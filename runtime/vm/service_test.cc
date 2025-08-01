// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include <memory>

#include "platform/globals.h"

#include "include/dart_tools_api.h"
#include "vm/dart_api_impl.h"
#include "vm/dart_entry.h"
#include "vm/debugger.h"
#include "vm/debugger_api_impl_test.h"
#include "vm/globals.h"
#include "vm/heap/safepoint.h"
#include "vm/message_handler.h"
#include "vm/message_snapshot.h"
#include "vm/object_id_ring.h"
#include "vm/os.h"
#include "vm/port.h"
#include "vm/profiler.h"
#include "vm/resolver.h"
#include "vm/service.h"
#include "vm/unit_test.h"

namespace dart {

// This flag is used in the Service_Flags test below.
DEFINE_FLAG(bool, service_testing_flag, false, "Comment");

#ifndef PRODUCT

class ServiceTestMessageHandler : public MessageHandler {
 public:
  ServiceTestMessageHandler() : _msg(nullptr) {}

  ~ServiceTestMessageHandler() {
    PortMap::ClosePorts(this);
    free(_msg);
  }

  MessageStatus HandleMessage(std::unique_ptr<Message> message) {
    if (_msg != nullptr) {
      free(_msg);
      _msg = nullptr;
    }

    // Parse the message.
    Object& response_obj = Object::Handle();
    if (message->IsRaw()) {
      response_obj = message->raw_obj();
    } else {
      Thread* thread = Thread::Current();
      response_obj = ReadMessage(thread, message.get());
    }
    if (response_obj.IsString()) {
      String& response = String::Handle();
      response ^= response_obj.ptr();
      _msg = Utils::StrDup(response.ToCString());
    } else {
      ASSERT(response_obj.IsArray());
      Array& response_array = Array::Handle();
      response_array ^= response_obj.ptr();
      ASSERT(response_array.Length() == 1);
      ExternalTypedData& response = ExternalTypedData::Handle();
      response ^= response_array.At(0);
      _msg = Utils::StrDup(reinterpret_cast<char*>(response.DataAddr(0)));
    }

    return kOK;
  }

  const char* msg() const { return _msg; }

  virtual Isolate* isolate() const { return Isolate::Current(); }

