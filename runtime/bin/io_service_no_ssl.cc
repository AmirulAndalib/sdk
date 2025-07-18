// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#if defined(DART_IO_SECURE_SOCKET_DISABLED)

#include "bin/io_service_no_ssl.h"

#include "bin/dartutils.h"
#include "bin/directory.h"
#include "bin/file.h"
#include "bin/io_buffer.h"
#include "bin/socket.h"
#include "bin/utils.h"

#include "include/dart_api.h"

#include "platform/globals.h"
#include "platform/utils.h"

namespace dart {
namespace bin {

#define CASE_REQUEST(type, method, id)                                         \
  case IOService::k##type##method##Request:                                    \
    response = type::method##Request(data);                                    \
    break;

void IOServiceCallback(Dart_Port dest_port_id, Dart_CObject* message) {
  Dart_Port reply_port_id = ILLEGAL_PORT;
  CObject* response = CObject::IllegalArgumentError();
  CObjectArray request(message);
  if ((message->type == Dart_CObject_kArray) && (request.Length() == 4) &&
      request[0]->IsInt32() && request[1]->IsSendPort() &&
      request[2]->IsInt32() && request[3]->IsArray()) {
    CObjectInt32 message_id(request[0]);
    CObjectSendPort reply_port(request[1]);
    CObjectInt32 request_id(request[2]);
    CObjectArray data(request[3]);
    reply_port_id = reply_port.Value();
    switch (request_id.Value()) {
      IO_SERVICE_REQUEST_LIST(CASE_REQUEST);
      default:
        UNREACHABLE();
    }
  }

  CObjectArray result(CObject::NewArray(2));
  result.SetAt(0, request[0]);
  result.SetAt(1, response);
  ASSERT(reply_port_id != ILLEGAL_PORT);
  Dart_PostCObject(reply_port_id, result.AsApiCObject());
}

intptr_t IOService::max_concurrency_ = 32;
std::atomic<Dart_Port> IOService::port_ = ILLEGAL_PORT;

Dart_Port IOService::GetServicePort() {
  Dart_Port port = port_;
  if (port == ILLEGAL_PORT) {
    port = Dart_NewConcurrentNativePort("IOService", IOServiceCallback,
                                        max_concurrency_);
    Dart_Port expected = ILLEGAL_PORT;
    if (!port_.compare_exchange_strong(expected, port)) {
      // Lost the initialization race. Use the winner's port and close our port.
      // The winner's port is eventually implicitly closed by VM shutdown.
      Dart_CloseNativePort(port);
      return expected;
    }
  }
  return port;
}

void FUNCTION_NAME(IOService_NewServicePort)(Dart_NativeArguments args) {
  Dart_Port service_port = IOService::GetServicePort();
  if (service_port != ILLEGAL_PORT) {
    // Return a send port for the service port.
    Dart_Handle send_port = Dart_NewSendPort(service_port);
    Dart_SetReturnValue(args, send_port);
  } else {
    // If port is not successfully created throw an error.
    Dart_PropagateError(
        DartUtils::NewInternalError("Unable to create native port"));
  }
}

}  // namespace bin
}  // namespace dart

#endif  // defined(DART_IO_SECURE_SOCKET_DISABLED)
