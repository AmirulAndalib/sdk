// TODO(multitest): This was automatically migrated from a multitest and may
// contain strange or dead code.

// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class S0 {}

class S1 extends Object {}

class S2 extends S0 {}

mixin class M0 {}

mixin class M1 extends Object {}

class M2 extends M0 {}

class C00 = S0 with M0;
class C01 = S0 with M1;

class C03 = S0 with M0, M1;

class C10 = S1 with M0;
class C11 = S1 with M1;

class C13 = S1 with M0, M1;

class C20 = S2 with M0;
class C21 = S2 with M1;

class C23 = S2 with M0, M1;

class D00 extends S0 with M0 {}

class D01 extends S0 with M1 {}

class D03 extends S0 with M0, M1 {}

class D10 extends S1 with M0 {}

class D11 extends S1 with M1 {}

class D13 extends S1 with M0, M1 {}

class D20 extends S2 with M0 {}

class D21 extends S2 with M1 {}

class D23 extends S2 with M0, M1 {}

main() {
  new C00();
  new C01();

  new C03();

  new C10();
  new C11();

  new C13();

  new C20();
  new C21();

  new C23();

  new D00();
  new D01();

  new D03();

  new D10();
  new D11();

  new D13();

  new D20();
  new D21();

  new D23();
}