 private:
  char* _msg;
};

static ArrayPtr Eval(Dart_Handle lib, const char* expr) {
  const String& dummy_isolate_id = String::Handle(String::New("isolateId"));
  Dart_Handle expr_val;
  {
    TransitionVMToNative transition(Thread::Current());
    expr_val = Dart_EvaluateStaticExpr(lib, NewString(expr));
    EXPECT_VALID(expr_val);
  }
  Zone* zone = Thread::Current()->zone();
  const GrowableObjectArray& value =
      Api::UnwrapGrowableObjectArrayHandle(zone, expr_val);
  const Array& result = Array::Handle(Array::MakeFixedLength(value));
  GrowableObjectArray& growable = GrowableObjectArray::Handle();
  growable ^= result.At(5);
  // Append dummy isolate id to parameter values.
  growable.Add(dummy_isolate_id);
  Array& array = Array::Handle(Array::MakeFixedLength(growable));
  result.SetAt(5, array);
  growable ^= result.At(6);
  // Append dummy isolate id to parameter values.
  growable.Add(dummy_isolate_id);
  array = Array::MakeFixedLength(growable);
  result.SetAt(6, array);
  return result.ptr();
}

static ArrayPtr EvalF(Dart_Handle lib, const char* fmt, ...) {
  va_list measure_args;
  va_start(measure_args, fmt);
  intptr_t len = Utils::VSNPrint(nullptr, 0, fmt, measure_args);
  va_end(measure_args);

  char* buffer = Thread::Current()->zone()->Alloc<char>(len + 1);
  va_list print_args;
  va_start(print_args, fmt);
  Utils::VSNPrint(buffer, (len + 1), fmt, print_args);
  va_end(print_args);

  return Eval(lib, buffer);
}

static FunctionPtr GetFunction(const Class& cls, const char* name) {
  const Function& result = Function::Handle(Resolver::ResolveDynamicFunction(
      Thread::Current()->zone(), cls, String::Handle(String::New(name))));
  EXPECT(!result.IsNull());
  return result.ptr();
}

static ClassPtr GetClass(const Library& lib, const char* name) {
  const Class& cls = Class::Handle(
      lib.LookupClass(String::Handle(Symbols::New(Thread::Current(), name))));
  EXPECT(!cls.IsNull());  // No ambiguity error expected.
  return cls.ptr();
}

static void HandleIsolateMessage(Isolate* isolate, const Array& msg) {
  Service::HandleIsolateMessage(isolate, msg);
}

static void HandleRootMessage(const Array& message) {
  Service::HandleRootMessage(message);
}

ISOLATE_UNIT_TEST_CASE(Service_IsolateStickyError) {
  const char* kScript = "main() => throw 'HI THERE STICKY';\n";

  Isolate* isolate = thread->isolate();
  isolate->set_is_runnable(true);
  Dart_Handle result;
  {
    TransitionVMToNative transition(thread);
    Dart_Handle lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT(Dart_IsUnhandledExceptionError(result));
    EXPECT(!Dart_HasStickyError());
  }
  EXPECT(Thread::Current()->sticky_error() == Error::null());

  {
    JSONStream js;
    js.set_id_zone(isolate->EnsureDefaultServiceIdZone());
    isolate->PrintJSON(&js, false);
    // No error property and no PauseExit state.
    EXPECT_NOTSUBSTRING("\"error\":", js.ToCString());
    EXPECT_NOTSUBSTRING("HI THERE STICKY", js.ToCString());
    EXPECT_NOTSUBSTRING("PauseExit", js.ToCString());
  }

  {
    // Set the sticky error.
    TransitionVMToNative transition(thread);
    Dart_SetStickyError(result);
    Dart_SetPausedOnExit(true);
    EXPECT(Dart_HasStickyError());
  }

  {
    JSONStream js;
    js.set_id_zone(isolate->EnsureDefaultServiceIdZone());
    isolate->PrintJSON(&js, false);
    // Error and PauseExit set.
    EXPECT_SUBSTRING("\"error\":", js.ToCString());
    EXPECT_SUBSTRING("HI THERE STICKY", js.ToCString());
    EXPECT_SUBSTRING("PauseExit", js.ToCString());
  }
}

ISOLATE_UNIT_TEST_CASE(Service_RingServiceIdZonePolicies) {
  Zone* zone = thread->zone();

  const String& test_a = String::Handle(zone, String::New("a"));
  const String& test_b = String::Handle(zone, String::New("b"));
  const String& test_c = String::Handle(zone, String::New("c"));
  const String& test_d = String::Handle(zone, String::New("d"));

  const intptr_t kDefaultIdZoneId = 0;
  const int32_t kTestIdZoneCapacity = 32;

  // Always allocate a new id.
  RingServiceIdZone always_allocate_zone(
      kDefaultIdZoneId, ObjectIdRing::kAllocateId, kTestIdZoneCapacity);
  EXPECT_STREQ("objects/0/0", always_allocate_zone.GetServiceId(test_a));
  EXPECT_STREQ("objects/1/0", always_allocate_zone.GetServiceId(test_a));
  EXPECT_STREQ("objects/2/0", always_allocate_zone.GetServiceId(test_a));
  EXPECT_STREQ("objects/3/0", always_allocate_zone.GetServiceId(test_b));
  EXPECT_STREQ("objects/4/0", always_allocate_zone.GetServiceId(test_c));

  // Reuse an existing id or allocate a new id.
  RingServiceIdZone reuse_existing_zone(
      kDefaultIdZoneId, ObjectIdRing::kReuseId, kTestIdZoneCapacity);
  EXPECT_STREQ("objects/0/0", reuse_existing_zone.GetServiceId(test_a));
  EXPECT_STREQ("objects/0/0", reuse_existing_zone.GetServiceId(test_a));
  EXPECT_STREQ("objects/1/0", reuse_existing_zone.GetServiceId(test_b));
  EXPECT_STREQ("objects/1/0", reuse_existing_zone.GetServiceId(test_b));
  EXPECT_STREQ("objects/2/0", reuse_existing_zone.GetServiceId(test_c));
  EXPECT_STREQ("objects/2/0", reuse_existing_zone.GetServiceId(test_c));
  EXPECT_STREQ("objects/3/0", reuse_existing_zone.GetServiceId(test_d));
  EXPECT_STREQ("objects/3/0", reuse_existing_zone.GetServiceId(test_d));
}

ISOLATE_UNIT_TEST_CASE(Service_Code) {
  const char* kScript =
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "class A {\n"
      "  var a;\n"
      "  dynamic b() {}\n"
      "  dynamic c() {\n"
      "    var d = () { b(); };\n"
      "    return d;\n"
      "  }\n"
      "}\n"
      "main() {\n"
      "  var z = new A();\n"
      "  var x = z.c();\n"
      "  x();\n"
      "}";

  SetFlagScope<bool> sfs(&FLAG_verify_entry_points, false);
  Isolate* isolate = thread->isolate();
  isolate->set_is_runnable(true);
  Dart_Handle lib;
  Library& vmlib = Library::Handle();
  {
    TransitionVMToNative transition(thread);
    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    EXPECT(!Dart_IsNull(lib));
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);
  }
  vmlib ^= Api::UnwrapHandle(lib);
  EXPECT(!vmlib.IsNull());
  const Class& class_a = Class::Handle(GetClass(vmlib, "A"));
  EXPECT(!class_a.IsNull());
  const Function& function_c = Function::Handle(GetFunction(class_a, "c"));
  EXPECT(!function_c.IsNull());
  const Code& code_c = Code::Handle(function_c.CurrentCode());
  EXPECT(!code_c.IsNull());
  // Use the entry of the code object as it's reference.
  uword entry = code_c.PayloadStart();
  int64_t compile_timestamp = code_c.compile_timestamp();
  EXPECT_GT(code_c.Size(), 16u);
  uword last = entry + code_c.Size();

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Array& service_msg = Array::Handle();

