// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/analysis_rule/pubspec.dart';
import 'package:analyzer/dart/analysis/analysis_options.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/src/ignore_comments/ignore_info.dart';
import 'package:analyzer/src/lint/linter.dart';
import 'package:analyzer/src/lint/pub.dart';
import 'package:analyzer/src/pubspec/validators/dependency_validator.dart';
import 'package:analyzer/src/pubspec/validators/field_validator.dart';
import 'package:analyzer/src/pubspec/validators/flutter_validator.dart';
import 'package:analyzer/src/pubspec/validators/name_validator.dart';
import 'package:analyzer/src/pubspec/validators/platforms_validator.dart';
import 'package:analyzer/src/pubspec/validators/screenshot_validator.dart';
import 'package:analyzer/src/pubspec/validators/workspace_validator.dart';
import 'package:yaml/yaml.dart';

/// List of [PubspecValidator] implementations.
const _pubspecValidators = <PubspecValidator>[
  dependencyValidator,
  fieldValidator,
  flutterValidator,
  nameValidator,
  screenshotsValidator,
  platformsValidator,
  workspaceValidator,
];

/// Validate pubspec with given [contents].
///
/// The [source] argument must be the source of the file being validated.
/// The [provider] argument must provide access to the file-system.
List<Diagnostic> validatePubspec({
  // TODO(brianwilkerson): This method needs to take a `YamlDocument` rather
  //  than the contents of the document so that it can validate an empty file.
  required YamlNode contents,
  required Source source,
  required ResourceProvider provider,
  AnalysisOptions? analysisOptions,
}) {
  var recorder = RecordingDiagnosticListener();
  DiagnosticReporter reporter = DiagnosticReporter(recorder, source);
  var ctx = PubspecValidationContext._(
    contents: contents,
    source: source,
    reporter: reporter,
    provider: provider,
  );

  for (var validator in _pubspecValidators) {
    validator(ctx);
  }
  if (analysisOptions != null && analysisOptions.lint) {
    var visitors = <AbstractAnalysisRule, PubspecVisitor>{};
    for (var linter in analysisOptions.lintRules) {
      var visitor = linter.pubspecVisitor;
      if (visitor != null) {
        visitors[linter] = visitor;
      }
    }
    if (visitors.isNotEmpty) {
      var pubspecAst = Pubspec.parseYaml(contents, resourceProvider: provider);
      for (var entry in visitors.entries) {
        entry.key.reporter = reporter;
        pubspecAst.accept(entry.value);
      }
    }
  }
  var lineInfo = LineInfo.fromContent(source.contents.data);
  var ignoreInfo = IgnoreInfo.forYaml(source.contents.data, lineInfo);

  return recorder.diagnostics
      .where((error) => !ignoreInfo.ignored(error))
      .toList();
}

/// A function that can validate a `pubspec.yaml`.
typedef PubspecValidator = void Function(PubspecValidationContext ctx);

final class PubspecField {
  /// The name of the sub-field (under `flutter`) whose value is a list of
  /// assets available to Flutter apps at runtime.
  static const String ASSETS_FIELD = 'assets';

  /// The name of the sub-field (under `flutter / assets`) whose value is a path
  /// to an asset available to Flutter apps at runtime.
  static const String ASSET_PATH_FIELD = 'path';

  /// The name of the field whose value is a map of dependencies.
  static const String DEPENDENCIES_FIELD = 'dependencies';

  /// The name of the field whose value is a map of development dependencies.
  static const String DEV_DEPENDENCIES_FIELD = 'dev_dependencies';

  /// The name of the field whose value is a specification of Flutter-specific
  /// configuration data.
  static const String FLUTTER_FIELD = 'flutter';

  /// The name of the field whose value is a git dependency.
  static const String GIT_FIELD = 'git';

  /// The name of the field whose value is the name of the package.
  static const String NAME_FIELD = 'name';

  /// The name of the field whose value is a path to a package dependency.
  static const String PATH_FIELD = 'path';

  /// The name of the field whose value is the where to publish the package.
  static const String PUBLISH_TO_FIELD = 'publish_to';

  /// The name of the field whose value is a list of screenshots to publish.
  static const String SCREENSHOTS_FIELD = 'screenshots';

  /// The name of the field that declares platforms.
  static const String PLATFORMS_FIELD = 'platforms';

  /// The name of the field whose value is the version of the package.
  static const String VERSION_FIELD = 'version';

  /// The name of the field whose value defines a workspace for the repository.
  static const String WORKSPACE_FIELD = 'workspace';
}

/// Context given to function that implement [PubspecValidator].
final class PubspecValidationContext {
  /// Yaml document being validated
  final YamlNode contents;

  /// The source representing the file being validated.
  final Source source;

  /// The reporter to which errors should be reported.
  final DiagnosticReporter reporter;

  /// The resource provider used to access the file system.
  final ResourceProvider provider;

  PubspecValidationContext._({
    required this.contents,
    required this.source,
    required this.reporter,
    required this.provider,
  });

  String? asString(dynamic node) {
    if (node is String) {
      return node;
    }
    if (node is YamlScalar && node.value is String) {
      return node.value as String;
    }
    return null;
  }

  /// Report an error for the given node.
  void reportErrorForNode(
    YamlNode node,
    DiagnosticCode diagnosticCode, [
    List<Object>? arguments,
    List<DiagnosticMessage>? messages,
    Object? data,
  ]) {
    var span = node.span;
    reporter.atOffset(
      offset: span.start.offset,
      length: span.length,
      diagnosticCode: diagnosticCode,
      arguments: arguments,
      contextMessages: messages,
      data: data,
    );
  }
}
