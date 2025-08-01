// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/globals.h"
#include "vm/instructions.h"
#include "vm/signal_handler.h"
#include "vm/simulator.h"
#if defined(DART_HOST_OS_MACOS)

namespace dart {

uintptr_t SignalHandler::GetProgramCounter(const mcontext_t& mcontext) {
  uintptr_t pc = 0;

#if defined(HOST_ARCH_IA32)
  pc = static_cast<uintptr_t>(mcontext->__ss.__eip);
#elif defined(HOST_ARCH_X64)
  pc = static_cast<uintptr_t>(mcontext->__ss.__rip);
#elif defined(HOST_ARCH_ARM)
  pc = static_cast<uintptr_t>(mcontext->__ss.__pc);
#elif defined(HOST_ARCH_ARM64)
  pc = static_cast<uintptr_t>(mcontext->__ss.__pc);
#else
#error Unsupported architecture.
#endif  // HOST_ARCH_...

  return pc;
}

uintptr_t SignalHandler::GetFramePointer(const mcontext_t& mcontext) {
  uintptr_t fp = 0;

#if defined(HOST_ARCH_IA32)
  fp = static_cast<uintptr_t>(mcontext->__ss.__ebp);
#elif defined(HOST_ARCH_X64)
  fp = static_cast<uintptr_t>(mcontext->__ss.__rbp);
#elif defined(HOST_ARCH_ARM)
  fp = static_cast<uintptr_t>(mcontext->__ss.__r[7]);
#elif defined(HOST_ARCH_ARM64)
  fp = static_cast<uintptr_t>(mcontext->__ss.__fp);
#else
#error Unsupported architecture.
#endif  // HOST_ARCH_...

  return fp;
}

uintptr_t SignalHandler::GetCStackPointer(const mcontext_t& mcontext) {
  uintptr_t sp = 0;

#if defined(HOST_ARCH_IA32)
  sp = static_cast<uintptr_t>(mcontext->__ss.__esp);
#elif defined(HOST_ARCH_X64)
  sp = static_cast<uintptr_t>(mcontext->__ss.__rsp);
#elif defined(HOST_ARCH_ARM)
  sp = static_cast<uintptr_t>(mcontext->__ss.__sp);
#elif defined(HOST_ARCH_ARM64)
  sp = static_cast<uintptr_t>(mcontext->__ss.__sp);
#else
  UNIMPLEMENTED();
#endif  // HOST_ARCH_...

  return sp;
}

uintptr_t SignalHandler::GetDartStackPointer(const mcontext_t& mcontext) {
#if defined(TARGET_ARCH_ARM64) && !defined(DART_INCLUDE_SIMULATOR)
  return static_cast<uintptr_t>(mcontext->__ss.__x[SPREG]);
#else
  return GetCStackPointer(mcontext);
#endif
}

uintptr_t SignalHandler::GetLinkRegister(const mcontext_t& mcontext) {
  uintptr_t lr = 0;

#if defined(HOST_ARCH_IA32)
  lr = 0;
#elif defined(HOST_ARCH_X64)
  lr = 0;
#elif defined(HOST_ARCH_ARM)
  lr = static_cast<uintptr_t>(mcontext->__ss.__lr);
#elif defined(HOST_ARCH_ARM64)
  lr = static_cast<uintptr_t>(mcontext->__ss.__lr);
#else
#error Unsupported architecture.
#endif  // HOST_ARCH_...

  return lr;
}

void SignalHandler::Install(SignalAction action) {
  // Nothing to do on MacOS.
}

void SignalHandler::Remove() {
  // Nothing to do on MacOS.
}

}  // namespace dart

#endif  // defined(DART_HOST_OS_MACOS)
