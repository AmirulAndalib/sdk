// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

typedef T = C;

class C extends T {}
//    ^
// [analyzer] COMPILE_TIME_ERROR.RECURSIVE_INTERFACE_INHERITANCE
// [cfe] 'C' is a supertype of itself.

main() => C();
