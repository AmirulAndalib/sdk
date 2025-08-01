// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_js_interop_checks/js_interop_checks.dart';
import 'package:collection/collection.dart';
import 'package:front_end/src/api_prototype/codes.dart'
    show Message, LocatedMessage;
import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/target/targets.dart' show DiagnosticReporter;

/// Used to record the type of error in Flutter telemetry.
///
/// DO NOT alter the numeric values or change the meaning of these entries.
///
/// It is MUCH better to add new values and deprecate old values.
/// Consider commenting out the old value line as a tombstone.
///
/// Please notify folks in charge of Flutter Web analytics before making any
/// changes.
enum _DryRunErrorCode {
  noDartHtml(0),
  noDartJs(1),
  interopChecksError(2),
  // ignore: unused_field
  isTestValueError(3),
  // ignore: unused_field
  isTestTypeError(4),
  // ignore: unused_field
  isTestGenericTypeError(5);

  const _DryRunErrorCode(this.code);

  final int code;
}

class _DryRunError {
  final _DryRunErrorCode code;
  final String problemMessage;
  final Uri? errorSourceUri;
  final Location? errorLocation;

  _DryRunError(this.code, this.problemMessage,
      {this.errorSourceUri, this.errorLocation});

  static String _locationToString(Uri? sourceUri, Location? location) {
    if (sourceUri == null && location == null) return 'unknown location';
    final uri = sourceUri ?? location?.file;
    final lineCol =
        location != null ? ' ${location.line}:${location.column}' : '';
    return '$uri$lineCol';
  }

  @override
  String toString() => '${_locationToString(errorSourceUri, errorLocation)} '
      '- $problemMessage (${code.code})';
}

/// Runs several passes over the provided kernel to find any code in the
/// sources that could block a migration to WASM from JS.
///
/// At the end of execution, it emits a summary to stdout that looks like:
/// ```
/// Found incompatibilities with WebAssembly.
///
/// package:dryrun/test.dart 5:15 - Cannot test a JS value against String (3)
/// package:dryrun/test.dart 6:7 - JS interop class 'B' cannot extend Dart class 'A'. (2)
/// ````
class DryRunSummarizer {
  final Component component;
  late final CoreTypes coreTypes;
  late final ClassHierarchy classHierarchy;

  DryRunSummarizer(this.component) {
    coreTypes = CoreTypes(component);
    classHierarchy = ClassHierarchy(component, coreTypes);
  }

  static const Map<String, _DryRunErrorCode> _disallowedDartUris = {
    'dart:html': _DryRunErrorCode.noDartHtml,
    'dart:js': _DryRunErrorCode.noDartJs,
    // 'dart:ffi' is handled by interop checks.
  };

  List<_DryRunError> _analyzeImports() {
    final errors = <_DryRunError>[];

    for (final library in component.libraries) {
      if (library.importUri.scheme == 'dart') continue;

      for (final dep in library.dependencies) {
        final depLib = dep.importedLibraryReference.asLibrary;
        final code = _disallowedDartUris[depLib.importUri.toString()];
        if (code != null) {
          errors.add(_DryRunError(code, '${depLib.importUri} unsupported',
              errorSourceUri: library.importUri, errorLocation: dep.location));
        }
      }
    }

    return errors;
  }

  List<_DryRunError> _interopChecks() {
    final collector = _CollectingDiagnosticReporter(component);
    final reporter = JsInteropDiagnosticReporter(collector);
    // These checks will already have been done by the CFE but the message
    // format the CFE provides for those errors makes it hard to identify them
    // as interop-specific errors. Instead we rerun and collect any errors here.
    component.accept(JsInteropChecks(coreTypes, classHierarchy, reporter,
        JsInteropChecks.getNativeClasses(component),
        isDart2Wasm: true));
    return collector.errors;
  }

  bool summarize() {
    final errors = [
      ..._analyzeImports(),
      ..._interopChecks(),
      // TODO: Add additional checks here.
    ];

    if (errors.isNotEmpty) {
      print('Found incompatibilities with WebAssembly.\n');
      print(errors.join('\n'));
      return true;
    }
    return false;
  }
}

class _CollectingDiagnosticReporter
    extends DiagnosticReporter<Message, LocatedMessage> {
  final Component component;
  final List<_DryRunError> errors = <_DryRunError>[];

  _CollectingDiagnosticReporter(this.component);

  @override
  void report(Message message, int charOffset, int length, Uri? fileUri,
      {List<LocatedMessage>? context}) {
    final libraryUri = fileUri != null
        ? component.libraries
            .firstWhereOrNull((e) => e.fileUri == fileUri)
            ?.importUri
        : null;
    final location =
        fileUri != null ? component.getLocation(fileUri, charOffset) : null;
    errors.add(_DryRunError(
        _DryRunErrorCode.interopChecksError, message.problemMessage,
        errorSourceUri: libraryUri ?? fileUri, errorLocation: location));
  }
}
