// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class C<T> {
  /*member: C.field:Union([exact=JSString], [exact=JSUInt31])*/
  final T field;

  /*member: C.fixedFunctionField:[subclass=Closure]*/
  int Function() fixedFunctionField = /*[exact=JSUInt31]*/ () => 0;

  /*member: C.functionField:[null|subclass=Closure]*/
  T Function()? functionField;

  /*member: C.genericFunctionField:[null|subclass=Closure]*/
  S Function<S>(S)? genericFunctionField;

  /*member: C.:[exact=C]*/
  C(this. /*Union([exact=JSString], [exact=JSUInt31])*/ field) {
    /*update: [subclass=C]*/
    functionField =
        /*Union([exact=JSString], [exact=JSUInt31])*/
        () => /*[subclass=C]*/ field;
    /*Union([exact=JSString], [exact=JSUInt31])*/
    S local<S>(S /*Union([exact=JSString], [exact=JSUInt31])*/ s) => s;
    /*update: [subclass=C]*/
    genericFunctionField = local;
  }

  /*member: C.method:Union([exact=JSString], [exact=JSUInt31])*/
  T method() => /*[subclass=C]*/ field;

  /*member: C.+:Union([exact=JSString], [exact=JSUInt31])*/
  T operator +(T /*Union([exact=JSString], [exact=JSUInt31])*/ t) =>
      /*[subclass=C]*/ field;

  /*member: C.getter:Union([exact=JSString], [exact=JSUInt31])*/
  T get getter => /*[subclass=C]*/ field;

  /*member: C.fixedFunctionGetter:[subclass=Closure]*/
  int Function() get fixedFunctionGetter => /*[exact=JSUInt31]*/ () => 0;

  /*member: C.functionGetter:[null|subclass=Closure]*/
  T Function()? get functionGetter => /*[subclass=C]*/ functionField;

  /*member: C.genericFunctionGetter:[null|subclass=Closure]*/
  S Function<S>(S)? get genericFunctionGetter =>
      /*[subclass=C]*/ genericFunctionField;

  /*member: C.genericMethod:Union([exact=JSString], [exact=JSUInt31])*/
  S genericMethod<S>(S /*Union([exact=JSString], [exact=JSUInt31])*/ s) => s;
}

class D1 extends C<int> {
  /*member: D1.:[exact=D1]*/
  D1(int /*[exact=JSUInt31]*/ field) : super(field);

  /*member: D1.superFieldAccess:[exact=JSUInt31]*/
  superFieldAccess() => super.field;

  /*member: D1.superFieldInvoke:[subclass=JSInt]*/
  superFieldInvoke() => super.functionField!();

  /*member: D1.superFixedFieldInvoke:[subclass=JSInt]*/
  superFixedFieldInvoke() => super.fixedFunctionField();

  /*member: D1.superMethodInvoke:[exact=JSUInt31]*/
  superMethodInvoke() => super.method();

  /*member: D1.superOperatorInvoke:[exact=JSUInt31]*/
  superOperatorInvoke() => super + 0;

  /*member: D1.superGetterAccess:[exact=JSUInt31]*/
  superGetterAccess() => super.getter;

  /*member: D1.superGetterInvoke:[subclass=JSInt]*/
  superGetterInvoke() => super.functionGetter!();

  /*member: D1.superFixedGetterInvoke:[subclass=JSInt]*/
  superFixedGetterInvoke() => super.fixedFunctionGetter();

  /*member: D1.superGenericFieldInvoke1:[exact=JSString]*/
  superGenericFieldInvoke1() => super.genericFunctionField!('');

  /*member: D1.superGenericFieldInvoke2:[subclass=JSInt]*/
  superGenericFieldInvoke2() => super.genericFunctionField!(0);

  /*member: D1.superGenericMethodInvoke1:[exact=JSString]*/
  superGenericMethodInvoke1() => super.genericMethod('');

  /*member: D1.superGenericMethodInvoke2:[exact=JSUInt31]*/
  superGenericMethodInvoke2() => super.genericMethod(0);

  /*member: D1.superGenericGetterInvoke1:[exact=JSString]*/
  superGenericGetterInvoke1() => super.genericFunctionGetter!('');

  /*member: D1.superGenericGetterInvoke2:[subclass=JSInt]*/
  superGenericGetterInvoke2() => super.genericFunctionGetter!(0);
}

class D2 extends C<String> {
  /*member: D2.:[exact=D2]*/
  D2(String /*Value([exact=JSString], value: "")*/ field) : super(field);

  /*member: D2.superFieldAccess:[exact=JSString]*/
  superFieldAccess() => super.field;

