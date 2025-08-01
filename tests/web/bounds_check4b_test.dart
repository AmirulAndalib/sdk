// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2jsOptions=-O1

import 'package:expect/expect.dart';

main() {
  dynamic c = new Class<int>();
  Expect.equals(c.method(), int);
}

class Class<T> {
  method<S extends T>() => S;
}
