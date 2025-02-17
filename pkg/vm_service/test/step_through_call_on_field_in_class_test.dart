// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart pkg/vm_service/test/step_through_call_on_field_in_class_test.dart
//
const LINE_A = 19;
// AUTOGENERATED END

const file = 'step_through_call_on_field_in_class_test.dart';

void code() /* LINE_A */ {
  final foo = Foo();
  foo.foo = foo.fooMethod;
  foo.fooMethod();
  foo.foo();
}

class Foo {
  late Function() foo;

  void fooMethod() {
    print('Hello from fooMethod');
  }
}

final stops = <String>[];
const expected = <String>[
  '$file:${LINE_A + 0}:10', // after "code", i.e. on "("
  '$file:${LINE_A + 1}:15', // on "Foo"
  '$file:${LINE_A + 2}:17', // on "fooMethod"
  '$file:${LINE_A + 2}:7', // on "foo"
  '$file:${LINE_A + 3}:7', // on "fooMethod"
  '$file:${LINE_A + 4}:7', // on "foo"
  '$file:${LINE_A + 5}:1', // on ending '}'
];

final tests = <IsolateTest>[
  hasPausedAtStart,
  setBreakpointAtLine(LINE_A),
  runStepThroughProgramRecordingStops(stops),
  checkRecordedStops(stops, expected),
];

void main(args) => runIsolateTests(
      args,
      tests,
      'step_through_call_on_field_in_class_test.dart',
      testeeConcurrent: code,
      pauseOnStart: true,
      pauseOnExit: true,
    );
