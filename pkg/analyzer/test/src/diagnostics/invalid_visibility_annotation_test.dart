// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/context_collection_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(InvalidVisibilityAnnotationTest);
  });
}

@reflectiveTest
class InvalidVisibilityAnnotationTest extends PubPackageResolutionTest {
  @override
  void setUp() {
    super.setUp();
    writeTestPackageConfigWithMeta();
  }

  test_fields_multipleMixed() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
class C {
  @visibleForTesting int _a = 0, b = 0;
}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 46, 17),
        error(WarningCode.UNUSED_FIELD, 68, 2),
      ],
    );
  }

  test_fields_multiplePrivate() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
class C {
  @visibleForTesting int _a = 0, _b = 0;
}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 46, 17),
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 46, 17),
        error(WarningCode.UNUSED_FIELD, 68, 2),
        error(WarningCode.UNUSED_FIELD, 76, 2),
      ],
    );
  }

  test_fields_multiplePublic() async {
    await assertNoErrorsInCode(r'''
import 'package:meta/meta.dart';
class C {
  @visibleForTesting int a = 0, b = 0;
}
''');
  }

  test_privateClass() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting class _C {}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 58, 2),
      ],
    );
  }

  test_privateConstructor() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
class C {
  @visibleForTesting C._() {}
}
''',
      [error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 46, 17)],
    );
  }

  test_privateEnum() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting enum _E {a, b}
void f(_E e) => e == _E.a || e == _E.b;
''',
      [error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17)],
    );
  }

  test_privateExtensionType() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting extension type _E(int i) {}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 67, 2),
      ],
    );
  }

  test_privateField() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
class C {
  @visibleForTesting int _a = 1;
}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 46, 17),
        error(WarningCode.UNUSED_FIELD, 68, 2),
      ],
    );
  }

  test_privateMethod() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
class C {
  @visibleForTesting void _m() {}
}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 46, 17),
        error(WarningCode.UNUSED_ELEMENT, 69, 2),
      ],
    );
  }

  test_privateMixin() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting mixin _M {}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 58, 2),
      ],
    );
  }

  test_privateTopLevelFunction() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting void _f() {}
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 57, 2),
      ],
    );
  }

  test_privateTopLevelVariable() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting final _a = 1;
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 58, 2),
      ],
    );
  }

  test_privateTypedef() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting typedef _T = Function();
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 60, 2),
      ],
    );
  }

  test_topLevelVariable_multipleMixed() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting final _a = 1, b = 2;
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 58, 2),
      ],
    );
  }

  test_topLevelVariable_multiplePrivate() async {
    await assertErrorsInCode(
      r'''
import 'package:meta/meta.dart';
@visibleForTesting final _a = 1, _b = 2;
''',
      [
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.INVALID_VISIBILITY_ANNOTATION, 34, 17),
        error(WarningCode.UNUSED_ELEMENT, 58, 2),
        error(WarningCode.UNUSED_ELEMENT, 66, 2),
      ],
    );
  }

  test_topLevelVariable_multiplePublic() async {
    await assertNoErrorsInCode(r'''
import 'package:meta/meta.dart';
@visibleForTesting final a = 1, b = 2;
''');
  }

  test_valid() async {
    await assertNoErrorsInCode(r'''
import 'package:meta/meta.dart';
@visibleForTesting void f() {}
@visibleForTesting enum E {a, b, c}
@visibleForTesting typedef T = Function();
@visibleForTesting class C1 {}
@visibleForTesting extension type ET1(int i) {}
extension type ET2(int i) {
  @visibleForTesting void m() {}
}
@visibleForTesting mixin M {}
class C2 {
  @visibleForTesting C2.named() {}
}
class C3 {
  @visibleForTesting void m() {}
}
''');
  }
}
