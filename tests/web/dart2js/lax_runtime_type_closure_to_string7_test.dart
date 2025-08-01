// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2jsOptions=--omit-implicit-checks --lax-runtime-type-to-string

import 'package:expect/expect.dart';
import 'package:expect/variations.dart';
import 'dart:_foreign_helper' show JS_GET_FLAG;

class Class<T> {
  Class();
}

@pragma('dart2js:noInline')
test<Q>() {
  Q? local1(Q) {}
  local2(int i) => i;

  var toString = '${local1.runtimeType}';
  if (!toString.contains('minified:')) {
    if (!rtiOptimizationsDisabled) {
      // `true` if non-minified.
      Expect.equals("Closure", toString);
    }
  }
  print(toString);
  local2(0);
  new Class();
}

main() {
  test<int>();
  test<String>();
}
