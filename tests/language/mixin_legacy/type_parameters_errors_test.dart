// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.19

class S<T> {}

class M<U> {}

class A<X> extends S<int> with M<double> {}

class B<U, V> extends S with M<U, V> {}
//                           ^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.WRONG_NUMBER_OF_TYPE_ARGUMENTS
// [cfe] Expected 1 type arguments.

class C<A, B> extends S<A, int> with M {}
//                    ^^^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.WRONG_NUMBER_OF_TYPE_ARGUMENTS
// [cfe] Expected 1 type arguments.

class F<X> = S<X> with M<X>;
class G = S<int> with M<double, double>;
//                    ^^^^^^^^^^^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.WRONG_NUMBER_OF_TYPE_ARGUMENTS
// [cfe] Expected 1 type arguments.

main() {
  var a;
  a = new A();
  a = new A<int>();
  a = new A<String, String>();
  //      ^^^^^^^^^^^^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.WRONG_NUMBER_OF_TYPE_ARGUMENTS
  // [cfe] Expected 1 type arguments.
  a = new F<int>();
  a = new F<int, String>();
  //      ^^^^^^^^^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.WRONG_NUMBER_OF_TYPE_ARGUMENTS
  // [cfe] Expected 1 type arguments.
}
