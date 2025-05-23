// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/context_collection_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnnecessaryNullComparisonFalseTest);
    defineReflectiveTests(UnnecessaryNullComparisonTrueTest);
  });
}

@reflectiveTest
class UnnecessaryNullComparisonFalseTest extends PubPackageResolutionTest {
  test_equal_intLiteral() async {
    await assertNoErrorsInCode('''
f(int a, int? b) {
  a == 0;
  0 == a;
  b == 0;
  0 == b;
}
''');
  }

  test_equal_notNullable() async {
    await assertErrorsInCode(
      '''
f(int a) {
  a == null;
  null == a;
}
''',
      [
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_NEVER_NULL_FALSE, 15, 7),
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_NEVER_NULL_FALSE, 26, 7),
      ],
    );
  }

  test_equal_nullable() async {
    await assertNoErrorsInCode('''
f(int? a) {
  a == null;
  null == a;
}
''');
  }

  test_implicitlyAssigned_false() async {
    await assertErrorsInCode(
      '''
f() {
  int? i;
  i != null;
  null != i;
}
''',
      [
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_ALWAYS_NULL_FALSE, 18, 4),
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_ALWAYS_NULL_FALSE, 36, 4),
      ],
    );
  }

  test_implicitlyAssigned_true() async {
    await assertErrorsInCode(
      '''
f() {
  int? i;
  i == null;
  null == i;
}
''',
      [
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_ALWAYS_NULL_TRUE, 18, 4),
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_ALWAYS_NULL_TRUE, 36, 4),
      ],
    );
  }
}

@reflectiveTest
class UnnecessaryNullComparisonTrueTest extends PubPackageResolutionTest {
  test_notEqual_intLiteral() async {
    await assertNoErrorsInCode('''
f(int a, int? b) {
  a != 0;
  0 != a;
  b != 0;
  0 != b;
}
''');
  }

  test_notEqual_notNullable() async {
    await assertErrorsInCode(
      '''
f(int a) {
  a != null;
  null != a;
}
''',
      [
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_NEVER_NULL_TRUE, 15, 7),
        error(WarningCode.UNNECESSARY_NULL_COMPARISON_NEVER_NULL_TRUE, 26, 7),
      ],
    );
  }

  test_notEqual_nullable() async {
    await assertNoErrorsInCode('''
f(int? a) {
  a != null;
  null != a;
}
''');
  }
}
