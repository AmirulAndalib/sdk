// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// NOTE: THIS FILE IS GENERATED. DO NOT EDIT.
//
// Instead modify 'tools/experimental_features.yaml' and run
// 'dart pkg/front_end/tool/cfe.dart generate-experimental-flags' to update.

part of 'experimental_flags.dart';

/// An experiment flag including its fixed properties.
class ExperimentalFlag {
  /// The name of this flag as used in the --enable-experiment option.
  final String name;

  /// `true` if this experimental feature is enabled by default.
  ///
  /// When `true`, the feature can still be disabled in individual libraries
  /// with a language version below the [experimentEnabledVersion], and if not
  /// [isExpired], the feature can also be disabled by using a 'no-' prefix
  /// in the --enable-experiment option.
  final bool isEnabledByDefault;

  /// `true` if this feature can no longer be changed using the
  /// --enable-experiment option.
  ///
  /// Libraries can still opt out of the feature by using a language version
  /// below the [experimentEnabledVersion].
  final bool isExpired;
  final Version enabledVersion;

  /// The minimum version that supports this feature.
  ///
  /// If the feature is not enabled by default, this is the current language
  /// version.
  final Version experimentEnabledVersion;

  /// The minimum version that supports this feature in allowed libraries.
  ///
  /// Allowed libraries are specified in
  ///
  ///    sdk/lib/_internal/allowed_experiments.json
  final Version experimentReleasedVersion;

  const ExperimentalFlag(
      {required this.name,
      required this.isEnabledByDefault,
      required this.isExpired,
      required this.enabledVersion,
      required this.experimentEnabledVersion,
      required this.experimentReleasedVersion});
  static const ExperimentalFlag alternativeInvalidationStrategy =
      const ExperimentalFlag(
          name: 'alternative-invalidation-strategy',
          isEnabledByDefault: true,
          isExpired: true,
          enabledVersion: const Version(2, 18),
          experimentEnabledVersion: const Version(2, 18),
          experimentReleasedVersion: const Version(2, 18));

  static const ExperimentalFlag augmentations = const ExperimentalFlag(
      name: 'augmentations',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: const Version(3, 6));

