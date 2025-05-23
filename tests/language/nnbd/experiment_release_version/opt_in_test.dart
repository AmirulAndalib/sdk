// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This version should continue to opt into null safety in perpetuity (or at
// least until Dart 3), when the experiment is enabled.
// @dart = 2.12

void main() {
  // This should be an error since we are opted in.
  int x = null;
  //      ^^^^
  // [analyzer] COMPILE_TIME_ERROR.INVALID_ASSIGNMENT
  // [cfe] A value of type 'Null' can't be assigned to a variable of type 'int'.
}