  /*member: D2.superFieldInvoke:[exact=JSString]*/
  superFieldInvoke() => super.functionField!();

  /*member: D2.superFixedFieldInvoke:[subclass=JSInt]*/
  superFixedFieldInvoke() => super.fixedFunctionField();

  /*member: D2.superMethodInvoke:[exact=JSString]*/
  superMethodInvoke() => super.method();

  /*member: D2.superOperatorInvoke:[exact=JSString]*/
  superOperatorInvoke() => super + '';

  /*member: D2.superGetterAccess:[exact=JSString]*/
  superGetterAccess() => super.getter;

  /*member: D2.superGetterInvoke:[exact=JSString]*/
  superGetterInvoke() => super.functionGetter!();

  /*member: D2.superFixedGetterInvoke:[subclass=JSInt]*/
  superFixedGetterInvoke() => super.fixedFunctionGetter();

  /*member: D2.superGenericFieldInvoke1:[exact=JSString]*/
  superGenericFieldInvoke1() => super.genericFunctionField!('');

  /*member: D2.superGenericFieldInvoke2:[subclass=JSInt]*/
  superGenericFieldInvoke2() => super.genericFunctionField!(0);

  /*member: D2.superGenericMethodInvoke1:[exact=JSString]*/
  superGenericMethodInvoke1() => super.genericMethod('');

  /*member: D2.superGenericMethodInvoke2:[exact=JSUInt31]*/
  superGenericMethodInvoke2() => super.genericMethod(0);

  /*member: D2.superGenericGetterInvoke1:[exact=JSString]*/
  superGenericGetterInvoke1() => super.genericFunctionGetter!('');

  /*member: D2.superGenericGetterInvoke2:[subclass=JSInt]*/
  superGenericGetterInvoke2() => super.genericFunctionGetter!(0);
}

/*member: main:[null]*/
main() {
  closureInvoke();
  localFunctionInvoke();
  genericLocalFunctionInvoke();
  fieldAccess1();
  fieldAccess2();
  fixedFieldInvoke();
  fieldInvoke1();
  fieldInvoke2();
  methodInvoke1();
  methodInvoke2();
  operatorInvoke1();
  operatorInvoke2();
  fixedGetterInvoke();
  getterAccess1();
  getterAccess2();
  getterInvoke1();
  getterInvoke2();
  genericFieldInvoke1();
  genericFieldInvoke2();
  genericMethodInvoke1();
  genericMethodInvoke2();
  genericGetterInvoke1();
  genericGetterInvoke2();
  D1(0)
    .. /*invoke: [exact=D1]*/ superFieldAccess()
    .. /*invoke: [exact=D1]*/ superFieldInvoke()
    .. /*invoke: [exact=D1]*/ superFixedFieldInvoke()
    .. /*invoke: [exact=D1]*/ superMethodInvoke()
    .. /*invoke: [exact=D1]*/ superOperatorInvoke()
    .. /*invoke: [exact=D1]*/ superGetterAccess()
    .. /*invoke: [exact=D1]*/ superGetterInvoke()
    .. /*invoke: [exact=D1]*/ superFixedGetterInvoke()
    .. /*invoke: [exact=D1]*/ superGenericFieldInvoke1()
    .. /*invoke: [exact=D1]*/ superGenericFieldInvoke2()
    .. /*invoke: [exact=D1]*/ superGenericMethodInvoke1()
    .. /*invoke: [exact=D1]*/ superGenericMethodInvoke2()
    .. /*invoke: [exact=D1]*/ superGenericGetterInvoke1()
    .. /*invoke: [exact=D1]*/ superGenericGetterInvoke2();
  D2('')
    .. /*invoke: [exact=D2]*/ superFieldAccess()
    .. /*invoke: [exact=D2]*/ superFieldInvoke()
    .. /*invoke: [exact=D2]*/ superFixedFieldInvoke()
    .. /*invoke: [exact=D2]*/ superMethodInvoke()
    .. /*invoke: [exact=D2]*/ superOperatorInvoke()
    .. /*invoke: [exact=D2]*/ superGetterAccess()
    .. /*invoke: [exact=D2]*/ superGetterInvoke()
    .. /*invoke: [exact=D2]*/ superFixedGetterInvoke()
    .. /*invoke: [exact=D2]*/ superGenericFieldInvoke1()
    .. /*invoke: [exact=D2]*/ superGenericFieldInvoke2()
    .. /*invoke: [exact=D2]*/ superGenericMethodInvoke1()
    .. /*invoke: [exact=D2]*/ superGenericMethodInvoke2()
    .. /*invoke: [exact=D2]*/ superGenericGetterInvoke1()
    .. /*invoke: [exact=D2]*/ superGenericGetterInvoke2();
}

