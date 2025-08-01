// Copyright (c) 2025, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'dot_shorthands_test.dart' as dot_shorthands;
import 'extensions/test_all.dart' as extensions;

main() {
  defineReflectiveSuite(() {
    dot_shorthands.main();
    extensions.main();
  }, name: 'utilities');
}