  // Request an invalid code object.
  service_msg =
      Eval(lib, "[0, port, '0', 'getObject', false, ['objectId'], ['code/0']]");
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_SUBSTRING("\"error\"", handler.msg());

  // The following test checks that a code object can be found only
  // at compile_timestamp()-code.EntryPoint().
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, "
                      "['objectId'], ['code/%" Px64 "-%" Px "']]",
                      compile_timestamp, entry);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_SUBSTRING("\"type\":\"Code\"", handler.msg());
  {
    // Only perform a partial match.
    const intptr_t kBufferSize = 512;
    char buffer[kBufferSize];
    Utils::SNPrint(buffer, kBufferSize - 1,
                   "\"fixedId\":true,\"id\":\"code\\/%" Px64 "-%" Px "\",",
                   compile_timestamp, entry);
    EXPECT_SUBSTRING(buffer, handler.msg());
  }

  // Request code object at compile_timestamp-code.EntryPoint() + 16
  // Expect this to fail because the address is not the entry point.
  uintptr_t address = entry + 16;
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, "
                      "['objectId'], ['code/%" Px64 "-%" Px "']]",
                      compile_timestamp, address);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_SUBSTRING("\"error\"", handler.msg());

  // Request code object at (compile_timestamp - 1)-code.EntryPoint()
  // Expect this to fail because the timestamp is wrong.
  address = entry;
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, "
                      "['objectId'], ['code/%" Px64 "-%" Px "']]",
                      compile_timestamp - 1, address);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_SUBSTRING("\"error\"", handler.msg());

  // Request native code at address. Expect the null code object back.
  address = last;
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, "
                      "['objectId'], ['code/native-%" Px "']]",
                      address);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  // TODO(turnidge): It is pretty broken to return an Instance here.  Fix.
  EXPECT_SUBSTRING("\"kind\":\"Null\"", handler.msg());

  // Request malformed native code.
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, ['objectId'], "
                      "['code/native%" Px "']]",
                      address);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_SUBSTRING("\"error\"", handler.msg());
}

