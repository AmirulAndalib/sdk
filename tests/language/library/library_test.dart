// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

import "nonexistent_library.dart"; //# 01: compile-time error

main() {
  print("Er, hello world? This should not be printed!");
}
