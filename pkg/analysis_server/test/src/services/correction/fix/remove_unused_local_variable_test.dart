// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RemoveUnusedLocalVariableTest);
    defineReflectiveTests(
      RemoveUnusedLocalVariableTest_DeclaredVariablePattern,
    );
  });
}

@reflectiveTest
class RemoveUnusedLocalVariableTest extends FixProcessorTest {
  @override
  FixKind get kind => DartFixKind.REMOVE_UNUSED_LOCAL_VARIABLE;

  Future<void> test_assigned() async {
    await resolveTestCode(r'''
void f() {
  var v = 1;
  v = 2;
}
''');
    await assertHasFix(r'''
void f() {
}
''');
  }

  Future<void> test_assigned_awaitedExpression() async {
    await resolveTestCode(r'''
Future<int> foo = Future.value(0);
void f() async {
  final removed = await foo;
}
''');
    await assertHasFix(r'''
Future<int> foo = Future.value(0);
void f() async {
  await foo;
}
''');
  }

  Future<void> test_assigned_awaitedInvocation() async {
    await resolveTestCode(r'''
Future<int> foo() async => 0;
void f() async {
  final removed = await foo();
}
''');
    await assertHasFix(r'''
Future<int> foo() async => 0;
void f() async {
  await foo();
}
''');
  }

  Future<void> test_assigned_doubleParenthesised_awaitedInvocation() async {
    await resolveTestCode(r'''
Future<int> foo() async => 0;
void f() async {
  final removed = ((await foo()));
}
''');
    await assertHasFix(r'''
Future<int> foo() async => 0;
void f() async {
  ((await foo()));
}
''');
  }

  Future<void> test_assigned_functionExpressionInvocation() async {
    await resolveTestCode(r'''
void Function() foo() => () {};
void f() async {
  final removed = foo()();
}
''');
    await assertHasFix(r'''
void Function() foo() => () {};
void f() async {
  foo()();
}
''');
  }

  Future<void> test_assigned_functionInvocation() async {
    await resolveTestCode(r'''
int foo() => 0;
void f() {
  final removed = foo();
}
''');
    await assertHasFix(r'''
int foo() => 0;
void f() {
  foo();
}
''');
  }

  Future<void> test_assigned_inArgumentList() async {
    await resolveTestCode(r'''
void f() {
  var v = 1;
  print(v = 2);
}
''');
    await assertHasFix(r'''
void f() {
  print(2);
}
''');
  }

  Future<void> test_assigned_inArgumentList2() async {
    await resolveTestCode(r'''
void g() {
  var v = 1;
  f(v = 1, 2);
}
void f(a, b) { }
''');
    await assertHasFix(r'''
void g() {
  f(1, 2);
}
void f(a, b) { }
''');
  }

  Future<void> test_assigned_inArgumentList3() async {
    await resolveTestCode(r'''
void g() {
  var v = 1;
  f(v = 1, v = 2);
}
void f(a, b) { }
''');
    await assertHasFix(r'''
void g() {
  f(1, 2);
}
void f(a, b) { }
''');
  }

  Future<void> test_assigned_inAssignment() async {
    await resolveTestCode(r'''
void f() {
  var v = 1;
  v = (v = 2);
  print(0);
}
''');
    await assertHasFix(r'''
void f() {
  print(0);
}
''');
  }

  Future<void> test_assigned_inAssignment2() async {
    await resolveTestCode(r'''
void f() {
  var x = 1, y = 2;
  print(x);
}
''');
    await assertHasFix(r'''
void f() {
  var x = 1;
  print(x);
}
''');
  }

  Future<void> test_assigned_inDeclaration() async {
    await resolveTestCode(r'''
List<String> l = [];
void f(str) {
  final removed = l.remove(str);
}
''');
    await assertHasFix(r'''
List<String> l = [];
void f(str) {
  l.remove(str);
}
''');
  }

  Future<void> test_assigned_parenthesised_awaitedInvocation() async {
    await resolveTestCode(r'''
Future<int> foo() async => 0;
void f() async {
  final removed = (await foo());
}
''');
    await assertHasFix(r'''
Future<int> foo() async => 0;
void f() async {
  (await foo());
}
''');
  }

  Future<void> test_notInFunctionBody() async {
    await resolveTestCode(r'''
var a = [for (var v = 0;;) 0];
''');
    await assertNoFix();
  }

  Future<void> test_variableDeclarationList_multi_first() async {
    await resolveTestCode(r'''
void f() {
  var v = 1, v2 = 3;
  v = 2;
  print(v2);
}
''');
    await assertHasFix(r'''
void f() {
  var v2 = 3;
  print(v2);
}
''');
  }

  Future<void> test_variableDeclarationList_multi_last() async {
    await resolveTestCode(r'''
void f() {
  var v = 1, v2 = 3;
  print(v);
}
''');
    await assertHasFix(r'''
void f() {
  var v = 1;
  print(v);
}
''');
  }

  Future<void> test_withReferences_beforeDeclaration() async {
    // CompileTimeErrorCode.REFERENCED_BEFORE_DECLARATION
    verifyNoTestUnitErrors = false;
    await resolveTestCode(r'''
void f() {
  v = 2;
  var v = 1;
}
''');
    await assertHasFix(
      r'''
void f() {
}
''',
      errorFilter:
          (e) =>
              e.diagnosticCode !=
              CompileTimeErrorCode.REFERENCED_BEFORE_DECLARATION,
    );
  }
}

