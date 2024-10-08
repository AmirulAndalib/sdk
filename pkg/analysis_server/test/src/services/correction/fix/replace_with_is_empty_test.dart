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
    defineReflectiveTests(ReplaceWithIsEmptyBulkTest);
    defineReflectiveTests(ReplaceWithIsEmptyTest);
  });
}

@reflectiveTest
class ReplaceWithIsEmptyBulkTest extends BulkFixProcessorTest {
  @override
  String get lintCode => LintNames.prefer_is_empty;

  Future<void> test_singleFile() async {
    await resolveTestCode('''
void f(List c) {
  if (0 == c.length) {}
  if (1 > c.length) {}
}
''');
    await assertHasFix('''
void f(List c) {
  if (c.isEmpty) {}
  if (c.isEmpty) {}
}
''');
  }
}

@reflectiveTest
class ReplaceWithIsEmptyTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.REPLACE_WITH_IS_EMPTY;

  @override
  String get lintCode => LintNames.prefer_is_empty;

  Future<void> test_constantOnLeft_equal() async {
    await resolveTestCode('''
f(List c) {
  if (0 == c.length) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (c.isEmpty) {}
}
''');
  }

  Future<void> test_constantOnLeft_greaterThan() async {
    await resolveTestCode('''
f(List c) {
  if (1 > c.length) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (c.isEmpty) {}
}
''');
  }

  Future<void> test_constantOnLeft_greaterThanOrEqual() async {
    await resolveTestCode('''
f(List c) {
  if (0 >= c.length) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (c.isEmpty) {}
}
''');
  }

  Future<void> test_constantOnRight_equal() async {
    await resolveTestCode('''
f(List c) {
  if (c.length == 0) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (c.isEmpty) {}
}
''');
  }

  Future<void> test_constantOnRight_lessThan() async {
    await resolveTestCode('''
f(List c) {
  if (c.length < 1) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (c.isEmpty) {}
}
''');
  }

  Future<void> test_constantOnRight_lessThanOrEqual() async {
    await resolveTestCode('''
f(List c) {
  if (c.length <= 0) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (c.isEmpty) {}
}
''');
  }

  /// https://github.com/dart-lang/sdk/issues/55250
  Future<void> test_nullableList() async {
    await resolveTestCode('''
bool f(List<String>? l) {
  return l?.length == 0;
}
''');
    await assertNoFix();
  }
}