  static const ExperimentalFlag classModifiers = const ExperimentalFlag(
      name: 'class-modifiers',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 0),
      experimentEnabledVersion: const Version(3, 0),
      experimentReleasedVersion: const Version(3, 0));

  static const ExperimentalFlag constFunctions = const ExperimentalFlag(
      name: 'const-functions',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: defaultLanguageVersion);

  static const ExperimentalFlag constantUpdate2018 = const ExperimentalFlag(
      name: 'constant-update-2018',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 0),
      experimentEnabledVersion: const Version(2, 0),
      experimentReleasedVersion: const Version(2, 0));

  static const ExperimentalFlag constructorTearoffs = const ExperimentalFlag(
      name: 'constructor-tearoffs',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 15),
      experimentEnabledVersion: const Version(2, 15),
      experimentReleasedVersion: const Version(2, 15));

  static const ExperimentalFlag controlFlowCollections = const ExperimentalFlag(
      name: 'control-flow-collections',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 0),
      experimentEnabledVersion: const Version(2, 0),
      experimentReleasedVersion: const Version(2, 0));

  static const ExperimentalFlag digitSeparators = const ExperimentalFlag(
      name: 'digit-separators',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 6),
      experimentEnabledVersion: const Version(3, 6),
      experimentReleasedVersion: const Version(3, 6));

  static const ExperimentalFlag dotShorthands = const ExperimentalFlag(
      name: 'dot-shorthands',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: const Version(3, 9));

  static const ExperimentalFlag enhancedEnums = const ExperimentalFlag(
      name: 'enhanced-enums',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 17),
      experimentEnabledVersion: const Version(2, 17),
      experimentReleasedVersion: const Version(2, 17));

  static const ExperimentalFlag enhancedParts = const ExperimentalFlag(
      name: 'enhanced-parts',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: const Version(3, 6));

  static const ExperimentalFlag extensionMethods = const ExperimentalFlag(
      name: 'extension-methods',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 6),
      experimentEnabledVersion: const Version(2, 6),
      experimentReleasedVersion: const Version(2, 6));

  static const ExperimentalFlag genericMetadata = const ExperimentalFlag(
      name: 'generic-metadata',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 14),
      experimentEnabledVersion: const Version(2, 14),
      experimentReleasedVersion: const Version(2, 14));

  static const ExperimentalFlag getterSetterError = const ExperimentalFlag(
      name: 'getter-setter-error',
      isEnabledByDefault: true,
      isExpired: false,
      enabledVersion: const Version(3, 9),
      experimentEnabledVersion: const Version(3, 9),
      experimentReleasedVersion: const Version(3, 9));

  static const ExperimentalFlag inferenceUpdate1 = const ExperimentalFlag(
      name: 'inference-update-1',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 18),
      experimentEnabledVersion: const Version(2, 18),
      experimentReleasedVersion: const Version(2, 18));

  static const ExperimentalFlag inferenceUpdate2 = const ExperimentalFlag(
      name: 'inference-update-2',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 2),
      experimentEnabledVersion: const Version(3, 2),
      experimentReleasedVersion: const Version(3, 2));

  static const ExperimentalFlag inferenceUpdate3 = const ExperimentalFlag(
      name: 'inference-update-3',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 4),
      experimentEnabledVersion: const Version(3, 4),
      experimentReleasedVersion: const Version(3, 4));

  static const ExperimentalFlag inferenceUpdate4 = const ExperimentalFlag(
      name: 'inference-update-4',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: defaultLanguageVersion);

  static const ExperimentalFlag inferenceUsingBounds = const ExperimentalFlag(
      name: 'inference-using-bounds',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 7),
      experimentEnabledVersion: const Version(3, 7),
      experimentReleasedVersion: const Version(3, 7));

  static const ExperimentalFlag inlineClass = const ExperimentalFlag(
      name: 'inline-class',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 3),
      experimentEnabledVersion: const Version(3, 3),
      experimentReleasedVersion: const Version(3, 3));

  static const ExperimentalFlag macros = const ExperimentalFlag(
      name: 'macros',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: const Version(3, 3));

  static const ExperimentalFlag namedArgumentsAnywhere = const ExperimentalFlag(
      name: 'named-arguments-anywhere',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 17),
      experimentEnabledVersion: const Version(2, 17),
      experimentReleasedVersion: const Version(2, 17));

  static const ExperimentalFlag nativeAssets = const ExperimentalFlag(
      name: 'native-assets',
      isEnabledByDefault: true,
      isExpired: false,
      enabledVersion: const Version(3, 9),
      experimentEnabledVersion: const Version(3, 9),
      experimentReleasedVersion: const Version(3, 9));

  static const ExperimentalFlag nonNullable = const ExperimentalFlag(
      name: 'non-nullable',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 12),
      experimentEnabledVersion: const Version(2, 12),
      experimentReleasedVersion: const Version(2, 10));

  static const ExperimentalFlag nonfunctionTypeAliases = const ExperimentalFlag(
      name: 'nonfunction-type-aliases',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 13),
      experimentEnabledVersion: const Version(2, 13),
      experimentReleasedVersion: const Version(2, 13));

  static const ExperimentalFlag nullAwareElements = const ExperimentalFlag(
      name: 'null-aware-elements',
      isEnabledByDefault: true,
      isExpired: false,
      enabledVersion: const Version(3, 8),
      experimentEnabledVersion: const Version(3, 8),
      experimentReleasedVersion: const Version(3, 8));

  static const ExperimentalFlag patterns = const ExperimentalFlag(
      name: 'patterns',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 0),
      experimentEnabledVersion: const Version(3, 0),
      experimentReleasedVersion: const Version(3, 0));

  static const ExperimentalFlag recordUse = const ExperimentalFlag(
      name: 'record-use',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: defaultLanguageVersion);

  static const ExperimentalFlag records = const ExperimentalFlag(
      name: 'records',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 0),
      experimentEnabledVersion: const Version(3, 0),
      experimentReleasedVersion: const Version(3, 0));

  static const ExperimentalFlag sealedClass = const ExperimentalFlag(
      name: 'sealed-class',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 0),
      experimentEnabledVersion: const Version(3, 0),
      experimentReleasedVersion: const Version(3, 0));

  static const ExperimentalFlag setLiterals = const ExperimentalFlag(
      name: 'set-literals',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 0),
      experimentEnabledVersion: const Version(2, 0),
      experimentReleasedVersion: const Version(2, 0));

  static const ExperimentalFlag soundFlowAnalysis = const ExperimentalFlag(
      name: 'sound-flow-analysis',
      isEnabledByDefault: true,
      isExpired: false,
      enabledVersion: const Version(3, 9),
      experimentEnabledVersion: const Version(3, 9),
      experimentReleasedVersion: const Version(3, 9));

  static const ExperimentalFlag spreadCollections = const ExperimentalFlag(
      name: 'spread-collections',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 0),
      experimentEnabledVersion: const Version(2, 0),
      experimentReleasedVersion: const Version(2, 0));

  static const ExperimentalFlag superParameters = const ExperimentalFlag(
      name: 'super-parameters',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 17),
      experimentEnabledVersion: const Version(2, 17),
      experimentReleasedVersion: const Version(2, 17));

  static const ExperimentalFlag testExperiment = const ExperimentalFlag(
      name: 'test-experiment',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: defaultLanguageVersion);

  static const ExperimentalFlag tripleShift = const ExperimentalFlag(
      name: 'triple-shift',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 14),
      experimentEnabledVersion: const Version(2, 14),
      experimentReleasedVersion: const Version(2, 14));

  static const ExperimentalFlag unnamedLibraries = const ExperimentalFlag(
      name: 'unnamed-libraries',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(2, 19),
      experimentEnabledVersion: const Version(2, 19),
      experimentReleasedVersion: const Version(2, 19));

  static const ExperimentalFlag unquotedImports = const ExperimentalFlag(
      name: 'unquoted-imports',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: defaultLanguageVersion);

  static const ExperimentalFlag variance = const ExperimentalFlag(
      name: 'variance',
      isEnabledByDefault: false,
      isExpired: false,
      enabledVersion: defaultLanguageVersion,
      experimentEnabledVersion: defaultLanguageVersion,
      experimentReleasedVersion: defaultLanguageVersion);

  static const ExperimentalFlag wildcardVariables = const ExperimentalFlag(
      name: 'wildcard-variables',
      isEnabledByDefault: true,
      isExpired: true,
      enabledVersion: const Version(3, 7),
      experimentEnabledVersion: const Version(3, 7),
      experimentReleasedVersion: const Version(3, 7));
}

/// Interface for accessing the global state of experimental features.
class GlobalFeatures {
  final Map<ExperimentalFlag, bool> explicitExperimentalFlags;
  final AllowedExperimentalFlags? allowedExperimentalFlags;
  final Map<ExperimentalFlag, bool>? defaultExperimentFlagsForTesting;
  final Map<ExperimentalFlag, Version>? experimentEnabledVersionForTesting;
  final Map<ExperimentalFlag, Version>? experimentReleasedVersionForTesting;