ISOLATE_UNIT_TEST_CASE(Service_PcDescriptors) {
  const char* kScript =
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "class A {\n"
      "  var a;\n"
      "  dynamic b() {}\n"
      "  dynamic c() {\n"
      "    var d = () { b(); };\n"
      "    return d;\n"
      "  }\n"
      "}\n"
      "main() {\n"
      "  var z = new A();\n"
      "  var x = z.c();\n"
      "  x();\n"
      "}";

  SetFlagScope<bool> sfs(&FLAG_verify_entry_points, false);
  Isolate* isolate = thread->isolate();
  isolate->set_is_runnable(true);
  Dart_Handle lib;
  Library& vmlib = Library::Handle();
  {
    TransitionVMToNative transition(thread);
    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    EXPECT(!Dart_IsNull(lib));
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);
  }
  vmlib ^= Api::UnwrapHandle(lib);
  EXPECT(!vmlib.IsNull());
  const Class& class_a = Class::Handle(GetClass(vmlib, "A"));
  EXPECT(!class_a.IsNull());
  const Function& function_c = Function::Handle(GetFunction(class_a, "c"));
  EXPECT(!function_c.IsNull());
  const Code& code_c = Code::Handle(function_c.CurrentCode());
  EXPECT(!code_c.IsNull());

  const PcDescriptors& descriptors =
      PcDescriptors::Handle(code_c.pc_descriptors());
  EXPECT(!descriptors.IsNull());
  ServiceIdZone& default_id_zone = isolate->EnsureDefaultServiceIdZone();
  const char* id = default_id_zone.GetServiceId(descriptors);

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Array& service_msg = Array::Handle();

  // Fetch object.
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, "
                      "['objectId'], ['%s']]",
                      id);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  // Check type.
  EXPECT_SUBSTRING("\"type\":\"Object\"", handler.msg());
  EXPECT_SUBSTRING("\"_vmType\":\"PcDescriptors\"", handler.msg());
  // Check for members array.
  EXPECT_SUBSTRING("\"members\":[", handler.msg());
}

ISOLATE_UNIT_TEST_CASE(Service_LocalVarDescriptors) {
  const char* kScript =
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "class A {\n"
      "  var a;\n"
      "  dynamic b() {}\n"
      "  dynamic c() {\n"
      "    var d = () { b(); };\n"
      "    return d;\n"
      "  }\n"
      "}\n"
      "main() {\n"
      "  var z = new A();\n"
      "  var x = z.c();\n"
      "  x();\n"
      "}";

  SetFlagScope<bool> sfs(&FLAG_verify_entry_points, false);
  Isolate* isolate = thread->isolate();
  isolate->set_is_runnable(true);
  Dart_Handle lib;
  Library& vmlib = Library::Handle();
  {
    TransitionVMToNative transition(thread);
    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    EXPECT(!Dart_IsNull(lib));
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);
  }
  vmlib ^= Api::UnwrapHandle(lib);
  EXPECT(!vmlib.IsNull());
  const Class& class_a = Class::Handle(GetClass(vmlib, "A"));
  EXPECT(!class_a.IsNull());
  const Function& function_c = Function::Handle(GetFunction(class_a, "c"));
  EXPECT(!function_c.IsNull());
  const Code& code_c = Code::Handle(function_c.CurrentCode());
  EXPECT(!code_c.IsNull());

  const LocalVarDescriptors& descriptors =
      LocalVarDescriptors::Handle(code_c.GetLocalVarDescriptors());
  // Generate an ID for this object.
  ServiceIdZone& default_id_zone = isolate->EnsureDefaultServiceIdZone();
  const char* id = default_id_zone.GetServiceId(descriptors);

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Array& service_msg = Array::Handle();

  // Fetch object.
  service_msg = EvalF(lib,
                      "[0, port, '0', 'getObject', false, "
                      "['objectId'], ['%s']]",
                      id);
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  // Check type.
  EXPECT_SUBSTRING("\"type\":\"Object\"", handler.msg());
  EXPECT_SUBSTRING("\"_vmType\":\"LocalVarDescriptors\"", handler.msg());
  // Check for members array.
  EXPECT_SUBSTRING("\"members\":[", handler.msg());
}

static void WeakHandleFinalizer(void* isolate_callback_data, void* peer) {}

