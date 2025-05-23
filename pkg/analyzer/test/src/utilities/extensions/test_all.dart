// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'async_test.dart' as async;
import 'collection_test.dart' as collection;
import 'object_test.dart' as object;
import 'stream_test.dart' as stream;
import 'string_test.dart' as string;

main() {
  defineReflectiveSuite(() {
    async.main();
    collection.main();
    object.main();
    stream.main();
    string.main();
  }, name: 'extensions');
}
