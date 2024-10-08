// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertDocumentationIntoLineBulkTest);
    defineReflectiveTests(ConvertDocumentationIntoLineTest);
  });
}

@reflectiveTest
class ConvertDocumentationIntoLineBulkTest extends BulkFixProcessorTest {
  @override
  String get lintCode => LintNames.slash_for_doc_comments;

  Future<void> test_singleFile() async {
    await parseTestCode('''
/**
 * C
 */
class C {
  /**
   * f
   */
  int f;

  /**
   * m
   */
  m() {}
}

/**
 * f
 */
void f() {}
''');
    await assertHasFix('''
/// C
class C {
  /// f
  int f;

  /// m
  m() {}
}

/// f
void f() {}
''', isParse: true);
  }
}

@reflectiveTest
class ConvertDocumentationIntoLineTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.CONVERT_TO_LINE_COMMENT;

  @override
  String get lintCode => LintNames.slash_for_doc_comments;

  /// More coverage in the `convert_to_documentation_line_test.dart` assist test.
  Future<void> test_onText() async {
    await resolveTestCode('''
class A {
  /**
   * AAAAAAA [int] AAAAAAA
   * BBBBBBBB BBBB BBBB
   * CCC [A] CCCCCCCCCCC
   */
  mmm() {}
}
''');
    await assertHasFix('''
class A {
  /// AAAAAAA [int] AAAAAAA
  /// BBBBBBBB BBBB BBBB
  /// CCC [A] CCCCCCCCCCC
  mmm() {}
}
''');
  }
}