  GlobalFeatures(this.explicitExperimentalFlags,
      {this.allowedExperimentalFlags,
      this.defaultExperimentFlagsForTesting,
      this.experimentEnabledVersionForTesting,
      this.experimentReleasedVersionForTesting});

  GlobalFeature _computeGlobalFeature(ExperimentalFlag flag) {
    return new GlobalFeature(
        flag,
        isExperimentEnabled(flag,
            defaultExperimentFlagsForTesting: defaultExperimentFlagsForTesting,
            explicitExperimentalFlags: explicitExperimentalFlags));
  }

  LibraryFeature _computeLibraryFeature(
      ExperimentalFlag flag, Uri canonicalUri, Version libraryVersion) {
    return new LibraryFeature(
        flag,
        isExperimentEnabledInLibrary(flag, canonicalUri,
            defaultExperimentFlagsForTesting: defaultExperimentFlagsForTesting,
            explicitExperimentalFlags: explicitExperimentalFlags,
            allowedExperimentalFlags: allowedExperimentalFlags),
        getExperimentEnabledVersionInLibrary(
            flag, canonicalUri, explicitExperimentalFlags,
            allowedExperimentalFlags: allowedExperimentalFlags,
            defaultExperimentFlagsForTesting: defaultExperimentFlagsForTesting,
            experimentEnabledVersionForTesting:
                experimentEnabledVersionForTesting,
            experimentReleasedVersionForTesting:
                experimentReleasedVersionForTesting),
        isExperimentEnabledInLibraryByVersion(
            flag, canonicalUri, libraryVersion,
            defaultExperimentFlagsForTesting: defaultExperimentFlagsForTesting,
            explicitExperimentalFlags: explicitExperimentalFlags,
            allowedExperimentalFlags: allowedExperimentalFlags));
  }

  GlobalFeature? _alternativeInvalidationStrategy;
  GlobalFeature get alternativeInvalidationStrategy =>
      _alternativeInvalidationStrategy ??= _computeGlobalFeature(
          ExperimentalFlag.alternativeInvalidationStrategy);

  GlobalFeature? _augmentations;
  GlobalFeature get augmentations =>
      _augmentations ??= _computeGlobalFeature(ExperimentalFlag.augmentations);

  GlobalFeature? _classModifiers;
  GlobalFeature get classModifiers => _classModifiers ??=
      _computeGlobalFeature(ExperimentalFlag.classModifiers);

  GlobalFeature? _constFunctions;
  GlobalFeature get constFunctions => _constFunctions ??=
      _computeGlobalFeature(ExperimentalFlag.constFunctions);

  GlobalFeature? _constantUpdate2018;
  GlobalFeature get constantUpdate2018 => _constantUpdate2018 ??=
      _computeGlobalFeature(ExperimentalFlag.constantUpdate2018);

  GlobalFeature? _constructorTearoffs;
  GlobalFeature get constructorTearoffs => _constructorTearoffs ??=
      _computeGlobalFeature(ExperimentalFlag.constructorTearoffs);

  GlobalFeature? _controlFlowCollections;
  GlobalFeature get controlFlowCollections => _controlFlowCollections ??=
      _computeGlobalFeature(ExperimentalFlag.controlFlowCollections);

  GlobalFeature? _digitSeparators;
  GlobalFeature get digitSeparators => _digitSeparators ??=
      _computeGlobalFeature(ExperimentalFlag.digitSeparators);

  GlobalFeature? _dotShorthands;
  GlobalFeature get dotShorthands =>
      _dotShorthands ??= _computeGlobalFeature(ExperimentalFlag.dotShorthands);

  GlobalFeature? _enhancedEnums;
  GlobalFeature get enhancedEnums =>
      _enhancedEnums ??= _computeGlobalFeature(ExperimentalFlag.enhancedEnums);

  GlobalFeature? _enhancedParts;
  GlobalFeature get enhancedParts =>
      _enhancedParts ??= _computeGlobalFeature(ExperimentalFlag.enhancedParts);

  GlobalFeature? _extensionMethods;
  GlobalFeature get extensionMethods => _extensionMethods ??=
      _computeGlobalFeature(ExperimentalFlag.extensionMethods);

  GlobalFeature? _genericMetadata;
  GlobalFeature get genericMetadata => _genericMetadata ??=
      _computeGlobalFeature(ExperimentalFlag.genericMetadata);

  GlobalFeature? _getterSetterError;
  GlobalFeature get getterSetterError => _getterSetterError ??=
      _computeGlobalFeature(ExperimentalFlag.getterSetterError);

  GlobalFeature? _inferenceUpdate1;
  GlobalFeature get inferenceUpdate1 => _inferenceUpdate1 ??=
      _computeGlobalFeature(ExperimentalFlag.inferenceUpdate1);

  GlobalFeature? _inferenceUpdate2;
  GlobalFeature get inferenceUpdate2 => _inferenceUpdate2 ??=
      _computeGlobalFeature(ExperimentalFlag.inferenceUpdate2);

  GlobalFeature? _inferenceUpdate3;
  GlobalFeature get inferenceUpdate3 => _inferenceUpdate3 ??=
      _computeGlobalFeature(ExperimentalFlag.inferenceUpdate3);

  GlobalFeature? _inferenceUpdate4;
  GlobalFeature get inferenceUpdate4 => _inferenceUpdate4 ??=
      _computeGlobalFeature(ExperimentalFlag.inferenceUpdate4);

