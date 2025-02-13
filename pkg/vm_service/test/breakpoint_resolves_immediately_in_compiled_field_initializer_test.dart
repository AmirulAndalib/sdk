// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:developer' show debugger;

import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart pkg/vm_service/test/breakpoint_resolves_immediately_in_compiled_field_initializer_test.dart
//
const LINE_A = 28;
const LINE_B = 34;
// AUTOGENERATED END

int getTwo() => 3;

int getThree() => 3;

class C {
  static int x = getTwo() + getThree(); // LINE_A
}

Future<void> testeeMain() async {
  final y = C.x;
  print(y);
  debugger(); // LINE_B
}

final tests = <IsolateTest>[
  // Ensure that the main isolate has stopped at the [debugger] statement at the
  // end of [testeeMain].
  hasStoppedAtBreakpoint,
  stoppedAtLine(LINE_B),
  (VmService service, IsolateRef isolateRef) async {
    final isolateId = isolateRef.id!;
    final isolate = await service.getIsolate(isolateId);
    final rootLib = await service.getObject(
      isolateId,
      isolate.rootLib!.id!,
    ) as Library;
    final scriptId = rootLib.scripts![0].id!;

    // Add a breakpoint at the initializer of `C.x`.
    final breakpoint = await service.addBreakpoint(isolateId, scriptId, LINE_A);
    // It is guaranteed that the initializer of `C.x` has been compiled at this
    // point, because `C.x` was already used to initialize `y`, so we ensure
    // that the newly set breakpoint has been resolved immediately.
    expect(breakpoint.resolved, true);
  },
];

void main([args = const <String>[]]) => runIsolateTests(
      args,
      tests,
      'breakpoint_resolves_immediately_in_compiled_field_initializer_test.dart',
      testeeConcurrent: testeeMain,
    );
