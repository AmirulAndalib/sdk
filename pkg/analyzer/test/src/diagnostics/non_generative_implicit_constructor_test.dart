// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/error/codes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/context_collection_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NonGenerativeImplicitConstructorTest);
  });
}

@reflectiveTest
class NonGenerativeImplicitConstructorTest extends PubPackageResolutionTest {
  @SkippedTest() // TODO(scheglov): implement augmentation
  test_explicit_augmentationDeclares() async {
    newFile('$testPackageLibPath/a.dart', r'''
part of 'test.dart';

augment class B {
  B.named();
}
''');

    await assertNoErrorsInCode(r'''
part 'a.dart';

class A {}
class B extends A {}
''');
  }

  test_implicit() async {
    await assertErrorsInCode(
      r'''
class A {
  factory A() => throw 0;
  A.named();
}
class B extends A {
}
''',
      [error(CompileTimeErrorCode.NON_GENERATIVE_IMPLICIT_CONSTRUCTOR, 57, 1)],
    );
  }
}
