// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:pub_semver/pub_semver.dart';

class SinceSdkVersionComputer {
  static final RegExp _asLanguageVersion = RegExp(r'^\d+\.\d+$');

  /// The [element] is a `dart:xyz` library, so it can have `@Since` annotations.
  /// Evaluates its annotations and returns the version.
  Version? compute(Element element) {
    // Must be in a `dart:` library.
    var libraryUri = element.library?.uri;
    if (libraryUri == null || !libraryUri.isScheme('dart')) {
      return null;
    }

    // We cannot add required parameters.
    if (element is FormalParameterElement && element.isRequired) {
      return null;
    }

    var specified = _specifiedVersion(element);
    var enclosing = element.enclosingElement?.sinceSdkVersion;
    return specified.maxWith(enclosing);
  }

  /// Returns the parsed [Version], or `null` if wrong format.
  static Version? _parseVersion(String versionStr) {
    // 2.15
    if (_asLanguageVersion.hasMatch(versionStr)) {
      return Version.parse('$versionStr.0');
    }

    // 2.19.3 or 3.0.0-dev.4
    try {
      return Version.parse(versionStr);
    } on FormatException {
      return null;
    }
  }

  /// Returns the maximal specified `@Since()` version, `null` if none.
  static Version? _specifiedVersion(Element element) {
    var annotations =
        element.metadata.annotations.cast<ElementAnnotationImpl>();
    Version? result;
    for (var annotation in annotations) {
      if (annotation.isDartInternalSince) {
        var arguments = annotation.annotationAst.arguments?.arguments;
        var versionNode = arguments?.singleOrNull;
        if (versionNode is SimpleStringLiteralImpl) {
          var versionStr = versionNode.value;
          var version = _parseVersion(versionStr);
          if (version != null) {
            result = result.maxWith(version);
          }
        }
      }
    }
    return result;
  }
}

extension on Version? {
  Version? maxWith(Version? other) {
    var self = this;
    if (self == null) {
      return other;
    } else if (other == null) {
      return self;
    } else if (self >= other) {
      return self;
    } else {
      return other;
    }
  }
}