@reflectiveTest
class RemoveUnusedLocalVariableTest_DeclaredVariablePattern
    extends FixProcessorTest {
  @override
  FixKind get kind => DartFixKind.REMOVE_UNUSED_LOCAL_VARIABLE;

  Future<void> test_logicalAndPattern_typed_left() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case B y && A()) {
  }
}

class A {}
class B {}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case B _ && A()) {
  }
}

class A {}
class B {}
''');
  }

  Future<void> test_logicalAndPattern_typed_left_final() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case final B y && A()) {
  }
}

class A {}
class B {}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case B _ && A()) {
  }
}

class A {}
class B {}
''');
  }

  Future<void> test_logicalAndPattern_typed_right() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case A() && B y) {
  }
}

class A {}
class B {}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case A() && B _) {
  }
}

class A {}
class B {}
''');
  }

  Future<void> test_logicalAndPattern_typed_right_final() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case A() && final B y) {
  }
}

class A {}
class B {}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case A() && B _) {
  }
}

class A {}
class B {}
''');
  }

  Future<void> test_logicalAndPattern_untyped_left() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case var y && int()) {
  }
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case int()) {
  }
}
''');
  }

  Future<void> test_logicalAndPattern_untyped_left_final() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case final y && int()) {
  }
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case int()) {
  }
}
''');
  }

  Future<void> test_logicalAndPattern_untyped_right() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case int() && var y) {
  }
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case int()) {
  }
}
''');
  }

  Future<void> test_logicalAndPattern_untyped_right_final() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case int() && final y) {
  }
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case int()) {
  }
}
''');
  }

  Future<void> test_match_listPattern_typed() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case [0, int foo]) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case [0, int _]) {}
}
''');
  }

  Future<void> test_match_listPattern_typed_final() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case [0, final int foo, 2]) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case [0, int _, 2]) {}
}
''');
  }

  Future<void> test_match_listPattern_untyped_final() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case [0, final foo]) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case [0, _]) {}
}
''');
  }

  Future<void> test_match_listPattern_untyped_var() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case [0, var foo]) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case [0, _]) {}
}
''');
  }

  Future<void> test_match_mapPattern() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case {0: 1, 2: var foo}) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case {0: 1, 2: _}) {}
}
''');
  }

  Future<void> test_objectPattern_declarationStatement_multi_first() async {
    await resolveTestCode(r'''
void f(A a) {
  var A(:foo, bar: int()) = a;
}

class A {
  int get foo => 0;
  int get bar => 0;
}
''');
    await assertHasFix(r'''
void f(A a) {
  var A(bar: int()) = a;
}

class A {
  int get foo => 0;
  int get bar => 0;
}
''');
  }

  Future<void> test_objectPattern_declarationStatement_multi_last() async {
    await resolveTestCode(r'''
void f(A a) {
  var A(foo: int(), :bar) = a;
}

class A {
  int get foo => 0;
  int get bar => 0;
}
''');
    await assertHasFix(r'''
void f(A a) {
  var A(foo: int()) = a;
}

class A {
  int get foo => 0;
  int get bar => 0;
}
''');
  }

  Future<void> test_objectPattern_declarationStatement_only() async {
    await resolveTestCode(r'''
void f(A a) {
  var A(:foo) = a;
}

class A {
  int get foo => 0;
}
''');
    await assertHasFix(r'''
void f(A a) {
}

class A {
  int get foo => 0;
}
''');
  }

  Future<void> test_objectPattern_declarationStatement_typed() async {
    await resolveTestCode(r'''
void f(A a) {
  var A(:num foo) = a;
}

class A {
  int get foo => 0;
}
''');
    await assertHasFix(r'''
void f(A a) {
}

class A {
  int get foo => 0;
}
''');
  }

  Future<void> test_objectPattern_forEach_only() async {
    await resolveTestCode(r'''
void f(List<A> x) {
  for (final A(:foo) in x) {}
}

class A {
  int get foo => 0;
}
''');
    await assertHasFix(r'''
void f(List<A> x) {
  for (final A() in x) {}
}

class A {
  int get foo => 0;
}
''');
  }

  Future<void> test_objectPattern_guardedPattern_typed_explicitName() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case A(foo: int foo)) {
  }
}

class A {
  Object? foo;
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case A(foo: int _)) {
  }
}

class A {
  Object? foo;
}
''');
  }

  Future<void> test_objectPattern_guardedPattern_typed_implicitName() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case A(:int foo)) {
  }
}

class A {
  Object? foo;
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case A(foo: int _)) {
  }
}

class A {
  Object? foo;
}
''');
  }

  Future<void> test_objectPattern_guardedPattern_untyped() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case int(:var sign)) {
  }
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case int()) {
  }
}
''');
  }

  Future<void> test_recordPattern_named_declaration() async {
    await resolveTestCode(r'''
void f(({int foo, int bar}) x) {
  var (:foo, bar: int()) = x;
}
''');
    await assertHasFix(r'''
void f(({int foo, int bar}) x) {
  var (foo: _, bar: int()) = x;
}
''');
  }

  Future<void> test_recordPattern_named_guardedPattern() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case (:int foo)) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case (foo: int _)) {}
}
''');
  }

  Future<void> test_recordPattern_positional_declaration() async {
    await resolveTestCode(r'''
void f(Object? x) {
  var (foo, int()) = (0, 1);
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  var (_, int()) = (0, 1);
}
''');
  }

  Future<void> test_recordPattern_positional_guardedPattern() async {
    await resolveTestCode(r'''
void f(Object? x) {
  if (x case (int foo,)) {}
}
''');
    await assertHasFix(r'''
void f(Object? x) {
  if (x case (int _,)) {}
}
''');
  }
}
