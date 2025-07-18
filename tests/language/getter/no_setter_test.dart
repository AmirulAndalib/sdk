// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Verifies behavior with a static getter, but no field and no setter.

import "package:expect/expect.dart";

class Example {
  static int _var = 1;
  static int get nextVar => _var++;
  Example() {
    nextVar = 1;
    // [error column 5, length 7]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_NO_SETTER
    // [cfe] Setter not found: 'nextVar'.
    this.nextVar = 1;
    //   ^^^^^^^
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_NO_SETTER
    // [cfe] The setter 'nextVar' isn't defined for the type 'Example'.
  }
  static test() {
    nextVar = 0;
    // [error column 5, length 7]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_NO_SETTER
    // [cfe] Setter not found: 'nextVar'.
    this.nextVar = 0;
    // [error column 5, length 4]
    // [analyzer] COMPILE_TIME_ERROR.INVALID_REFERENCE_TO_THIS
    // [cfe] Expected identifier, but got 'this'.
    //   ^^^^^^^
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_NO_SETTER
  }
}

class Example1 {
  Example1(int i) {}
}

class Example2 extends Example1 {
  static int _var = 1;
  static int get nextVar => _var++;
  Example2() : super(nextVar) {} // No 'this' in scope.
}

void main() {
  Example x = new Example();
  Example.test();
  Example2 x2 = new Example2();
}
