// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Dart test for testing Math.min and Math.max.

import "package:expect/expect.dart";
import 'package:expect/variations.dart' as v;

negate(x) => -x;

main() {
  // Test matrix:
  var minNonZero = 5e-324;
  var maxDenormal = 2.225073858507201e-308;
  var minNormal = 2.2250738585072014e-308;
  var maxFraction = 0.9999999999999999;
  var minAbove1 = 1.0000000000000002;
  var maxNonInt = 4503599627370495.5;
  var maxNonIntFloorAsInt = maxNonInt.floor();
  var maxNonIntFloorAsDouble = maxNonIntFloorAsInt.toDouble();
  var maxExactIntAsDouble = 9007199254740992.0;
  var maxExactIntAsInt = 9007199254740992;
  // Can't use 1 << 53 with web numbers. 2^53 = (2^10)^5 * 2^3.
  int two53 = 1024 * 1024 * 1024 * 1024 * 1024 * 8; // Same as maxExactIntAsInt.
  var two53p1 = two53 + 1;
  var maxFiniteAsDouble = 1.7976931348623157e+308;
  var maxFiniteAsInt = maxFiniteAsDouble.truncate();
  var inf = double.infinity;
  var nan = double.nan;
  var mnan = negate(nan);
  var minInt64 = -0x8000000000000000;
  var minInt64AsDouble = minInt64.toDouble();
  // Split 0x7fffffffffffffff into sum of two web numbers. When compiled to
  // JavaScript the sum will round up.
  var maxInt64 = 0x7ffffffffffff000 + 0xfff;
  var maxInt64AsDouble = maxInt64.toDouble(); // 1 << 63
  var matrix = [
    -inf,
    -maxFiniteAsDouble,
    [minInt64, if (!v.jsNumbers) minInt64AsDouble],
    if (!v.jsNumbers) [-maxInt64, -maxFiniteAsInt],
    if (!v.jsNumbers) -two53p1,
    [-two53, -maxExactIntAsInt, -maxExactIntAsDouble],
    -maxNonInt,
    [-maxNonIntFloorAsDouble, -maxNonIntFloorAsInt],
    [-499.0, -499],
    -minAbove1,
    [-1.0, -1],
    -maxFraction,
    -minNormal,
    -maxDenormal,
    -minNonZero,
    -0.0,
    [0, 0, 0],
    minNonZero,
    maxDenormal,
    minNormal,
    maxFraction,
    [1.0, 1],
    minAbove1,
    [499.0, 499],
    [maxNonIntFloorAsDouble, maxNonIntFloorAsInt],
    maxNonInt,
    [two53, maxExactIntAsInt, maxExactIntAsDouble],
    if (!v.jsNumbers) two53p1,
    [maxInt64, if (!v.jsNumbers) maxFiniteAsInt],
    if (!v.jsNumbers) maxInt64AsDouble,
    maxFiniteAsDouble,
    inf,
    [nan, mnan],
  ];

  check(left, right, expectedResult) {
    if (left is List) {
      for (var x in left) check(x, right, expectedResult);
      return;
    }
    if (right is List) {
      for (var x in right) check(left, x, expectedResult);
      return;
    }
    int actual = left.compareTo(right);
    Expect.equals(
      expectedResult,
      actual,
      "($left).compareTo($right) failed "
      "(should have been $expectedResult, was $actual",
    );
  }

  for (int i = 0; i < matrix.length; i++) {
    for (int j = 0; j < matrix.length; j++) {
      var left = matrix[i];
      var right = matrix[j];
      if (left is List) {
        check(left, left, 0);
      }
      check(left, right, i == j ? 0 : (i < j ? -1 : 1));
    }
  }
}
