// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

// It is an error if a potentially non-nullable local variable which has no
// initializer expression and is not marked `late` is used before it is
// definitely assigned.

f(bool b) {
  int v; //# none: compile-time error
  if (b) {
    // not assigned
  } else {
    v = 1;
  }
  v;
}

void main() {}
