// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

import "package:expect/expect.dart";

class C<
        D //# 01: compile-time error
        E //# none: ok
         > {
  void set D(int value) {
    field = value;
  }

  int field = -1;
}

main() {
  C<int> c = new C<int>();
  c.D = 1;
  Expect.equals(c.field, 1);
}
