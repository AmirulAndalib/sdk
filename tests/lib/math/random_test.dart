// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test that rnd.nextInt with a seed generates the same sequence each time.

// Library tag to allow Dartium to run the test.
library random_test;

import "package:expect/expect.dart";
import 'dart:math';

main() {
  checkSequence();
  checkSeed();
}

void checkSequence() {
  // Check the sequence of numbers generated by the random generator for a seed
  // doesn't change unintendedly, and it agrees between implementations.
  var rnd = new Random(20130307);
  // Make sure we do not break the random number generation.
  // If the random algorithm changes, make sure both the VM and dart2js
  // generate the same new sequence.
  var i = 1;
  Expect.equals(0, rnd.nextInt(i *= 2));
  Expect.equals(3, rnd.nextInt(i *= 2));
  Expect.equals(7, rnd.nextInt(i *= 2));
  Expect.equals(5, rnd.nextInt(i *= 2));
  Expect.equals(29, rnd.nextInt(i *= 2));
  Expect.equals(17, rnd.nextInt(i *= 2));
  Expect.equals(104, rnd.nextInt(i *= 2));
  Expect.equals(199, rnd.nextInt(i *= 2));
  Expect.equals(408, rnd.nextInt(i *= 2));
  Expect.equals(362, rnd.nextInt(i *= 2));
  Expect.equals(995, rnd.nextInt(i *= 2));
  Expect.equals(2561, rnd.nextInt(i *= 2));
  Expect.equals(2548, rnd.nextInt(i *= 2));
  Expect.equals(9553, rnd.nextInt(i *= 2));
  Expect.equals(2628, rnd.nextInt(i *= 2));
  Expect.equals(42376, rnd.nextInt(i *= 2));
  Expect.equals(101848, rnd.nextInt(i *= 2));
  Expect.equals(85153, rnd.nextInt(i *= 2));
  Expect.equals(495595, rnd.nextInt(i *= 2));
  Expect.equals(647122, rnd.nextInt(i *= 2));
  Expect.equals(793546, rnd.nextInt(i *= 2));
  Expect.equals(1073343, rnd.nextInt(i *= 2));
  Expect.equals(4479969, rnd.nextInt(i *= 2));
  Expect.equals(9680425, rnd.nextInt(i *= 2));
  Expect.equals(28460171, rnd.nextInt(i *= 2));
  Expect.equals(49481738, rnd.nextInt(i *= 2));
  Expect.equals(9878974, rnd.nextInt(i *= 2));
  Expect.equals(132552472, rnd.nextInt(i *= 2));
  Expect.equals(210267283, rnd.nextInt(i *= 2));
  Expect.equals(125422442, rnd.nextInt(i *= 2));
  Expect.equals(226275094, rnd.nextInt(i *= 2));
  Expect.equals(1639629168, rnd.nextInt(i *= 2));
  Expect.equals(0x100000000, i);
  // If max is too large expect an ArgumentError.
  Expect.throwsArgumentError(() => rnd.nextInt(i + 1));

  rnd = new Random(6790);
  Expect.approxEquals(0.1202733131, rnd.nextDouble());
  Expect.approxEquals(0.5554054805, rnd.nextDouble());
  Expect.approxEquals(0.0385160727, rnd.nextDouble());
  Expect.approxEquals(0.2836345217, rnd.nextDouble());
}

void checkSeed() {
  // Check that various seeds generate the expected first values.
  // 53 significant bits, so the number is representable in JS.
  var rawSeed = 0x19a32c640e1d71;
  var expectations = [
    26007,
    43006,
    46458,
    18610,
    16413,
    50455,
    2164,
    47399,
    8859,
    9732,
    20367,
    33935,
    54549,
    54913,
    4819,
    24198,
    49353,
    22277,
    51852,
    35959,
    45347,
    12100,
    10136,
    22372,
    15293,
    20066,
    1351,
    49030,
    64845,
    12793,
    50916,
    55784,
    43170,
    27653,
    34696,
    1492,
    50255,
    9597,
    45929,
    2874,
    27629,
    53084,
    36064,
    42140,
    32016,
    41751,
    13967,
    20516,
    578,
    16773,
    53064,
    14814,
    22737,
    48846,
    45147,
    10205,
    56584,
    63711,
    44128,
    21099,
    47966,
    35471,
    39576,
    1141,
    45716,
    54940,
    57406,
    15437,
    31721,
    35044,
    28136,
    39797,
    50801,
    22184,
    58686,
  ];
  var negative_seed_expectations = [
    12170,
    42844,
    39228,
    64032,
    29046,
    57572,
    8453,
    52224,
    27060,
    28454,
    20510,
    28804,
    59221,
    53422,
    11047,
    50864,
    33997,
    19611,
    1250,
    65088,
    19690,
    11396,
    20,
    48867,
    44862,
    47129,
    58724,
    13325,
    50005,
    33320,
    16523,
    4740,
    63721,
    63272,
    30545,
    51403,
    35845,
    3943,
    31850,
    23148,
    26307,
    1724,
    29281,
    39988,
    43653,
    48012,
    43810,
    16755,
    13105,
    25325,
    32648,
    19958,
    38838,
    8322,
    3421,
    28624,
    17269,
    45385,
    50680,
    1696,
    26088,
    2787,
    48566,
    34357,
    27731,
    51764,
    8455,
    16498,
    59721,
    59568,
    46333,
    7935,
    51459,
    36766,
    50711,
  ];
  for (var i = 0, m = 1; i < 75; i++) {
    if (rawSeed * m < 0) {
      // Overflow.
      break;
    }
    Expect.equals(expectations[i], new Random(rawSeed * m).nextInt(65536));
    Expect.equals(
      negative_seed_expectations[i],
      new Random(rawSeed * -m).nextInt(65536),
    );
    m *= 2;
  }
  // And test zero seed too.
  Expect.equals(21391, new Random(0).nextInt(65536));
}
