// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

// There is no unary plus operator in Dart.

main() {
  var a = + 1; //      //# 01: syntax error
  var x = +"foo"; //   //# 02: syntax error
  var x = + "foo"; //  //# 03: syntax error
}
