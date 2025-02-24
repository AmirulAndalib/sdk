// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const String wildcardPrefix = '_#wc';
const String wildcardFormalSuffix = '#formal';
const String wildcardTypeParameterSuffix = '#type';
const String wildcardVariableSuffix = '#var';

/// Returns the named used for a wildcard formal parameter using [index].
String createWildcardFormalParameterName(int index) {
  return '$wildcardPrefix$index$wildcardFormalSuffix';
}

/// Returns the named used for a wildcard type parameter using [index].
String createWildcardTypeParameterName(int index) {
  return '$wildcardPrefix$index$wildcardTypeParameterSuffix';
}

/// Returns the named used for a wildcard variable using [index].
String createWildcardVariableName(int index) {
  return '$wildcardPrefix$index$wildcardVariableSuffix';
}

/// Whether the given [name] is a wildcard formal parameter.
bool isWildcardLoweredFormalParameter(String name) {
  return name.startsWith(wildcardPrefix) && name.endsWith(wildcardFormalSuffix);
}

// Coverage-ignore(suite): Not run.
/// Whether the given [name] is a wildcard type parameter.
bool isWildcardLoweredTypeParameter(String name) {
  return name.startsWith(wildcardPrefix) &&
      name.endsWith(wildcardTypeParameterSuffix);
}

// Coverage-ignore(suite): Not run.
/// Whether the given [name] is a wildcard variable.
bool isWildcardLoweredVariable(String name) {
  return name.startsWith(wildcardPrefix) &&
      name.endsWith(wildcardVariableSuffix);
}
