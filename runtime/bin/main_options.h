// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_BIN_MAIN_OPTIONS_H_
#define RUNTIME_BIN_MAIN_OPTIONS_H_

#include "bin/dartutils.h"
#include "bin/dfe.h"
#include "bin/options.h"
#include "platform/globals.h"
#include "platform/growable_array.h"
#include "platform/hashmap.h"

namespace dart {
namespace bin {

// A list of options taking string arguments. Organized as:
//   V(flag_name, field_name)
// The value of the flag can then be accessed with Options::field_name().
#define STRING_OPTIONS_LIST(V)                                                 \
  V(packages, packages_file)                                                   \
  V(snapshot, snapshot_filename)                                               \
  V(snapshot_depfile, snapshot_deps_filename)                                  \
  V(depfile, depfile)                                                          \
  V(depfile_output_filename, depfile_output_filename)                          \
  V(root_certs_file, root_certs_file)                                          \
  V(root_certs_cache, root_certs_cache)                                        \
  V(namespace, namespc)                                                        \
  V(write_service_info, vm_write_service_info_filename)                        \
  V(executable_name, executable_name)                                          \
  V(resolved_executable_name, resolved_executable_name)                        \
  /* The purpose of these flags is documented in */                            \
  /* pkg/dartdev/lib/src/commands/compilation_server.dart. */                  \
  V(resident_server_info_file, resident_server_info_file_path)                 \
  V(resident_compiler_info_file, resident_compiler_info_file_path)

// As STRING_OPTIONS_LIST but for boolean valued options. The default value is
// always false, and the presence of the flag switches the value to true.
#define BOOL_OPTIONS_LIST(V)                                                   \
  V(version, version_option)                                                   \
  V(compile_all, compile_all)                                                  \
  V(disable_service_origin_check, vm_service_dev_mode)                         \
  V(disable_service_auth_codes, vm_service_auth_disabled)                      \
  V(deterministic, deterministic)                                              \
  V(trace_loading, trace_loading)                                              \
  V(short_socket_read, short_socket_read)                                      \
  V(short_socket_write, short_socket_write)                                    \
  V(disable_exit, exit_disabled)                                               \
  V(suppress_core_dump, suppress_core_dump)                                    \
  V(enable_service_port_fallback, enable_service_port_fallback)                \
  V(long_ssl_cert_evaluation, long_ssl_cert_evaluation)                        \
  V(bypass_trusting_system_roots, bypass_trusting_system_roots)                \
  V(delayed_filewatch_callback, delayed_filewatch_callback)                    \
  V(mark_main_isolate_as_system_isolate, mark_main_isolate_as_system_isolate)  \
  V(no_serve_devtools, disable_devtools)                                       \
  V(serve_devtools, enable_devtools)                                           \
  V(no_serve_observatory, disable_observatory)                                 \
  V(serve_observatory, enable_observatory)                                     \
  V(print_dtd, print_dtd)                                                      \
  V(profile_microtasks, profile_microtasks)                                    \
  /* The purpose of this flag is documented in */                              \
  /* pkg/dartdev/lib/src/commands/run.dart. */                                 \
  V(resident, resident)

// Boolean flags that have a short form.
#define SHORT_BOOL_OPTIONS_LIST(V)                                             \
  V(h, help, help_option)                                                      \
  V(v, verbose, verbose_option)

#define DEBUG_BOOL_OPTIONS_LIST(V)                                             \
  V(force_load_from_memory, force_load_from_memory)

// A list of flags taking arguments from an enum. Organized as:
//   V(flag_name, enum_type, field_name)
// In main_options.cc there must be a list of strings that matches the enum
// called k{enum_type}Names. The field is not automatically declared in
// main_options.cc. It must be explicitly declared.
#define ENUM_OPTIONS_LIST(V)                                                   \
  V(snapshot_kind, SnapshotKind, gen_snapshot_kind)                            \
  V(verbosity, VerbosityLevel, verbosity)

// Callbacks passed to DEFINE_CB_OPTION().
#define CB_OPTIONS_LIST(V)                                                     \
  V(ProcessEnvironmentOption)                                                  \
  V(ProcessEnableVmServiceOption)                                              \
  V(ProcessObserveOption)                                                      \
  V(ProcessDdsOption)

// This enum must match the strings in kSnapshotKindNames in main_options.cc.
enum SnapshotKind {
  kNone,
  kKernel,
  kAppJIT,
};

enum VerbosityLevel {
  kError,
  kWarning,
  kInfo,
  kAll,
};

static const char* const kVerbosityLevelNames[] = {
    "error", "warning", "info", "all", nullptr,
};

class Options {
 public:
  // Returns true if argument parsing succeeded. False otherwise.
  static bool ParseArguments(int argc,
                             char** argv,
                             bool vm_run_app_snapshot,
                             bool parsing_dart_vm_options,
                             CommandLineOptions* vm_options,
                             char** script_name,
                             CommandLineOptions* dart_options,
                             bool* print_flags_seen);

#define STRING_OPTION_GETTER(flag, variable)                                   \
  static const char* variable() { return variable##_; }
  STRING_OPTIONS_LIST(STRING_OPTION_GETTER)
#undef STRING_OPTION_GETTER

#define BOOL_OPTION_GETTER(flag, variable)                                     \
  static bool variable() { return variable##_; }
  BOOL_OPTIONS_LIST(BOOL_OPTION_GETTER)
#if defined(DEBUG)
  DEBUG_BOOL_OPTIONS_LIST(BOOL_OPTION_GETTER)
#endif
#undef BOOL_OPTION_GETTER

#define SHORT_BOOL_OPTION_GETTER(short_name, long_name, variable)              \
  static bool variable() { return variable##_; }
  SHORT_BOOL_OPTIONS_LIST(SHORT_BOOL_OPTION_GETTER)
#undef SHORT_BOOL_OPTION_GETTER

#define ENUM_OPTIONS_GETTER(flag, type, variable)                              \
  static type variable() { return variable##_; }
  ENUM_OPTIONS_LIST(ENUM_OPTIONS_GETTER)
#undef ENUM_OPTIONS_GETTER

// Callbacks have to be public.
#define CB_OPTIONS_DECL(callback)                                              \
  static bool callback(const char* arg, CommandLineOptions* vm_options);
  CB_OPTIONS_LIST(CB_OPTIONS_DECL)
#undef CB_OPTIONS_DECL

  static dart::SimpleHashMap* environment() { return environment_; }

  static bool enable_vm_service() { return enable_vm_service_; }
#if !defined(PRODUCT)
  static const char* vm_service_server_ip() { return vm_service_server_ip_; }
  static int vm_service_server_port() { return vm_service_server_port_; }
#endif  // !defined(PRODUCT)
  static bool enable_dds() { return enable_dds_; }

  static Dart_KernelCompilationVerbosityLevel verbosity_level() {
    return VerbosityLevelToDartAPI(verbosity_);
  }
#if !defined(DART_PRECOMPILED_RUNTIME)
  static DFE* dfe() { return dfe_; }
  static void set_dfe(DFE* dfe) { dfe_ = dfe; }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

  static void PrintUsage();
  static void PrintVersion();

  static void Cleanup();

#if defined(DART_PRECOMPILED_RUNTIME)
  // Get the list of options in DART_VM_OPTIONS.
  static char** GetEnvArguments(int* argc);
#endif  // defined(DART_PRECOMPILED_RUNTIME)

 private:
  static void DestroyEnvironment();
#if defined(DART_PRECOMPILED_RUNTIME)
  static void DestroyEnvArgv();
#endif  // defined(DART_PRECOMPILED_RUNTIME)

#define STRING_OPTION_DECL(flag, variable) static const char* variable##_;
  STRING_OPTIONS_LIST(STRING_OPTION_DECL)
#undef STRING_OPTION_DECL

#define BOOL_OPTION_DECL(flag, variable) static bool variable##_;
  BOOL_OPTIONS_LIST(BOOL_OPTION_DECL)
#if defined(DEBUG)
  DEBUG_BOOL_OPTIONS_LIST(BOOL_OPTION_DECL)
#endif
#undef BOOL_OPTION_DECL

#define SHORT_BOOL_OPTION_DECL(short_name, long_name, variable)                \
  static bool variable##_;
  SHORT_BOOL_OPTIONS_LIST(SHORT_BOOL_OPTION_DECL)
#undef SHORT_BOOL_OPTION_DECL

#define ENUM_OPTION_DECL(flag, type, variable) static type variable##_;
  ENUM_OPTIONS_LIST(ENUM_OPTION_DECL)
#undef ENUM_OPTION_DECL

  static dart::SimpleHashMap* environment_;

#if defined(DART_PRECOMPILED_RUNTIME)
  static char** env_argv_;
  static int env_argc_;
#endif  // defined(DART_PRECOMPILED_RUNTIME)

// Frontend argument processing.
#if !defined(DART_PRECOMPILED_RUNTIME)
  static DFE* dfe_;
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

  static Dart_KernelCompilationVerbosityLevel VerbosityLevelToDartAPI(
      VerbosityLevel level) {
    switch (level) {
      case kError:
        return Dart_KernelCompilationVerbosityLevel_Error;
      case kWarning:
        return Dart_KernelCompilationVerbosityLevel_Warning;
      case kInfo:
        return Dart_KernelCompilationVerbosityLevel_Info;
      case kAll:
        return Dart_KernelCompilationVerbosityLevel_All;
      default:
        UNREACHABLE();
    }
  }

  // VM Service argument processing.
  static bool enable_vm_service_;
#if !defined(PRODUCT)
  static const char* vm_service_server_ip_;
  static int vm_service_server_port_;
#endif  // !defined(PRODUCT)
  static bool enable_dds_;

  static bool ExtractPortAndAddress(const char* option_value,
                                    int* out_port,
                                    const char** out_ip,
                                    int default_port,
                                    const char* default_ip);

#define OPTION_FRIEND(flag, variable) friend class OptionProcessor_##flag;
  STRING_OPTIONS_LIST(OPTION_FRIEND)
  BOOL_OPTIONS_LIST(OPTION_FRIEND)
#if defined(DEBUG)
  DEBUG_BOOL_OPTIONS_LIST(OPTION_FRIEND)
#endif
#undef OPTION_FRIEND

#define SHORT_BOOL_OPTION_FRIEND(short_name, long_name, variable)              \
  friend class OptionProcessor_##long_name;
  SHORT_BOOL_OPTIONS_LIST(SHORT_BOOL_OPTION_FRIEND)
#undef SHORT_BOOL_OPTION_FRIEND

#define ENUM_OPTION_FRIEND(flag, type, variable)                               \
  friend class OptionProcessor_##flag;
  ENUM_OPTIONS_LIST(ENUM_OPTION_FRIEND)
#undef ENUM_OPTION_FRIEND

  DISALLOW_ALLOCATION();
  DISALLOW_IMPLICIT_CONSTRUCTORS(Options);
};

}  // namespace bin
}  // namespace dart

#endif  // RUNTIME_BIN_MAIN_OPTIONS_H_
