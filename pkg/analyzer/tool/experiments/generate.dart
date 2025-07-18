/// This file contains code to generate experimental flags
/// based on the information in tools/experimental_features.yaml.
library;

import 'dart:io';

import 'package:_fe_analyzer_shared/src/scanner/characters.dart'
    show $MINUS, $_;
import 'package:analyzer_testing/package_root.dart' as pkg_root;
import 'package:analyzer_utilities/tools.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart' show YamlMap, loadYaml;

void main() async {
  await GeneratedContent.generateAll(pkg_root.packageRoot, allTargets);
}

List<GeneratedContent> get allTargets {
  var experimentsYaml =
      loadYaml(
            File(
              join(
                normalize(join(pkg_root.packageRoot, '../tools')),
                'experimental_features.yaml',
              ),
            ).readAsStringSync(),
          )
          as Map;

  return <GeneratedContent>[
    GeneratedFile('analyzer/lib/src/dart/analysis/experiments.g.dart', (
      pkgRoot,
    ) async {
      var generator = _ExperimentsGenerator(experimentsYaml);
      generator.generateFormatCode();
      return generator.out.toString();
    }),
  ];
}

String keyToIdentifier(String key) {
  var identifier = StringBuffer();
  for (int index = 0; index < key.length; ++index) {
    var code = key.codeUnitAt(index);
    if (code == $MINUS) {
      code = $_;
    }
    identifier.writeCharCode(code);
  }
  return identifier.toString();
}

class _ExperimentsGenerator {
  final Map experimentsYaml;

  late List<String> keysSorted;

  final out = StringBuffer('''
//
// THIS FILE IS GENERATED. DO NOT EDIT.
//
// Instead modify 'tools/experimental_features.yaml' and run
// 'dart pkg/analyzer/tool/experiments/generate.dart' to update.

part of 'experiments.dart';

// We allow some snake_case and SCREAMING_SNAKE_CASE identifiers in generated
// code, as they match names declared in the source configuration files.
// ignore_for_file: constant_identifier_names
''');

  Map<String, dynamic>? _features;

  _ExperimentsGenerator(this.experimentsYaml);

  Map<String, dynamic> get features {
    var features = _features;
    if (features != null) return features;

    features = <String, dynamic>{};
    var yamlFeatures = experimentsYaml['features'] as Map;
    for (MapEntry entry in yamlFeatures.entries) {
      var category =
          (entry.value as YamlMap)['category'] as String? ?? 'language';
      if (category != "language") {
        // Skip a feature with a category that's not language. In the future
        // possibly allow e.g. 'analyzer' etc.
        continue;
      }
      features[entry.key as String] = entry.value;
    }

    return _features = features;
  }

  void generateFormatCode() {
    keysSorted = features.keys.toList()..sort();
    generateSection_CurrentVersion();
    generateSection_KnownFeatures();
    generateSection_EnableString();
    generateSection_ExperimentalFeature();
    generateSection_IsEnabledByDefault();
    generateSection_IsExpired();
    generateSection_CurrentState();
  }

  void generateSection_CurrentState() {
    out.write('''

mixin _CurrentState {
''');
    for (var key in keysSorted) {
      var id = keyToIdentifier(key);
      out.write('''
  /// Current state for the flag "$key"
  bool get $id => isEnabled(ExperimentalFeatures.$id);
    ''');
    }
    out.write('''

  bool isEnabled(covariant ExperimentalFeature feature);
}''');
  }

  void generateSection_CurrentVersion() {
    var version = _versionNumberAsString(experimentsYaml['current-version']);
    out.write('''

/// The current version of the Dart language (or, for non-stable releases, the
/// version of the language currently in the process of being developed).
const _currentVersion = '$version';
    ''');
  }

  void generateSection_EnableString() {
    out.write('''

/// Constant strings for enabling each of the currently known experimental
/// flags.
class EnableString {
''');
    for (var key in keysSorted) {
      out.write('''
      /// String to enable the experiment "$key"
      static const String ${keyToIdentifier(key)} = '$key';
    ''');
    }
    out.write('''
    }''');
  }

  void generateSection_ExperimentalFeature() {
    out.write('''

class ExperimentalFeatures {
''');
    int index = 0;
    for (var key in keysSorted) {
      var id = keyToIdentifier(key);
      var help = (features[key] as YamlMap)['help'] ?? '';
      var experimentalReleaseVersion =
          (features[key] as YamlMap)['experimentalReleaseVersion'];
      var enabledIn = (features[key] as YamlMap)['enabledIn'];
      var channels =
          (((features[key] as YamlMap)['channels']) as List?)?.cast<String>();
      channels ??= ['stable', 'beta', 'dev', 'main'];
      var channelsLiteral = '[${channels.map((e) => '"$e"').join(', ')}]';
      out.write('''

      static final $id = ExperimentalFeature(
        index: $index,
        enableString: EnableString.$id,
        isEnabledByDefault: IsEnabledByDefault.$id,
        isExpired: IsExpired.$id,
        documentation: '$help',
    ''');

      if (experimentalReleaseVersion != null) {
        experimentalReleaseVersion = _versionNumberAsString(
          experimentalReleaseVersion,
        );
        out.write("experimentalReleaseVersion: ");
        out.write("Version.parse('$experimentalReleaseVersion'),");
      } else {
        out.write("experimentalReleaseVersion: null,");
      }

      if (enabledIn != null) {
        enabledIn = _versionNumberAsString(enabledIn);
        out.write("releaseVersion: Version.parse('$enabledIn'),");
      } else {
        out.write("releaseVersion: null,");
      }
      out.write("channels: $channelsLiteral,");
      out.writeln(');');
      ++index;
    }
    out.write('''
    }''');
  }

  void generateSection_IsEnabledByDefault() {
    out.write('''

/// Constant bools indicating whether each experimental flag is currently
/// enabled by default.
class IsEnabledByDefault {
''');
    for (var key in keysSorted) {
      var entry = features[key] as YamlMap;
      bool shipped = entry['enabledIn'] != null;
      out.write('''
      /// Default state of the experiment "$key"
      static const bool ${keyToIdentifier(key)} = $shipped;
    ''');
    }
    out.write('''
    }''');
  }

  void generateSection_IsExpired() {
    out.write('''

/// Constant bools indicating whether each experimental flag is currently
/// expired (meaning its enable/disable status can no longer be altered from the
/// value in [IsEnabledByDefault]).
class IsExpired {
''');
    for (var key in keysSorted) {
      var entry = features[key] as YamlMap;
      bool shipped = entry['enabledIn'] != null;
      var expired = entry['expired'] as bool?;
      out.write('''
      /// Expiration status of the experiment "$key"
      static const bool ${keyToIdentifier(key)} = ${expired == true};
    ''');
      if (shipped && expired == false) {
        throw 'Cannot mark shipped feature as "expired: false"';
      }
    }
    out.write('''
    }''');
  }

  void generateSection_KnownFeatures() {
    out.write('''

/// A map containing information about all known experimental flags.
final _knownFeatures = <String, ExperimentalFeature>{
''');
    for (var key in keysSorted) {
      var id = keyToIdentifier(key);
      out.write('''
  EnableString.$id: ExperimentalFeatures.$id,
    ''');
    }
    out.write('''
};
''');
  }

  String _versionNumberAsString(dynamic enabledIn) {
    if (enabledIn is double) {
      return '$enabledIn.0';
    } else {
      return enabledIn.toString();
    }
  }
}
