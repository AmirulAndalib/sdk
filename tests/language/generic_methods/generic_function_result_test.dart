// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.12

// Verify that function type parameter S can be resolved in bar's result type.
// Verify that generic function types are not allowed as type arguments.

import "package:expect/expect.dart";

int foo<T>(int i, int j) => i + j;

List<int Function<T>(S, int)> bar<S extends int>() {
// [error column 1]
// [cfe] A generic function type can't be used as a type argument.
//   ^^^^^^^^^^^^^^^^^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.GENERIC_FUNCTION_TYPE_CANNOT_BE_TYPE_ARGUMENT
  return <int Function<T>(S, int)>[foo, foo];
}

void main() {
  var list = bar<int>();
  print(list[0].runtimeType);
  Expect.equals(123, list[1](100, 23));
}
