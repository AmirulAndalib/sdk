// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertToPackageImportTest);
  });
}

@reflectiveTest
class ConvertToPackageImportTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.convertToPackageImport;

  Future<void> test_fileName_onImport() async {
    newFile('$testPackageLibPath/foo.dart', '');

    await resolveTestCode('''
^import 'foo.dart';
''');
    // Validate assist is on import keyword too.
    await assertHasAssist('''
import 'package:test/foo.dart';
''');
  }

  Future<void> test_fileName_onUri() async {
    newFile('$testPackageLibPath/foo.dart', '');

    await resolveTestCode('''
import '^foo.dart';
''');
    await assertHasAssist('''
import 'package:test/foo.dart';
''');
  }

  Future<void> test_invalidUri() async {
    verifyNoTestUnitErrors = false;
    await resolveTestCode('''
import ':[^invalidUri]';
''');
    await assertNoAssist();
  }

  Future<void> test_nonPackage_Uri() async {
    newFile('$testPackageLibPath/foo.dart', '');
    testFilePath = convertPath('$testPackageLibPath/src/test.dart');
    await resolveTestCode('''
/*0*/import '/*1*/dart:core';
''');

    await assertNoAssist();
    await assertNoAssist(1);
  }

  Future<void> test_packageUri() async {
    newFile('$testPackageLibPath/foo.dart', '');

    await resolveTestCode('''
/*0*/import 'package:test//*1*/foo.dart';
''');
    await assertNoAssist();
    await assertNoAssist(1);
  }

  Future<void> test_path() async {
    newFile('$testPackageLibPath/foo/bar.dart', '');

    testFilePath = convertPath('$testPackageLibPath/src/test.dart');

    await resolveTestCode('''
import '../foo/^bar.dart';
''');
    await assertHasAssist('''
import 'package:test/foo/bar.dart';
''');
  }
}