  GlobalFeature? _inferenceUsingBounds;
  GlobalFeature get inferenceUsingBounds => _inferenceUsingBounds ??=
      _computeGlobalFeature(ExperimentalFlag.inferenceUsingBounds);

  GlobalFeature? _inlineClass;
  GlobalFeature get inlineClass =>
      _inlineClass ??= _computeGlobalFeature(ExperimentalFlag.inlineClass);

  GlobalFeature? _macros;
  GlobalFeature get macros =>
      _macros ??= _computeGlobalFeature(ExperimentalFlag.macros);

  GlobalFeature? _namedArgumentsAnywhere;
  GlobalFeature get namedArgumentsAnywhere => _namedArgumentsAnywhere ??=
      _computeGlobalFeature(ExperimentalFlag.namedArgumentsAnywhere);

  GlobalFeature? _nativeAssets;
  GlobalFeature get nativeAssets =>
      _nativeAssets ??= _computeGlobalFeature(ExperimentalFlag.nativeAssets);

  GlobalFeature? _nonNullable;
  GlobalFeature get nonNullable =>
      _nonNullable ??= _computeGlobalFeature(ExperimentalFlag.nonNullable);

  GlobalFeature? _nonfunctionTypeAliases;
  GlobalFeature get nonfunctionTypeAliases => _nonfunctionTypeAliases ??=
      _computeGlobalFeature(ExperimentalFlag.nonfunctionTypeAliases);

  GlobalFeature? _nullAwareElements;
  GlobalFeature get nullAwareElements => _nullAwareElements ??=
      _computeGlobalFeature(ExperimentalFlag.nullAwareElements);

  GlobalFeature? _patterns;
  GlobalFeature get patterns =>
      _patterns ??= _computeGlobalFeature(ExperimentalFlag.patterns);

  GlobalFeature? _recordUse;
  GlobalFeature get recordUse =>
      _recordUse ??= _computeGlobalFeature(ExperimentalFlag.recordUse);

  GlobalFeature? _records;
  GlobalFeature get records =>
      _records ??= _computeGlobalFeature(ExperimentalFlag.records);

  GlobalFeature? _sealedClass;
  GlobalFeature get sealedClass =>
      _sealedClass ??= _computeGlobalFeature(ExperimentalFlag.sealedClass);

  GlobalFeature? _setLiterals;
  GlobalFeature get setLiterals =>
      _setLiterals ??= _computeGlobalFeature(ExperimentalFlag.setLiterals);

  GlobalFeature? _soundFlowAnalysis;
  GlobalFeature get soundFlowAnalysis => _soundFlowAnalysis ??=
      _computeGlobalFeature(ExperimentalFlag.soundFlowAnalysis);

  GlobalFeature? _spreadCollections;
  GlobalFeature get spreadCollections => _spreadCollections ??=
      _computeGlobalFeature(ExperimentalFlag.spreadCollections);

  GlobalFeature? _superParameters;
  GlobalFeature get superParameters => _superParameters ??=
      _computeGlobalFeature(ExperimentalFlag.superParameters);

  GlobalFeature? _testExperiment;
  GlobalFeature get testExperiment => _testExperiment ??=
      _computeGlobalFeature(ExperimentalFlag.testExperiment);

  GlobalFeature? _tripleShift;
  GlobalFeature get tripleShift =>
      _tripleShift ??= _computeGlobalFeature(ExperimentalFlag.tripleShift);

  GlobalFeature? _unnamedLibraries;
  GlobalFeature get unnamedLibraries => _unnamedLibraries ??=
      _computeGlobalFeature(ExperimentalFlag.unnamedLibraries);

  GlobalFeature? _unquotedImports;
  GlobalFeature get unquotedImports => _unquotedImports ??=
      _computeGlobalFeature(ExperimentalFlag.unquotedImports);

  GlobalFeature? _variance;
  GlobalFeature get variance =>
      _variance ??= _computeGlobalFeature(ExperimentalFlag.variance);

  GlobalFeature? _wildcardVariables;
  GlobalFeature get wildcardVariables => _wildcardVariables ??=
      _computeGlobalFeature(ExperimentalFlag.wildcardVariables);
}

/// Interface for accessing the state of experimental features within a
/// specific library.
class LibraryFeatures {
  final GlobalFeatures globalFeatures;
  final Uri canonicalUri;
  final Version libraryVersion;

  LibraryFeatures(this.globalFeatures, this.canonicalUri, this.libraryVersion);

  LibraryFeature? _alternativeInvalidationStrategy;
  LibraryFeature get alternativeInvalidationStrategy =>
      _alternativeInvalidationStrategy ??=
          globalFeatures._computeLibraryFeature(
              ExperimentalFlag.alternativeInvalidationStrategy,
              canonicalUri,
              libraryVersion);

