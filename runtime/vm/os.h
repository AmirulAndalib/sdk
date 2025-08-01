// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_OS_H_
#define RUNTIME_VM_OS_H_

#include "vm/globals.h"

// Forward declarations.
struct tm;
namespace dart {

// Forward declarations.
class Zone;

// Interface to the underlying OS platform.
class OS {
 public:
  // Returns the name of the given OS. For example "linux".
  static const char* Name() { return kHostOperatingSystemName; }

  // Returns the current process id.
  static intptr_t ProcessId();

  // Returns a time-zone name for the given instant.
  // The name is provided by the underlying platform.
  // The returned string may be Zone allocated.
  static const char* GetTimeZoneName(int64_t seconds_since_epoch);

  // Returns the difference in seconds between local time and UTC for the given
  // instant.
  // For example 3600 for CET, and 7200 for CEST.
  static int GetTimeZoneOffsetInSeconds(int64_t seconds_since_epoch);

  // Returns the current time in milliseconds measured
  // from midnight January 1, 1970 UTC.
  static int64_t GetCurrentTimeMillis();

  // Returns the current time in microseconds measured
  // from midnight January 1, 1970 UTC.
  static int64_t GetCurrentTimeMicros();

  // Returns the current time used by the tracing infrastructure.
  static int64_t GetCurrentMonotonicMicros();

  // Returns the raw clock value from the monotonic clock.
  static int64_t GetCurrentMonotonicTicks();

  // Returns the frequency of the monotonic clock.
  static int64_t GetCurrentMonotonicFrequency();

  // Returns the value of current thread's CPU usage clock in microseconds.
  // NOTE: This clock will return different values depending on the calling
  // thread. It is only expected to increase in value as the thread uses
  // CPU time.
  // NOTE: This function will return -1 on OSs that are not supported.
  static int64_t GetCurrentThreadCPUMicros();

  // If the tracing/timeline configuration on takes timestamps as input, returns
  // the same value as |GetCurrentMonotonicMicros|. Otherwise, returns -1.
  static int64_t GetCurrentMonotonicMicrosForTimeline();

  // Returns the activation frame alignment constraint or one if
  // the platform doesn't care. Guaranteed to be a power of two.
  static intptr_t ActivationFrameAlignment();

  // Returns number of available processor cores.
  static int NumberOfAvailableProcessors();

  // Returns the current resident set size in bytes, or 0 if it could not be
  // determined.
  static uintptr_t CurrentRSS();

  // Sleep the currently executing thread for millis ms.
  static void Sleep(int64_t millis);

  // Sleep the currently executing thread for micros microseconds.
  static void SleepMicros(int64_t micros);

  // Debug break.
  static void DebugBreak();

  // Returns the current program counter.
  static uintptr_t GetProgramCounter();

  // Print formatted output to stdout/stderr for debugging.
  // Tracing and debugging prints from the VM should strongly prefer to use
  // PrintErr to avoid interfering with the application's output, which may
  // be parsed by another program.
  static void Print(const char* format, ...) PRINTF_ATTRIBUTE(1, 2);
  static void PrintErr(const char* format, ...) PRINTF_ATTRIBUTE(1, 2);
  static void VFPrint(FILE* stream, const char* format, va_list args);

  // Allocate a string and print formatted output into the buffer.
  // Uses the zone for allocation if one if provided, and otherwise uses
  // malloc.
  static char* SCreate(Zone* zone, const char* format, ...)
      PRINTF_ATTRIBUTE(2, 3);
  static char* VSCreate(Zone* zone, const char* format, va_list args);

  // Converts the initial portion of a C string which represents a valid dart
  // integer into a 64 bit value.
  //
  // Returns false if it is unable to convert the string to a 64 bit value,
  // the failure could be because of underflow/overflow or invalid characters.
  //
  // On success the function returns true, 'value' contains the converted
  // value, and 'end' contains a pointer to the next character
  // after the parsed integer.
  static bool ParseInitialInt64(const char* str, int64_t* value, char** end);

  // Converts a C string which represents a valid dart integer into a 64 bit
  // value.
  // Returns false if it is unable to convert the string to a 64 bit value,
  // the failure could be because of underflow/overflow or invalid characters.
  // On success the function returns true and 'value' contains the converted
  // value.
  static bool StringToInt64(const char* str, int64_t* value) {
    char* endptr = nullptr;
    return ParseInitialInt64(str, value, &endptr) && (*endptr == '\0');
  }

  // Register code observers relevant to this OS.
  static void RegisterCodeObservers();

  // Initialize the OS class.
  static void Init();

  // Cleanup the OS class.
  static void Cleanup();

  // Only implemented on Windows, prevents cleanup code from running.
  static void PrepareToAbort();

  DART_NORETURN static void Abort();

  DART_NORETURN static void Exit(int code);

  // Retrieves the DSO base for the given instructions image.
  static const uint8_t* GetAppDSOBase(const uint8_t* snapshot_instructions);
  static uword GetAppDSOBase(uword snapshot_instructions) {
    return reinterpret_cast<uword>(
        GetAppDSOBase(reinterpret_cast<const uint8_t*>(snapshot_instructions)));
  }

  struct BuildId {
    intptr_t len;
    const uint8_t* data;
  };

  // Retrieves the build ID information for the given instructions image.
  // If found, returns a BuildId with the length of the build ID and a pointer
  // to its contents, otherwise returns a BuildId with contents {0, nullptr}.
  static BuildId GetAppBuildId(const uint8_t* snapshot_instructions);
  static BuildId GetAppBuildId(uword snapshot_instructions) {
    return GetAppBuildId(
        reinterpret_cast<const uint8_t*>(snapshot_instructions));
  }
};

}  // namespace dart

#endif  // RUNTIME_VM_OS_H_