ISOLATE_UNIT_TEST_CASE(Service_PersistentHandles) {
  const char* kScript =
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "class A {\n"
      "  var a;\n"
      "}\n"
      "var global = new A();\n"
      "main() {\n"
      "  return global;\n"
      "}";

  SetFlagScope<bool> sfs(&FLAG_verify_entry_points, false);
  Isolate* isolate = thread->isolate();
  isolate->set_is_runnable(true);

  Dart_Handle lib;
  Dart_PersistentHandle persistent_handle;
  Dart_WeakPersistentHandle weak_persistent_handle;
  {
    TransitionVMToNative transition(thread);
    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);

    // Create a persistent handle to global.
    persistent_handle = Dart_NewPersistentHandle(result);

    // Create a weak persistent handle to global.
    weak_persistent_handle = Dart_NewWeakPersistentHandle(
        result, reinterpret_cast<void*>(0xdeadbeef), 128, WeakHandleFinalizer);
  }

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Array& service_msg = Array::Handle();

  // Get persistent handles.
  service_msg =
      Eval(lib, "[0, port, '0', '_getPersistentHandles', false, [], []]");
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  // Look for a heart beat.
  EXPECT_SUBSTRING("\"type\":\"_PersistentHandles\"", handler.msg());
  EXPECT_SUBSTRING("\"peer\":\"0xdeadbeef\"", handler.msg());
  EXPECT_SUBSTRING("\"name\":\"A\"", handler.msg());
  EXPECT_SUBSTRING("\"externalSize\":\"128\"", handler.msg());

  // Delete persistent handles.
  {
    TransitionVMToNative transition(thread);
    Dart_DeletePersistentHandle(persistent_handle);
    Dart_DeleteWeakPersistentHandle(weak_persistent_handle);
  }

  // Get persistent handles (again).
  service_msg =
      Eval(lib, "[0, port, '0', '_getPersistentHandles', false, [], []]");
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_SUBSTRING("\"type\":\"_PersistentHandles\"", handler.msg());
  // Verify that old persistent handles are not present.
  EXPECT_NOTSUBSTRING("\"peer\":\"0xdeadbeef\"", handler.msg());
  EXPECT_NOTSUBSTRING("\"name\":\"A\"", handler.msg());
  EXPECT_NOTSUBSTRING("\"externalSize\":\"128\"", handler.msg());
}

static bool alpha_callback(const char* name,
                           const char** option_keys,
                           const char** option_values,
                           intptr_t num_options,
                           void* user_data,
                           const char** result) {
  *result = Utils::StrDup("alpha");
  return true;
}

static bool beta_callback(const char* name,
                          const char** option_keys,
                          const char** option_values,
                          intptr_t num_options,
                          void* user_data,
                          const char** result) {
  *result = Utils::StrDup("beta");
  return false;
}

ISOLATE_UNIT_TEST_CASE(Service_EmbedderRootHandler) {
  const char* kScript =
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "var x = 7;\n"
      "main() {\n"
      "  x = x * x;\n"
      "  x = (x / 13).floor();\n"
      "}";

  SetFlagScope<bool> sfs(&FLAG_verify_entry_points, false);
  Dart_Handle lib;
  {
    TransitionVMToNative transition(thread);

    Dart_RegisterRootServiceRequestCallback("alpha", alpha_callback, nullptr);
    Dart_RegisterRootServiceRequestCallback("beta", beta_callback, nullptr);

    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);
  }

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Array& service_msg = Array::Handle();
  service_msg = Eval(lib, "[0, port, '\"', 'alpha', false, [], []]");
  HandleRootMessage(service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_STREQ("{\"jsonrpc\":\"2.0\", \"result\":alpha,\"id\":\"\\\"\"}",
               handler.msg());
  service_msg = Eval(lib, "[0, port, 1, 'beta', false, [], []]");
  HandleRootMessage(service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_STREQ("{\"jsonrpc\":\"2.0\", \"error\":beta,\"id\":1}", handler.msg());
}

ISOLATE_UNIT_TEST_CASE(Service_EmbedderIsolateHandler) {
  const char* kScript =
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "var x = 7;\n"
      "main() {\n"
      "  x = x * x;\n"
      "  x = (x / 13).floor();\n"
      "}";

  SetFlagScope<bool> sfs(&FLAG_verify_entry_points, false);
  Dart_Handle lib;
  {
    TransitionVMToNative transition(thread);

    Dart_RegisterIsolateServiceRequestCallback("alpha", alpha_callback,
                                               nullptr);
    Dart_RegisterIsolateServiceRequestCallback("beta", beta_callback, nullptr);

    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);
  }

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Isolate* isolate = thread->isolate();
  Array& service_msg = Array::Handle();
  service_msg = Eval(lib, "[0, port, '0', 'alpha', false, [], []]");
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_STREQ("{\"jsonrpc\":\"2.0\", \"result\":alpha,\"id\":\"0\"}",
               handler.msg());
  service_msg = Eval(lib, "[0, port, '0', 'beta', false, [], []]");
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  EXPECT_STREQ("{\"jsonrpc\":\"2.0\", \"error\":beta,\"id\":\"0\"}",
               handler.msg());
}

// TODO(zra): Remove when tests are ready to enable.
#if !defined(TARGET_ARCH_ARM64)