  LibraryFeature? _augmentations;
  LibraryFeature get augmentations =>
      _augmentations ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.augmentations, canonicalUri, libraryVersion);

  LibraryFeature? _classModifiers;
  LibraryFeature get classModifiers =>
      _classModifiers ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.classModifiers, canonicalUri, libraryVersion);

  LibraryFeature? _constFunctions;
  LibraryFeature get constFunctions =>
      _constFunctions ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.constFunctions, canonicalUri, libraryVersion);

  LibraryFeature? _constantUpdate2018;
  LibraryFeature get constantUpdate2018 =>
      _constantUpdate2018 ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.constantUpdate2018, canonicalUri, libraryVersion);

  LibraryFeature? _constructorTearoffs;
  LibraryFeature get constructorTearoffs =>
      _constructorTearoffs ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.constructorTearoffs, canonicalUri, libraryVersion);

  LibraryFeature? _controlFlowCollections;
  LibraryFeature get controlFlowCollections =>
      _controlFlowCollections ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.controlFlowCollections,
          canonicalUri,
          libraryVersion);

  LibraryFeature? _digitSeparators;
  LibraryFeature get digitSeparators =>
      _digitSeparators ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.digitSeparators, canonicalUri, libraryVersion);

  LibraryFeature? _dotShorthands;
  LibraryFeature get dotShorthands =>
      _dotShorthands ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.dotShorthands, canonicalUri, libraryVersion);

  LibraryFeature? _enhancedEnums;
  LibraryFeature get enhancedEnums =>
      _enhancedEnums ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.enhancedEnums, canonicalUri, libraryVersion);

  LibraryFeature? _enhancedParts;
  LibraryFeature get enhancedParts =>
      _enhancedParts ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.enhancedParts, canonicalUri, libraryVersion);

  LibraryFeature? _extensionMethods;
  LibraryFeature get extensionMethods =>
      _extensionMethods ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.extensionMethods, canonicalUri, libraryVersion);

  LibraryFeature? _genericMetadata;
  LibraryFeature get genericMetadata =>
      _genericMetadata ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.genericMetadata, canonicalUri, libraryVersion);

  LibraryFeature? _getterSetterError;
  LibraryFeature get getterSetterError =>
      _getterSetterError ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.getterSetterError, canonicalUri, libraryVersion);

  LibraryFeature? _inferenceUpdate1;
  LibraryFeature get inferenceUpdate1 =>
      _inferenceUpdate1 ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.inferenceUpdate1, canonicalUri, libraryVersion);

  LibraryFeature? _inferenceUpdate2;
  LibraryFeature get inferenceUpdate2 =>
      _inferenceUpdate2 ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.inferenceUpdate2, canonicalUri, libraryVersion);

  LibraryFeature? _inferenceUpdate3;
  LibraryFeature get inferenceUpdate3 =>
      _inferenceUpdate3 ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.inferenceUpdate3, canonicalUri, libraryVersion);

  LibraryFeature? _inferenceUpdate4;
  LibraryFeature get inferenceUpdate4 =>
      _inferenceUpdate4 ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.inferenceUpdate4, canonicalUri, libraryVersion);

  LibraryFeature? _inferenceUsingBounds;
  LibraryFeature get inferenceUsingBounds =>
      _inferenceUsingBounds ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.inferenceUsingBounds, canonicalUri, libraryVersion);

  LibraryFeature? _inlineClass;
  LibraryFeature get inlineClass =>
      _inlineClass ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.inlineClass, canonicalUri, libraryVersion);

  LibraryFeature? _macros;
  LibraryFeature get macros =>
      _macros ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.macros, canonicalUri, libraryVersion);

  LibraryFeature? _namedArgumentsAnywhere;
  LibraryFeature get namedArgumentsAnywhere =>
      _namedArgumentsAnywhere ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.namedArgumentsAnywhere,
          canonicalUri,
          libraryVersion);

  LibraryFeature? _nativeAssets;
  LibraryFeature get nativeAssets =>
      _nativeAssets ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.nativeAssets, canonicalUri, libraryVersion);

  LibraryFeature? _nonNullable;
  LibraryFeature get nonNullable =>
      _nonNullable ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.nonNullable, canonicalUri, libraryVersion);

  LibraryFeature? _nonfunctionTypeAliases;
  LibraryFeature get nonfunctionTypeAliases =>
      _nonfunctionTypeAliases ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.nonfunctionTypeAliases,
          canonicalUri,
          libraryVersion);

  LibraryFeature? _nullAwareElements;
  LibraryFeature get nullAwareElements =>
      _nullAwareElements ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.nullAwareElements, canonicalUri, libraryVersion);

  LibraryFeature? _patterns;
  LibraryFeature get patterns =>
      _patterns ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.patterns, canonicalUri, libraryVersion);

  LibraryFeature? _recordUse;
  LibraryFeature get recordUse =>
      _recordUse ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.recordUse, canonicalUri, libraryVersion);

  LibraryFeature? _records;
  LibraryFeature get records =>
      _records ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.records, canonicalUri, libraryVersion);

  LibraryFeature? _sealedClass;
  LibraryFeature get sealedClass =>
      _sealedClass ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.sealedClass, canonicalUri, libraryVersion);

  LibraryFeature? _setLiterals;
  LibraryFeature get setLiterals =>
      _setLiterals ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.setLiterals, canonicalUri, libraryVersion);

  LibraryFeature? _soundFlowAnalysis;
  LibraryFeature get soundFlowAnalysis =>
      _soundFlowAnalysis ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.soundFlowAnalysis, canonicalUri, libraryVersion);

  LibraryFeature? _spreadCollections;
  LibraryFeature get spreadCollections =>
      _spreadCollections ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.spreadCollections, canonicalUri, libraryVersion);

  LibraryFeature? _superParameters;
  LibraryFeature get superParameters =>
      _superParameters ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.superParameters, canonicalUri, libraryVersion);

  LibraryFeature? _testExperiment;
  LibraryFeature get testExperiment =>
      _testExperiment ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.testExperiment, canonicalUri, libraryVersion);

  LibraryFeature? _tripleShift;
  LibraryFeature get tripleShift =>
      _tripleShift ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.tripleShift, canonicalUri, libraryVersion);

  LibraryFeature? _unnamedLibraries;
  LibraryFeature get unnamedLibraries =>
      _unnamedLibraries ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.unnamedLibraries, canonicalUri, libraryVersion);

  LibraryFeature? _unquotedImports;
  LibraryFeature get unquotedImports =>
      _unquotedImports ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.unquotedImports, canonicalUri, libraryVersion);

  LibraryFeature? _variance;
  LibraryFeature get variance =>
      _variance ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.variance, canonicalUri, libraryVersion);

  LibraryFeature? _wildcardVariables;
  LibraryFeature get wildcardVariables =>
      _wildcardVariables ??= globalFeatures._computeLibraryFeature(
          ExperimentalFlag.wildcardVariables, canonicalUri, libraryVersion);

  /// Returns the [LibraryFeature] corresponding to [experimentalFlag].
  LibraryFeature fromSharedExperimentalFlags(
      shared.ExperimentalFlag experimentalFlag) {
    switch (experimentalFlag) {
      case shared.ExperimentalFlag.augmentations:
        return augmentations;
      case shared.ExperimentalFlag.classModifiers:
        return classModifiers;
      case shared.ExperimentalFlag.constFunctions:
        return constFunctions;
      case shared.ExperimentalFlag.constantUpdate2018:
        return constantUpdate2018;
      case shared.ExperimentalFlag.constructorTearoffs:
        return constructorTearoffs;
      case shared.ExperimentalFlag.controlFlowCollections:
        return controlFlowCollections;
      case shared.ExperimentalFlag.digitSeparators:
        return digitSeparators;
      case shared.ExperimentalFlag.dotShorthands:
        return dotShorthands;
      case shared.ExperimentalFlag.enhancedEnums:
        return enhancedEnums;
      case shared.ExperimentalFlag.enhancedParts:
        return enhancedParts;
      case shared.ExperimentalFlag.extensionMethods:
        return extensionMethods;
      case shared.ExperimentalFlag.genericMetadata:
        return genericMetadata;
      case shared.ExperimentalFlag.getterSetterError:
        return getterSetterError;
      case shared.ExperimentalFlag.inferenceUpdate1:
        return inferenceUpdate1;
      case shared.ExperimentalFlag.inferenceUpdate2:
        return inferenceUpdate2;
      case shared.ExperimentalFlag.inferenceUpdate3:
        return inferenceUpdate3;
      case shared.ExperimentalFlag.inferenceUpdate4:
        return inferenceUpdate4;
      case shared.ExperimentalFlag.inferenceUsingBounds:
        return inferenceUsingBounds;
      case shared.ExperimentalFlag.inlineClass:
        return inlineClass;
      case shared.ExperimentalFlag.macros:
        return macros;
      case shared.ExperimentalFlag.namedArgumentsAnywhere:
        return namedArgumentsAnywhere;
      case shared.ExperimentalFlag.nativeAssets:
        return nativeAssets;
      case shared.ExperimentalFlag.nonNullable:
        return nonNullable;
      case shared.ExperimentalFlag.nonfunctionTypeAliases:
        return nonfunctionTypeAliases;
      case shared.ExperimentalFlag.nullAwareElements:
        return nullAwareElements;
      case shared.ExperimentalFlag.patterns:
        return patterns;
      case shared.ExperimentalFlag.recordUse:
        return recordUse;
      case shared.ExperimentalFlag.records:
        return records;
      case shared.ExperimentalFlag.sealedClass:
        return sealedClass;
      case shared.ExperimentalFlag.setLiterals:
        return setLiterals;
      case shared.ExperimentalFlag.soundFlowAnalysis:
        return soundFlowAnalysis;
      case shared.ExperimentalFlag.spreadCollections:
        return spreadCollections;
      case shared.ExperimentalFlag.superParameters:
        return superParameters;
      case shared.ExperimentalFlag.testExperiment:
        return testExperiment;
      case shared.ExperimentalFlag.tripleShift:
        return tripleShift;
      case shared.ExperimentalFlag.unnamedLibraries:
        return unnamedLibraries;
      case shared.ExperimentalFlag.unquotedImports:
        return unquotedImports;
      case shared.ExperimentalFlag.variance:
        return variance;
      case shared.ExperimentalFlag.wildcardVariables:
        return wildcardVariables;
    }
  }
}

