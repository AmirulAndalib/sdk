// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*member: main:[null|powerset={null}]*/
main() {
  zero();
  one();
  half();
  zeroPointZero();
  onePointZero();
  large();
  huge();
  minusOne();
  minusHalf();

  emptyString();
  nonEmptyString();
  stringJuxtaposition();
  stringConstantInterpolation();
  stringNonConstantInterpolation();

  symbolLiteral();
  typeLiteral();
}

////////////////////////////////////////////////////////////////////////////////
/// Return a zero integer literal.
////////////////////////////////////////////////////////////////////////////////

/*member: zero:[exact=JSUInt31|powerset={I}{O}{N}]*/
zero() => 0;

////////////////////////////////////////////////////////////////////////////////
/// Return a positive integer literal.
////////////////////////////////////////////////////////////////////////////////

/*member: one:[exact=JSUInt31|powerset={I}{O}{N}]*/
one() => 1;

////////////////////////////////////////////////////////////////////////////////
/// Return a double literal.
////////////////////////////////////////////////////////////////////////////////

/*member: half:[exact=JSNumNotInt|powerset={I}{O}{N}]*/
half() => 0.5;

////////////////////////////////////////////////////////////////////////////////
/// Return an integer valued zero double literal.
////////////////////////////////////////////////////////////////////////////////

/*member: zeroPointZero:[exact=JSUInt31|powerset={I}{O}{N}]*/
zeroPointZero() => 0.0;

////////////////////////////////////////////////////////////////////////////////
/// Return an integer valued double literal.
////////////////////////////////////////////////////////////////////////////////

/*member: onePointZero:[exact=JSUInt31|powerset={I}{O}{N}]*/
onePointZero() => 1.0;

////////////////////////////////////////////////////////////////////////////////
/// Return a >31bit integer literal.
////////////////////////////////////////////////////////////////////////////////

/*member: large:[subclass=JSUInt32|powerset={I}{O}{N}]*/
large() => 2147483648;

////////////////////////////////////////////////////////////////////////////////
/// Return a >32bit integer literal.
////////////////////////////////////////////////////////////////////////////////

/*member: huge:[subclass=JSPositiveInt|powerset={I}{O}{N}]*/
huge() => 4294967296;

////////////////////////////////////////////////////////////////////////////////
/// Return a negative integer literal.
////////////////////////////////////////////////////////////////////////////////

/*member: minusOne:[subclass=JSInt|powerset={I}{O}{N}]*/
minusOne() => -1;

////////////////////////////////////////////////////////////////////////////////
/// Return a negative double literal.
////////////////////////////////////////////////////////////////////////////////

/*member: minusHalf:[exact=JSNumNotInt|powerset={I}{O}{N}]*/
minusHalf() => -0.5;

////////////////////////////////////////////////////////////////////////////////
/// Return an empty string.
////////////////////////////////////////////////////////////////////////////////

/*member: emptyString:Value([exact=JSString|powerset={I}{O}{I}], value: "", powerset: {I}{O}{I})*/
emptyString() => '';

////////////////////////////////////////////////////////////////////////////////
/// Return a non-empty string.
////////////////////////////////////////////////////////////////////////////////

/*member: nonEmptyString:Value([exact=JSString|powerset={I}{O}{I}], value: "foo", powerset: {I}{O}{I})*/
nonEmptyString() => 'foo';

////////////////////////////////////////////////////////////////////////////////
/// Return a string juxtaposition.
////////////////////////////////////////////////////////////////////////////////

/*member: stringJuxtaposition:Value([exact=JSString|powerset={I}{O}{I}], value: "foobar", powerset: {I}{O}{I})*/
stringJuxtaposition() =>
    'foo'
    'bar';

////////////////////////////////////////////////////////////////////////////////
/// Return a string constant interpolation.
////////////////////////////////////////////////////////////////////////////////

/*member: stringConstantInterpolation:Value([exact=JSString|powerset={I}{O}{I}], value: "foobar", powerset: {I}{O}{I})*/
stringConstantInterpolation() => 'foo${'bar'}';

////////////////////////////////////////////////////////////////////////////////
/// Return a string non-constant interpolation.
////////////////////////////////////////////////////////////////////////////////

/*member: _method1:[exact=JSBool|powerset={I}{O}{N}]*/
_method1(/*[exact=JSBool|powerset={I}{O}{N}]*/ c) => c;

/*member: stringNonConstantInterpolation:[exact=JSString|powerset={I}{O}{I}]*/
stringNonConstantInterpolation() => 'foo${_method1(true)}${_method1(false)}';

////////////////////////////////////////////////////////////////////////////////
/// Return a symbol literal.
////////////////////////////////////////////////////////////////////////////////

/*member: symbolLiteral:[exact=Symbol|powerset={N}{O}{N}]*/
symbolLiteral() => #main;

////////////////////////////////////////////////////////////////////////////////
/// Return a type literal.
////////////////////////////////////////////////////////////////////////////////

/*member: typeLiteral:[exact=_Type|powerset={N}{O}{N}]*/
typeLiteral() => Object;
