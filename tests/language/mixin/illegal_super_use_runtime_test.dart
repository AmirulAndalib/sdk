// TODO(multitest): This was automatically migrated from a multitest and may
// contain strange or dead code.

// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";

mixin M {}

mixin P0 {
  foo() {
    void inner() {}
    inner();

    (() {})();

    return 42;
  }
}

mixin class P1 {
  bar() {
    return 87;
  }

  // The test method is strategically placed here to try to force the
  // P1 class and its bar method to be resolved before resolving the
  // mixin applications.
  test() {
    new C();
    var d = new D();
    var e = new E();
    var f = new F();
    Expect.equals(42, d.foo());
    Expect.equals(87, e.bar());
    Expect.equals(99, f.baz());
  }
}

mixin class P2 {
  baz() {
    return 99;
  }
}

class C = Object with M;
class D = Object with P0;
class E = Object with M, P1;
class F = Object with P2, M;

main() {
  var p1 = new P1();
  var p2 = new P2();
  Expect.equals(87, p1.bar());
  p1.test();
  Expect.equals(99, p2.baz());
}