ExperimentalFlag? parseExperimentalFlag(String flag) {
  switch (flag) {
    case "alternative-invalidation-strategy":
      return ExperimentalFlag.alternativeInvalidationStrategy;
    case "augmentations":
      return ExperimentalFlag.augmentations;
    case "class-modifiers":
      return ExperimentalFlag.classModifiers;
    case "const-functions":
      return ExperimentalFlag.constFunctions;
    case "constant-update-2018":
      return ExperimentalFlag.constantUpdate2018;
    case "constructor-tearoffs":
      return ExperimentalFlag.constructorTearoffs;
    case "control-flow-collections":
      return ExperimentalFlag.controlFlowCollections;
    case "digit-separators":
      return ExperimentalFlag.digitSeparators;
    case "dot-shorthands":
      return ExperimentalFlag.dotShorthands;
    case "enhanced-enums":
      return ExperimentalFlag.enhancedEnums;
    case "enhanced-parts":
      return ExperimentalFlag.enhancedParts;
    case "extension-methods":
      return ExperimentalFlag.extensionMethods;
    case "generic-metadata":
      return ExperimentalFlag.genericMetadata;
    case "getter-setter-error":
      return ExperimentalFlag.getterSetterError;
    case "inference-update-1":
      return ExperimentalFlag.inferenceUpdate1;
    case "inference-update-2":
      return ExperimentalFlag.inferenceUpdate2;
    case "inference-update-3":
      return ExperimentalFlag.inferenceUpdate3;
    case "inference-update-4":
      return ExperimentalFlag.inferenceUpdate4;
    case "inference-using-bounds":
      return ExperimentalFlag.inferenceUsingBounds;
    case "inline-class":
      return ExperimentalFlag.inlineClass;
    case "macros":
      return ExperimentalFlag.macros;
    case "named-arguments-anywhere":
      return ExperimentalFlag.namedArgumentsAnywhere;
    case "native-assets":
      return ExperimentalFlag.nativeAssets;
    case "non-nullable":
      return ExperimentalFlag.nonNullable;
    case "nonfunction-type-aliases":
      return ExperimentalFlag.nonfunctionTypeAliases;
    case "null-aware-elements":
      return ExperimentalFlag.nullAwareElements;
    case "patterns":
      return ExperimentalFlag.patterns;
    case "record-use":
      return ExperimentalFlag.recordUse;
    case "records":
      return ExperimentalFlag.records;
    case "sealed-class":
      return ExperimentalFlag.sealedClass;
    case "set-literals":
      return ExperimentalFlag.setLiterals;
    case "sound-flow-analysis":
      return ExperimentalFlag.soundFlowAnalysis;
    case "spread-collections":
      return ExperimentalFlag.spreadCollections;
    case "super-parameters":
      return ExperimentalFlag.superParameters;
    case "test-experiment":
      return ExperimentalFlag.testExperiment;
    case "triple-shift":
      return ExperimentalFlag.tripleShift;
    case "unnamed-libraries":
      return ExperimentalFlag.unnamedLibraries;
    case "unquoted-imports":
      return ExperimentalFlag.unquotedImports;
    case "variance":
      return ExperimentalFlag.variance;
    case "wildcard-variables":
      return ExperimentalFlag.wildcardVariables;
  }
  return null;
}

