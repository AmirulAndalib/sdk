// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

class C<X> {
  C(Type t) {
    Expect.equals(t, X);
  }
}

typedef T<X> = C<List<X>>;

Type typeOf<X>() => X;

void main() {
  T<num> x1 = T(typeOf<List<num>>());
  C<Iterable<num>> x2 = T(typeOf<List<num>>());
}
