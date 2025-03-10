// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/integration_tests.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(GetReachableSourcesTest);
  });
}

@reflectiveTest
class GetReachableSourcesTest extends AbstractAnalysisServerIntegrationTest {
  @failingTest
  Future<void> test_reachable() async {
    // This fails with the new analysis driver ('Bad state: Should not be used
    // with the new analysis driver') - #29311.
    var pathname = sourcePath('test.dart');
    var text = r'''
class Foo {}

class Bar {
  Foo foo;
}
''';
    writeFile(pathname, text);
    await standardAnalysisSetup();
    await analysisFinished;

    var result =
    // ignore: deprecated_member_use_from_same_package
    await sendAnalysisGetReachableSources(pathname);
    var sources = result.sources;
    var keys = sources.keys.toList();
    var url = File(pathname).uri.toString();

    expect(keys, contains('dart:core'));
    expect(keys, contains('dart:collection'));
    expect(keys, contains('dart:math'));
    expect(keys, contains(url));
    expect(sources[url], contains('dart:core'));
  }
}