static void EnableProfiler() {
  if (!FLAG_profiler) {
    FLAG_profiler = true;
    Profiler::Init();
  }
}

ISOLATE_UNIT_TEST_CASE(Service_Profile) {
  EnableProfiler();
  const char* kScript =
      "@pragma('vm:entry-point', 'set')\n"
      "var port;\n"  // Set to our mock port by C++.
      "\n"
      "var x = 7;\n"
      "main() {\n"
      "  x = x * x;\n"
      "  x = (x / 13).floor();\n"
      "}";

  Isolate* isolate = thread->isolate();
  isolate->set_is_runnable(true);
  Dart_Handle lib;
  {
    TransitionVMToNative transition(thread);

    lib = TestCase::LoadTestScript(kScript, nullptr);
    EXPECT_VALID(lib);
    Dart_Handle result = Dart_Invoke(lib, NewString("main"), 0, nullptr);
    EXPECT_VALID(result);
  }

  // Build a mock message handler and wrap it in a dart port.
  ServiceTestMessageHandler handler;
  Dart_Port port_id = PortMap::CreatePort(&handler);
  Dart_Handle port = Api::NewHandle(thread, SendPort::New(port_id));
  {
    TransitionVMToNative transition(thread);
    EXPECT_VALID(port);
    EXPECT_VALID(Dart_SetField(lib, NewString("port"), port));
  }

  Array& service_msg = Array::Handle();
  service_msg = Eval(lib, "[0, port, '0', 'getCpuSamples', false, [], []]");
  HandleIsolateMessage(isolate, service_msg);
  EXPECT_EQ(MessageHandler::kOK, handler.HandleNextMessage());
  // Expect profile
  EXPECT_SUBSTRING("\"type\":\"CpuSamples\"", handler.msg());
}

#endif  // !defined(TARGET_ARCH_ARM64)

ISOLATE_UNIT_TEST_CASE(Service_ParseJSONArray) {
  {
    const auto& elements =
        GrowableObjectArray::Handle(GrowableObjectArray::New());
    EXPECT_EQ(-1, ParseJSONArray(thread, "", elements));
    EXPECT_EQ(-1, ParseJSONArray(thread, "[", elements));
  }

  {
    const auto& elements =
        GrowableObjectArray::Handle(GrowableObjectArray::New());
    EXPECT_EQ(0, ParseJSONArray(thread, "[]", elements));
    EXPECT_EQ(0, elements.Length());
  }

  {
    const auto& elements =
        GrowableObjectArray::Handle(GrowableObjectArray::New());
    EXPECT_EQ(0, ParseJSONArray(thread, "[a]", elements));
    EXPECT_EQ(1, elements.Length());
    auto& element = String::Handle();
    element ^= elements.At(0);
    EXPECT(element.Equals("a"));
  }

  {
    const auto& elements =
        GrowableObjectArray::Handle(GrowableObjectArray::New());
    EXPECT_EQ(0, ParseJSONArray(thread, "[abc, def]", elements));
    EXPECT_EQ(2, elements.Length());
    auto& element = String::Handle();
    element ^= elements.At(0);
    EXPECT(element.Equals("abc"));
    element ^= elements.At(1);
    EXPECT(element.Equals("def"));
  }

  {
    const auto& elements =
        GrowableObjectArray::Handle(GrowableObjectArray::New());
    EXPECT_EQ(0, ParseJSONArray(thread, "[abc, def, ghi]", elements));
    EXPECT_EQ(3, elements.Length());
    auto& element = String::Handle();
    element ^= elements.At(0);
    EXPECT(element.Equals("abc"));
    element ^= elements.At(1);
    EXPECT(element.Equals("def"));
    element ^= elements.At(2);
    EXPECT(element.Equals("ghi"));
  }

  {
    const auto& elements =
        GrowableObjectArray::Handle(GrowableObjectArray::New());
    EXPECT_EQ(0, ParseJSONArray(thread, "[abc, , ghi]", elements));
    EXPECT_EQ(3, elements.Length());
    auto& element = String::Handle();
    element ^= elements.At(0);
    EXPECT(element.Equals("abc"));
    element ^= elements.At(1);
    EXPECT(element.Equals(""));
    element ^= elements.At(2);
    EXPECT(element.Equals("ghi"));
  }
}

#endif  // !PRODUCT

}  // namespace dart
