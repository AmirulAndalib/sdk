// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";
import '../helpers/compiler_helper.dart';

main() {
  runTest() async {
    String code = await compileAll(r'''main() { return "foo" + "bar"; }''');
    Expect.isTrue(!code.contains(r'$add'));
  }

  asyncTest(() async {
    print('--test from kernel------------------------------------------------');
    await runTest();
  });
}
