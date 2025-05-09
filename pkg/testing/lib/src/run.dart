// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library;

import 'dart:async' show Future, Stream;

import 'dart:convert' show json;

import 'dart:io' show Platform;

import 'dart:isolate' show Isolate, ReceivePort;

import 'test_root.dart' show TestRoot;

import 'error_handling.dart' show withErrorHandling;

import 'chain.dart' show CreateContext;

import '../testing.dart' show Chain, ChainContext;

import 'analyze.dart' show Analyze;

import 'log.dart'
    show enableVerboseOutput, isVerbose, Logger, splitLines, StdoutLogger;

import 'suite.dart' show Suite;

import 'zone_helper.dart' show acknowledgeControlMessages;

import 'run_tests.dart' show CommandLine;

Future<TestRoot> computeTestRoot(String? configurationPath, Uri? base) {
  Uri configuration = configurationPath == null
      ? Uri.base.resolve("testing.json")
      : base!.resolve(configurationPath);
  return TestRoot.fromUri(configuration);
}

/// This is called from a Chain suite, and helps implement main. In most cases,
/// main will look like this:
///
///     main(List<String> arguments) => runMe(arguments, createContext);
///
/// The optional argument [configurationPath] should be used when
/// `testing.json` isn't located in the current working directory and is a path
/// relative to [me] which defaults to `Platform.script`.
Future<void> runMe(List<String> arguments, CreateContext f,
    {String? configurationPath,
    Uri? me,
    int shards = 1,
    int shard = 0,
    int? limitTo,
    Logger logger = const StdoutLogger()}) {
  me ??= Platform.script;
  return withErrorHandling(() async {
    TestRoot testRoot = await computeTestRoot(configurationPath, me);
    CommandLine cl = CommandLine.parse(arguments);
    if (cl.verbose) enableVerboseOutput();
    for (Chain suite in testRoot.toolChains) {
      if (me == suite.source) {
        ChainContext context = await f(suite, cl.environment);
        await context.run(suite, Set<String>.from(cl.selectors),
            shards: shards, shard: shard, limitTo: limitTo, logger: logger);
      }
    }
  }, logger: logger);
}

/// This is called from a `_test.dart` file, and helps integration in other
/// test runner frameworks.
///
/// For example, to run the suite `my_suite` from `test.dart`, create a file
/// with this content:
///
///     import 'package:expect/async_helper.dart' show asyncTest;
///
///     import 'package:testing/testing.dart' show run;
///
///     main(List<String> arguments) => asyncTest(run(arguments, ["my_suite"]));
///
/// To run the same suite from `package:test`, create a file with this content:
///
///     import 'package:test/test.dart' show Timeout, test;
///
///     import 'package:testing/testing.dart' show run;
///
///     main() {
///       test("my_suite", () => run([], ["my_suite"]),
///           timeout: new Timeout(new Duration(minutes: 5)));
///     }
///
/// The optional argument [configurationPath] should be used when
/// `testing.json` isn't located in the current working directory and is a path
/// relative to `Uri.base`.
Future<void> run(List<String> arguments, List<String> suiteNames,
    [String? configurationPath]) {
  return withErrorHandling(() async {
    TestRoot root = await computeTestRoot(configurationPath, Uri.base);
    List<Suite> suites = root.suites
        .where((Suite suite) => suiteNames.contains(suite.name))
        .toList();
    SuiteRunner runner = SuiteRunner(
        suites, <String, String>{}, const <String>[], <String>{}, <String>{});
    String? program = await runner.generateDartProgram();
    await runner.analyze(root.packages);
    if (program != null) {
      await runProgram(program, root.packages);
    }
  });
}

Future<void> runProgram(String program, Uri packages) async {
  const StdoutLogger().logMessage("Running:");
  const StdoutLogger().logNumberedLines(program);
  Uri dataUri = Uri.dataFromString(program);
  ReceivePort exitPort = ReceivePort();
  Isolate isolate = await Isolate.spawnUri(dataUri, <String>[], null,
      paused: true,
      onExit: exitPort.sendPort,
      errorsAreFatal: false,
      checked: true,
      packageConfig: packages);
  List? error;
  var subscription = isolate.errors.listen((data) {
    error = data;
    exitPort.close();
  });
  await acknowledgeControlMessages(isolate, resume: isolate.pauseCapability);
  await for (var _ in exitPort) {
    exitPort.close();
  }
  await subscription.cancel();
  return error == null
      ? null
      : Future.error(error![0], StackTrace.fromString(error![1]));
}

class SuiteRunner {
  final List<Suite> suites;

  final Map<String, String> environment;

  final List<String> selectors;

  final Set<String> selectedSuites;

  final Set<String> skippedSuites;

  final List<Uri> testUris = <Uri>[];

  SuiteRunner(this.suites, this.environment, Iterable<String> selectors,
      this.selectedSuites, this.skippedSuites)
      : selectors = selectors.toList(growable: false);

  bool shouldRunSuite(Suite suite) {
    return !skippedSuites.contains(suite.name) &&
        (selectedSuites.isEmpty || selectedSuites.contains(suite.name));
  }

  Future<String?> generateDartProgram() async {
    testUris.clear();
    StringBuffer imports = StringBuffer();
    StringBuffer dart = StringBuffer();
    StringBuffer chain = StringBuffer();
    bool hasRunnableTests = false;

    await for (Chain suite in listChainSuites()) {
      hasRunnableTests = true;
      suite.writeImportOn(imports);
      suite.writeClosureOn(chain);
    }

    if (!hasRunnableTests) return null;

    return """
library testing.generated;

import 'dart:async' show Future;

import 'dart:convert' show json;

import 'package:testing/src/run_tests.dart' show runTests;

import 'package:testing/src/chain.dart' show runChain;

import 'package:testing/src/log.dart' show enableVerboseOutput, isVerbose;

${imports.toString().trim()}

Future<Null> main() async {
  if ($isVerbose) enableVerboseOutput();
  Map<String, String> environment =
      new Map<String, String>.from(json.decode('${json.encode(environment)}'));
  Set<String> selectors =
      new Set<String>.from(json.decode('${json.encode(selectors)}'));
  await runTests(<String, Function> {
      ${splitLines(dart.toString().trim()).join('      ')}
  });
  ${splitLines(chain.toString().trim()).join('  ')}
}
""";
  }

  Future<bool> analyze(Uri packages) async {
    bool hasAnalyzerSuites = false;
    for (Analyze suite in listAnalyzerSuites()) {
      if (shouldRunSuite(suite)) {
        hasAnalyzerSuites = true;
        await suite.run(packages, testUris);
      }
    }
    return hasAnalyzerSuites;
  }

  Stream<Chain> listChainSuites() async* {
    for (Chain suite in suites.whereType<Chain>()) {
      testUris.add((await Isolate.resolvePackageUri(suite.source))!);
      if (shouldRunSuite(suite)) {
        yield suite;
      }
    }
  }

  Iterable<Analyze> listAnalyzerSuites() {
    return suites.whereType<Analyze>();
  }
}
