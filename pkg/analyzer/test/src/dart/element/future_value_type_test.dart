// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/src/dart/element/type.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../generated/type_system_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FutureValueTypeTest);
  });
}

@reflectiveTest
class FutureValueTypeTest extends AbstractTypeSystemTest {
  /// futureValueType(`dynamic`) = `dynamic`.
  test_dynamic() {
    _check(dynamicType, 'dynamic');
  }

  /// futureValueType(Future<`S`>) = `S`, for all `S`.
  test_future() {
    void check(TypeImpl S, String expected) {
      _check(futureNone(S), expected);
    }

    check(intNone, 'int');
    check(intQuestion, 'int?');

    check(dynamicType, 'dynamic');
    check(voidNone, 'void');

    check(neverNone, 'Never');
    check(neverQuestion, 'Never?');

    check(objectNone, 'Object');
    check(objectQuestion, 'Object?');
  }

  /// futureValueType(FutureOr<`S`>) = `S`, for all `S`.
  test_futureOr() {
    void check(TypeImpl S, String expected) {
      _check(futureOrNone(S), expected);
    }

    check(intNone, 'int');
    check(intQuestion, 'int?');

    check(dynamicType, 'dynamic');
    check(voidNone, 'void');

    check(neverNone, 'Never');
    check(neverQuestion, 'Never?');

    check(objectNone, 'Object');
    check(objectQuestion, 'Object?');
  }

  /// Otherwise, for all `S`, futureValueType(`S`) = `Object?`.
  test_other() {
    _check(objectNone, 'Object?');
    _check(intNone, 'Object?');
  }

  /// futureValueType(`S?`) = futureValueType(`S`), for all `S`.
  test_suffix_question() {
    _check(intQuestion, 'Object?');

    _check(futureQuestion(intNone), 'int');
    _check(futureQuestion(intQuestion), 'int?');

    _check(futureOrQuestion(intNone), 'int');
    _check(futureOrQuestion(intQuestion), 'int?');

    _check(futureQuestion(objectNone), 'Object');
    _check(futureQuestion(objectQuestion), 'Object?');

    _check(futureQuestion(dynamicType), 'dynamic');
    _check(futureQuestion(voidNone), 'void');
  }

  /// futureValueType(`void`) = `void`.
  test_void() {
    _check(voidNone, 'void');
  }

  void _check(TypeImpl T, String expected) {
    var result = typeSystem.futureValueType(T);
    expect(result.getDisplayString(), expected);
  }
}