/*member: closureInvoke:[subclass=JSInt]*/
closureInvoke() {
  int Function() f = /*[exact=JSUInt31]*/ () => 0;
  return f();
}

/*member: localFunctionInvoke:[exact=JSUInt31]*/
localFunctionInvoke() {
  /*[exact=JSUInt31]*/
  int local() => 0;
  return local();
}

/*member: genericLocalFunctionInvoke:[null]*/
genericLocalFunctionInvoke() {
  /*Union([exact=JSString], [exact=JSUInt31])*/
  S local<S>(S /*Union([exact=JSString], [exact=JSUInt31])*/ s) => s;

  local(0). /*invoke: [exact=JSUInt31]*/ toString();
  local(''). /*invoke: [exact=JSString]*/ toString();
}

/*member: fieldAccess1:[exact=JSUInt31]*/
fieldAccess1() {
  C<int> c = C<int>(0);
  return c. /*[exact=C]*/ field;
}

/*member: fieldAccess2:[exact=JSString]*/
fieldAccess2() {
  C<String> c = C<String>('');
  return c. /*[exact=C]*/ field;
}

/*member: fixedFieldInvoke:[subclass=JSInt]*/
fixedFieldInvoke() {
  C<int> c = C<int>(0);
  return c.fixedFunctionField /*invoke: [exact=C]*/ ();
}

/*member: fieldInvoke1:[subclass=JSInt]*/
fieldInvoke1() {
  C<int> c = C<int>(0);
  return c. /*[exact=C]*/ functionField!();
}

/*member: fieldInvoke2:[exact=JSString]*/
fieldInvoke2() {
  C<String> c = C<String>('');
  return c. /*[exact=C]*/ functionField!();
}

/*member: methodInvoke1:[exact=JSUInt31]*/
methodInvoke1() {
  C<int> c = C<int>(0);
  return c. /*invoke: [exact=C]*/ method();
}

/*member: methodInvoke2:[exact=JSString]*/
methodInvoke2() {
  C<String> c = C<String>('');
  return c. /*invoke: [exact=C]*/ method();
}

/*member: operatorInvoke1:[exact=JSUInt31]*/
operatorInvoke1() {
  C<int> c = C<int>(0);
  return c /*invoke: [exact=C]*/ + 0;
}

/*member: operatorInvoke2:[exact=JSString]*/
operatorInvoke2() {
  C<String> c = C<String>('');
  return c /*invoke: [exact=C]*/ + '';
}

/*member: fixedGetterInvoke:[subclass=JSInt]*/
fixedGetterInvoke() {
  C<int> c = C<int>(0);
  return c.fixedFunctionGetter /*invoke: [exact=C]*/ ();
}

/*member: getterAccess1:[exact=JSUInt31]*/
getterAccess1() {
  C<int> c = C<int>(0);
  return c. /*[exact=C]*/ getter;
}

/*member: getterAccess2:[exact=JSString]*/
getterAccess2() {
  C<String> c = C<String>('');
  return c. /*[exact=C]*/ getter;
}

/*member: getterInvoke1:[subclass=JSInt]*/
getterInvoke1() {
  C<int> c = C<int>(0);
  return c. /*[exact=C]*/ functionGetter!();
}

/*member: getterInvoke2:[exact=JSString]*/
getterInvoke2() {
  C<String> c = C<String>('');
  return c. /*[exact=C]*/ functionGetter!();
}

/*member: genericFieldInvoke1:[exact=JSString]*/
genericFieldInvoke1() {
  C<int> c = C<int>(0);
  return c. /*[exact=C]*/ genericFunctionField!('');
}

/*member: genericFieldInvoke2:[subclass=JSInt]*/
genericFieldInvoke2() {
  C<String> c = C<String>('');
  return c. /*[exact=C]*/ genericFunctionField!(0);
}

/*member: genericMethodInvoke1:[exact=JSString]*/
genericMethodInvoke1() {
  C<int> c = C<int>(0);
  return c. /*invoke: [exact=C]*/ genericMethod('');
}

/*member: genericMethodInvoke2:[exact=JSUInt31]*/
genericMethodInvoke2() {
  C<String> c = C<String>('');
  return c. /*invoke: [exact=C]*/ genericMethod(0);
}

/*member: genericGetterInvoke1:[exact=JSString]*/
genericGetterInvoke1() {
  C<int> c = C<int>(0);
  return c. /*[exact=C]*/ genericFunctionGetter!('');
}

/*member: genericGetterInvoke2:[subclass=JSInt]*/
genericGetterInvoke2() {
  C<String> c = C<String>('');
  return c. /*[exact=C]*/ genericFunctionGetter!(0);
}
