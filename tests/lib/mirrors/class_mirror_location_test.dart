// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO(51557): Decide if the mixins being applied in this test should be
// "mixin", "mixin class" or the test should be left at 2.19.
// @dart=2.19

// Don't let the formatter change the location of things.
// dart format off

library test.class_location;

import "dart:mirrors";
import "package:expect/expect.dart";

part 'class_mirror_location_other.dart';

class ClassInMainFile {}
  class SpaceIndentedInMainFile {}
	class TabIndentedInMainFile {}

abstract class AbstractClass {}
typedef bool Predicate(num n);

class M {}
class S {}
class MA extends S with M {}
class MA2 = S with M;

const metadata = 'metadata';

@metadata
class WithMetadata {}

enum Enum { RED, GREEN, BLUE }

@metadata
enum AnnotatedEnum { SALT, PEPPER }

// We only check for a suffix of the uri because the test might be run from
// any number of absolute paths.
expectLocation(
    DeclarationMirror mirror, String uriSuffix, int line, int column) {
  final location = mirror.location!;
  final uri = location.sourceUri;
  Expect.isTrue(
      uri.toString().endsWith(uriSuffix), "Expected suffix $uriSuffix in $uri");
  Expect.equals(line, location.line, "line");
  Expect.equals(column, location.column, "column");
}

main() {
  String mainSuffix = 'class_mirror_location_test.dart';
  String otherSuffix = 'class_mirror_location_other.dart';

  // This file.
  expectLocation(reflectClass(ClassInMainFile), mainSuffix, 19, 1);
  expectLocation(reflectClass(SpaceIndentedInMainFile), mainSuffix, 20, 3);
  expectLocation(reflectClass(TabIndentedInMainFile), mainSuffix, 21, 2);
  expectLocation(reflectClass(AbstractClass), mainSuffix, 23, 1);
  expectLocation(reflectType(Predicate), mainSuffix, 24, 1);
  expectLocation(reflectClass(MA), mainSuffix, 28, 1);
  expectLocation(reflectClass(MA2), mainSuffix, 29, 1);
  expectLocation(reflectClass(WithMetadata), mainSuffix, 34, 1);
  expectLocation(reflectClass(Enum), mainSuffix, 36, 1);
  expectLocation(reflectClass(AnnotatedEnum), mainSuffix, 39, 1);

  // Another part.
  expectLocation(reflectClass(ClassInOtherFile), otherSuffix, 14, 1);
  expectLocation(reflectClass(SpaceIndentedInOtherFile), otherSuffix, 16, 3);
  expectLocation(reflectClass(TabIndentedInOtherFile), otherSuffix, 18, 2);

  // Synthetic classes.
  Expect.isNull(reflectClass(MA).superclass!.location);
  Expect.isNull((reflect(main) as ClosureMirror).type.location);
}
