// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Common compiler options and helper functions used for testing.
library front_end.testing.compiler_options_common;

import 'dart:typed_data';

import 'package:kernel/ast.dart' show Library, Component;

import '../api_prototype/front_end.dart'
    show
        CompilerOptions,
        CompilerResult,
        kernelForModule,
        kernelForProgramInternal,
        summaryFor;
import '../api_prototype/memory_file_system.dart'
    show MemoryFileSystem, MemoryFileSystemEntity;
import '../base/hybrid_file_system.dart' show HybridFileSystem;
import '../compute_platform_binaries_location.dart'
    show computePlatformBinariesLocation;

/// Generate kernel for a script.
///
/// [scriptOrSources] can be a String, in which case it is the script to be
/// compiled, or a Map containing source files. In which case, this function
/// compiles the entry whose name is [fileName].
///
/// Wraps [kernelForProgram] with some default testing options (see [setup]).
Future<CompilerResult?> compileScript(dynamic scriptOrSources,
    {String fileName = 'main.dart',
    List<String> additionalDills = const [],
    CompilerOptions? options,
    bool retainDataForTesting = false,
    bool requireMain = true}) async {
  options ??= new CompilerOptions();
  Map<String, dynamic> sources;
  if (scriptOrSources is String) {
    sources = {fileName: scriptOrSources};
  } else {
    assert(scriptOrSources is Map);
    sources = scriptOrSources;
  }
  await setup(options, sources, additionalDills: additionalDills);
  return await kernelForProgramInternal(toTestUri(fileName), options,
      retainDataForTesting: retainDataForTesting, requireMain: requireMain);
}

/// Generate a component for a modular compilation unit.
///
/// Wraps [kernelForModule] with some default testing options (see [setup]).
Future<Component?> compileUnit(
    List<String> inputs, Map<String, dynamic> sources,
    {List<String> additionalDills = const [], CompilerOptions? options}) async {
  options ??= new CompilerOptions();
  await setup(options, sources, additionalDills: additionalDills);
  return (await kernelForModule(inputs.map(toTestUri).toList(), options))
      .component;
}

/// Generate a summary for a modular compilation unit.
///
/// Wraps [summaryFor] with some default testing options (see [setup]).
Future<Uint8List?> summarize(List<String> inputs, Map<String, dynamic> sources,
    {List<String> additionalDills = const [],
    CompilerOptions? options,
    bool truncate = false}) async {
  options ??= new CompilerOptions();
  await setup(options, sources, additionalDills: additionalDills);
  return await summaryFor(inputs.map(toTestUri).toList(), options,
      truncate: truncate);
}

/// Defines a default set of options for testing:
///
///   * create a hybrid file system that stores [sources] in memory but allows
///   access to the physical file system to load the SDK. [sources] can
///   contain either source files (value is [String]) or .dill files (value
///   is [List<int>]).
///
///   * define an empty `package_config.json` file (if one isn't defined in
///     sources).
///
///   * specify the location of the sdk summaries.
Future<Null> setup(CompilerOptions options, Map<String, dynamic> sources,
    {List<String> additionalDills = const []}) async {
  MemoryFileSystem fs = createMemoryFileSystem();
  sources.forEach((name, data) {
    MemoryFileSystemEntity entity = fs.entityForUri(toTestUri(name));
    if (data is String) {
      entity.writeAsStringSync(data);
    } else {
      entity.writeAsBytesSync(data);
    }
  });
  MemoryFileSystemEntity packageConfigFile =
      fs.entityForUri(toTestUri('.dart_tool/package_config.json'));
  if (!await packageConfigFile.exists()) {
    packageConfigFile.writeAsStringSync('{"configVersion": 2, "packages": []}');
  }
  fs
      .entityForUri(invalidCoreLibsSpecUri)
      .writeAsStringSync(_invalidLibrariesSpec);
  options
    ..verify = true
    ..fileSystem = new HybridFileSystem(fs)
    ..additionalDills = additionalDills.map(toTestUri).toList();
  if (options.packagesFileUri == null) {
    options.packagesFileUri = toTestUri('.dart_tool/package_config.json');
  }

  if (options.sdkSummary == null) {
    options.sdkRoot = computePlatformBinariesLocation(forceBuildDir: true);
  }
}

MemoryFileSystem createMemoryFileSystem() => new MemoryFileSystem(_defaultDir);

const String _testUriScheme = 'org-dartlang-test';

bool isTestUri(Uri uri) => uri.isScheme(_testUriScheme);

/// A fake absolute directory used as the root of a memory-file system in the
/// helpers above.
Uri _defaultDir = Uri.parse('${_testUriScheme}:///a/b/c/');

/// Convert relative file paths into an absolute Uri as expected by the test
/// helpers above.
Uri toTestUri(String relativePath) => _defaultDir.resolve(relativePath);

/// Uri to a libraries specification file that purposely provides
/// invalid Uris to dart:core and dart:async. Used by tests that want to ensure
/// that the sdk libraries are not loaded from sources, but read from a .dill
/// file.
Uri invalidCoreLibsSpecUri = toTestUri('invalid_sdk_libraries.json');

String _invalidLibrariesSpec = '''
{
  "vm": {
    "libraries": {
      "core":  {"uri": "/non_existing_file/core.dart"},
      "async": {"uri": "/non_existing_file/async.dart"}
    }
  }
}
''';

bool isDartCoreLibrary(Library lib) => isDartCore(lib.importUri);
bool isDartCore(Uri uri) => uri.isScheme('dart') && uri.path == 'core';

/// Find a library in [component] whose Uri ends with the given [suffix]
Library findLibrary(Component component, String suffix) {
  return component.libraries
      .firstWhere((lib) => lib.importUri.path.endsWith(suffix));
}