final Map<ExperimentalFlag, bool> defaultExperimentalFlags = {
  ExperimentalFlag.alternativeInvalidationStrategy:
      ExperimentalFlag.alternativeInvalidationStrategy.isEnabledByDefault,
  ExperimentalFlag.augmentations:
      ExperimentalFlag.augmentations.isEnabledByDefault,
  ExperimentalFlag.classModifiers:
      ExperimentalFlag.classModifiers.isEnabledByDefault,
  ExperimentalFlag.constFunctions:
      ExperimentalFlag.constFunctions.isEnabledByDefault,
  ExperimentalFlag.constantUpdate2018:
      ExperimentalFlag.constantUpdate2018.isEnabledByDefault,
  ExperimentalFlag.constructorTearoffs:
      ExperimentalFlag.constructorTearoffs.isEnabledByDefault,
  ExperimentalFlag.controlFlowCollections:
      ExperimentalFlag.controlFlowCollections.isEnabledByDefault,
  ExperimentalFlag.digitSeparators:
      ExperimentalFlag.digitSeparators.isEnabledByDefault,
  ExperimentalFlag.dotShorthands:
      ExperimentalFlag.dotShorthands.isEnabledByDefault,
  ExperimentalFlag.enhancedEnums:
      ExperimentalFlag.enhancedEnums.isEnabledByDefault,
  ExperimentalFlag.enhancedParts:
      ExperimentalFlag.enhancedParts.isEnabledByDefault,
  ExperimentalFlag.extensionMethods:
      ExperimentalFlag.extensionMethods.isEnabledByDefault,
  ExperimentalFlag.genericMetadata:
      ExperimentalFlag.genericMetadata.isEnabledByDefault,
  ExperimentalFlag.getterSetterError:
      ExperimentalFlag.getterSetterError.isEnabledByDefault,
  ExperimentalFlag.inferenceUpdate1:
      ExperimentalFlag.inferenceUpdate1.isEnabledByDefault,
  ExperimentalFlag.inferenceUpdate2:
      ExperimentalFlag.inferenceUpdate2.isEnabledByDefault,
  ExperimentalFlag.inferenceUpdate3:
      ExperimentalFlag.inferenceUpdate3.isEnabledByDefault,
  ExperimentalFlag.inferenceUpdate4:
      ExperimentalFlag.inferenceUpdate4.isEnabledByDefault,
  ExperimentalFlag.inferenceUsingBounds:
      ExperimentalFlag.inferenceUsingBounds.isEnabledByDefault,
  ExperimentalFlag.inlineClass: ExperimentalFlag.inlineClass.isEnabledByDefault,
  ExperimentalFlag.macros: ExperimentalFlag.macros.isEnabledByDefault,
  ExperimentalFlag.namedArgumentsAnywhere:
      ExperimentalFlag.namedArgumentsAnywhere.isEnabledByDefault,
  ExperimentalFlag.nativeAssets:
      ExperimentalFlag.nativeAssets.isEnabledByDefault,
  ExperimentalFlag.nonNullable: ExperimentalFlag.nonNullable.isEnabledByDefault,
  ExperimentalFlag.nonfunctionTypeAliases:
      ExperimentalFlag.nonfunctionTypeAliases.isEnabledByDefault,
  ExperimentalFlag.nullAwareElements:
      ExperimentalFlag.nullAwareElements.isEnabledByDefault,
  ExperimentalFlag.patterns: ExperimentalFlag.patterns.isEnabledByDefault,
  ExperimentalFlag.recordUse: ExperimentalFlag.recordUse.isEnabledByDefault,
  ExperimentalFlag.records: ExperimentalFlag.records.isEnabledByDefault,
  ExperimentalFlag.sealedClass: ExperimentalFlag.sealedClass.isEnabledByDefault,
  ExperimentalFlag.setLiterals: ExperimentalFlag.setLiterals.isEnabledByDefault,
  ExperimentalFlag.soundFlowAnalysis:
      ExperimentalFlag.soundFlowAnalysis.isEnabledByDefault,
  ExperimentalFlag.spreadCollections:
      ExperimentalFlag.spreadCollections.isEnabledByDefault,
  ExperimentalFlag.superParameters:
      ExperimentalFlag.superParameters.isEnabledByDefault,
  ExperimentalFlag.testExperiment:
      ExperimentalFlag.testExperiment.isEnabledByDefault,
  ExperimentalFlag.tripleShift: ExperimentalFlag.tripleShift.isEnabledByDefault,
  ExperimentalFlag.unnamedLibraries:
      ExperimentalFlag.unnamedLibraries.isEnabledByDefault,
  ExperimentalFlag.unquotedImports:
      ExperimentalFlag.unquotedImports.isEnabledByDefault,
  ExperimentalFlag.variance: ExperimentalFlag.variance.isEnabledByDefault,
  ExperimentalFlag.wildcardVariables:
      ExperimentalFlag.wildcardVariables.isEnabledByDefault,
};
const AllowedExperimentalFlags defaultAllowedExperimentalFlags =
    const AllowedExperimentalFlags(
        sdkDefaultExperiments: {},
        sdkLibraryExperiments: {},
        packageExperiments: {
      "json": {
        ExperimentalFlag.enhancedParts,
        ExperimentalFlag.macros,
      },
    });
