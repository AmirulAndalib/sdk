// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Dart test program to check that we can resolve unqualified identifiers

// Import 'dart:typed_data' which internally imports 'dart:_internal'.
import 'dart:typed_data';

import 'package:expect/expect.dart';

main() {
  ClassID.GetID(4);
  // [error column 3, length 7]
  // [analyzer] COMPILE_TIME_ERROR.UNDEFINED_IDENTIFIER
  // [cfe] Undefined name 'ClassID'.
}
