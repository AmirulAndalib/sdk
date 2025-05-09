// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Check that const objects (including literals) are immutable.

// Must be 'const {}' to be valid.
invalid([
  var p = {},
  //      ^^
  // [analyzer] COMPILE_TIME_ERROR.NON_CONSTANT_DEFAULT_VALUE
  // [cfe] Constant expression expected.
  // [cfe] Non-constant map literal is not a constant expression.
]) {}

main() {
  invalid();
}
