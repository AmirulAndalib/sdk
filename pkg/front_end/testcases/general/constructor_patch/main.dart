// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:test';

test() {
  new Class._private(); // Error
  new Class._privateInjected(); // Error
  new Class3(); // Error
}

main() {
  new Class.generative();
  const Class.constGenerative();
}