const Map<shared.ExperimentalFlag, ExperimentalFlag> sharedExperimentalFlags = {
  shared.ExperimentalFlag.augmentations: ExperimentalFlag.augmentations,
  shared.ExperimentalFlag.classModifiers: ExperimentalFlag.classModifiers,
  shared.ExperimentalFlag.constFunctions: ExperimentalFlag.constFunctions,
  shared.ExperimentalFlag.constantUpdate2018:
      ExperimentalFlag.constantUpdate2018,
  shared.ExperimentalFlag.constructorTearoffs:
      ExperimentalFlag.constructorTearoffs,
  shared.ExperimentalFlag.controlFlowCollections:
      ExperimentalFlag.controlFlowCollections,
  shared.ExperimentalFlag.digitSeparators: ExperimentalFlag.digitSeparators,
  shared.ExperimentalFlag.dotShorthands: ExperimentalFlag.dotShorthands,
  shared.ExperimentalFlag.enhancedEnums: ExperimentalFlag.enhancedEnums,
  shared.ExperimentalFlag.enhancedParts: ExperimentalFlag.enhancedParts,
  shared.ExperimentalFlag.extensionMethods: ExperimentalFlag.extensionMethods,
  shared.ExperimentalFlag.genericMetadata: ExperimentalFlag.genericMetadata,
  shared.ExperimentalFlag.getterSetterError: ExperimentalFlag.getterSetterError,
  shared.ExperimentalFlag.inferenceUpdate1: ExperimentalFlag.inferenceUpdate1,
  shared.ExperimentalFlag.inferenceUpdate2: ExperimentalFlag.inferenceUpdate2,
  shared.ExperimentalFlag.inferenceUpdate3: ExperimentalFlag.inferenceUpdate3,
  shared.ExperimentalFlag.inferenceUpdate4: ExperimentalFlag.inferenceUpdate4,
  shared.ExperimentalFlag.inferenceUsingBounds:
      ExperimentalFlag.inferenceUsingBounds,
  shared.ExperimentalFlag.inlineClass: ExperimentalFlag.inlineClass,
  shared.ExperimentalFlag.macros: ExperimentalFlag.macros,
  shared.ExperimentalFlag.namedArgumentsAnywhere:
      ExperimentalFlag.namedArgumentsAnywhere,
  shared.ExperimentalFlag.nativeAssets: ExperimentalFlag.nativeAssets,
  shared.ExperimentalFlag.nonNullable: ExperimentalFlag.nonNullable,
  shared.ExperimentalFlag.nonfunctionTypeAliases:
      ExperimentalFlag.nonfunctionTypeAliases,
  shared.ExperimentalFlag.nullAwareElements: ExperimentalFlag.nullAwareElements,
  shared.ExperimentalFlag.patterns: ExperimentalFlag.patterns,
  shared.ExperimentalFlag.recordUse: ExperimentalFlag.recordUse,
  shared.ExperimentalFlag.records: ExperimentalFlag.records,
  shared.ExperimentalFlag.sealedClass: ExperimentalFlag.sealedClass,
  shared.ExperimentalFlag.setLiterals: ExperimentalFlag.setLiterals,
  shared.ExperimentalFlag.soundFlowAnalysis: ExperimentalFlag.soundFlowAnalysis,
  shared.ExperimentalFlag.spreadCollections: ExperimentalFlag.spreadCollections,
  shared.ExperimentalFlag.superParameters: ExperimentalFlag.superParameters,
  shared.ExperimentalFlag.testExperiment: ExperimentalFlag.testExperiment,
  shared.ExperimentalFlag.tripleShift: ExperimentalFlag.tripleShift,
  shared.ExperimentalFlag.unnamedLibraries: ExperimentalFlag.unnamedLibraries,
  shared.ExperimentalFlag.unquotedImports: ExperimentalFlag.unquotedImports,
  shared.ExperimentalFlag.variance: ExperimentalFlag.variance,
  shared.ExperimentalFlag.wildcardVariables: ExperimentalFlag.wildcardVariables,
};
