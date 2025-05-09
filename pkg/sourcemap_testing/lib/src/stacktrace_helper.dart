// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:_fe_analyzer_shared/src/testing/annotated_code_helper.dart';
import 'package:dart2js_tools/src/dart2js_mapping.dart';
import 'package:dart2js_tools/src/util.dart';
import 'package:expect/expect.dart';
import 'package:source_maps/source_maps.dart';
import 'package:source_maps/src/utils.dart';
import 'package:source_span/source_span.dart';

const String inputFileName = 'input.dart';

class Test {
  final String code;
  final Map<String, Expectations> expectationMap;

  Test(this.code, this.expectationMap);
}

class Expectations {
  final List<StackTraceLine> expectedLines;
  final List<StackTraceLine> unexpectedLines;

  Expectations(this.expectedLines, this.unexpectedLines);
}

/// Convert the annotated [code] to a [Test] object using [configs] to split
/// the annotations by prefix.
Test processTestCode(String code, Iterable<String> configs) {
  AnnotatedCode annotatedCode = AnnotatedCode.fromText(
    code,
    commentStart,
    commentEnd,
  );

  Map<String, Expectations> expectationMap = <String, Expectations>{};

  splitByPrefixes(annotatedCode, configs).forEach((
    String config,
    AnnotatedCode annotatedCode,
  ) {
    Map<int, StackTraceLine> stackTraceMap = <int, StackTraceLine>{};
    List<StackTraceLine> unexpectedLines = <StackTraceLine>[];

    for (Annotation annotation in annotatedCode.annotations) {
      String text = annotation.text;
      int colonIndex = text.indexOf(':');
      String indexText;
      String? methodName;
      if (colonIndex >= 0) {
        indexText = text.substring(0, colonIndex);
        methodName = text.substring(colonIndex + 1);
      } else {
        indexText = text;
      }
      StackTraceLine stackTraceLine = StackTraceLine(
        methodName,
        inputFileName,
        annotation.lineNo,
        annotation.columnNo,
      );
      if (indexText == '') {
        unexpectedLines.add(stackTraceLine);
      } else {
        int stackTraceIndex = int.parse(indexText);
        assert(!stackTraceMap.containsKey(stackTraceIndex));
        stackTraceMap[stackTraceIndex] = stackTraceLine;
      }
    }

    List<StackTraceLine> expectedLines = [];
    for (int stackTraceIndex
        in (stackTraceMap.keys.toList()..sort()).reversed) {
      expectedLines.add(stackTraceMap[stackTraceIndex]!);
    }
    expectationMap[config] = Expectations(expectedLines, unexpectedLines);
  });

  return Test(annotatedCode.sourceCode, expectationMap);
}

/// Compile function used in [testStackTrace]. [input] is the name of the input
/// Dart file and [output] is the name of the generated JavaScript file. The
/// function returns `true` if the compilation succeeded.
typedef CompileFunc = Future<bool> Function(String, String);

List<String> emptyPreamble(String input, String output) => const <String>[];
String? identityConverter(String? name) => name;

/// Tests the stack trace of [test] using the expectations for [config].
///
/// The [compile] function is called to compile the Dart code in [test] to
/// JavaScript.
///
/// The [jsPreambles] contains the path of additional JavaScript files needed
/// to run the generated JavaScript file.
///
/// The [beforeExceptions] lines are allowed before the intended stack trace.
/// The [afterExceptions] lines are allowed after the intended stack trace.
///
/// If [printJs] is `true`, the generated JavaScript code is print to the
/// console. If [writeJs] is `true` the generated JavaScript code and the
/// generated source map are saved in the current working directory (as 'out.js'
/// and 'out.js.map', respectively).
///
/// If forcedTmpDir is given that directory is used as the out directory and
/// will not be cleaned up. Note that if *not* giving a temporary directory and
/// the test fails the directory will not be cleaned up.
Future testStackTrace(
  Test test,
  String config,
  CompileFunc compile, {
  bool printJs = false,
  bool writeJs = false,
  bool verbose = false,
  List<String> Function(String input, String output) jsPreambles =
      emptyPreamble,
  List<LineException> beforeExceptions = const <LineException>[],
  List<LineException> afterExceptions = const <LineException>[],
  bool useJsMethodNamesOnAbsence = false,
  String? Function(String? name) jsNameConverter = identityConverter,
  Directory? forcedTmpDir,
  int stackTraceLimit = 10,
  expandDart2jsInliningData = false,
}) async {
  Expect.isTrue(
    test.expectationMap.keys.contains(config),
    "No expectations found for '$config' in ${test.expectationMap.keys}",
  );

  Directory tmpDir =
      forcedTmpDir ?? await Directory.systemTemp.createTemp('stacktrace-test');
  String input = '${tmpDir.path}/$inputFileName';
  File(input).writeAsStringSync(test.code);
  String output = '${tmpDir.path}/out.js';

  Expect.isTrue(
    await compile(input, output),
    'Unsuccessful compilation of test:\n${test.code}',
  );
  File sourceMapFile = File('$output.map');
  Expect.isTrue(
    sourceMapFile.existsSync(),
    'Source map not generated for $input',
  );
  String sourceMapText = sourceMapFile.readAsStringSync();
  SingleMapping sourceMap = parseSingleMapping(jsonDecode(sourceMapText));
  String jsOutput = File(output).readAsStringSync();

  if (printJs) {
    print('JavaScript output:');
    print(jsOutput);
  }
  if (writeJs) {
    File('out.js').writeAsStringSync(jsOutput);
    File('out.js.map').writeAsStringSync(sourceMapText);
  }
  print('Running d8 $output');
  List<String> d8Arguments = <String>[];
  d8Arguments.add('--stack-trace-limit');
  d8Arguments.add('$stackTraceLimit');
  d8Arguments.addAll(jsPreambles(input, output));
  d8Arguments.add(output);
  ProcessResult runResult = Process.runSync(d8executable, d8Arguments);
  String out = '${runResult.stderr}\n${runResult.stdout}';
  if (verbose) {
    print('d8 output:');
    print(out);
  }
  List<String> lines = out.split(RegExp(r'(\r|\n|\r\n)'));
  List<StackTraceLine> jsStackTrace = <StackTraceLine>[];
  for (String line in lines) {
    if (line.startsWith('    at ')) {
      StackTraceLine stackTraceLine = StackTraceLine.fromText(line);
      if (stackTraceLine.lineNo != null && stackTraceLine.columnNo != null) {
        jsStackTrace.add(stackTraceLine);
      }
    }
  }

  List<StackTraceLine> dartStackTrace = <StackTraceLine>[];
  for (StackTraceLine line in jsStackTrace) {
    TargetEntry? targetEntry = _findColumn(
      line.lineNo! - 1,
      line.columnNo! - 1,
      _findLine(sourceMap, line),
    );
    if (targetEntry == null || targetEntry.sourceUrlId == null) {
      dartStackTrace.add(line);
    } else {
      String fileName = sourceMap.urls[targetEntry.sourceUrlId!];
      int targetLine = targetEntry.sourceLine! + 1;
      int targetColumn = targetEntry.sourceColumn! + 1;

      if (expandDart2jsInliningData) {
        SourceFile file = SourceFile.fromString(jsOutput);
        int offset = file.getOffset(line.lineNo! - 1, line.columnNo! - 1);
        Map<int, List<FrameEntry>> frames = _loadInlinedFrameData(
          sourceMap,
          sourceMapText,
        );
        List<int> indices = frames.keys.toList()..sort();
        int key = binarySearch<int>(indices, (i) => i > offset) - 1;
        int depth = 0;
        outer:
        while (key >= 0) {
          for (var frame in frames[indices[key]]!.reversed) {
            if (frame.isEmpty) break outer;
            if (frame.isPush) {
              if (depth <= 0) {
                dartStackTrace.add(
                  StackTraceLine(
                    '${frame.inlinedMethodName}(inlined)',
                    fileName,
                    targetLine,
                    targetColumn,
                    isMapped: true,
                  ),
                );
                fileName = frame.callUri!;
                targetLine = frame.callLine! + 1;
                targetColumn = frame.callColumn! + 1;
              } else {
                depth--;
              }
            }
            if (frame.isPop) {
              depth++;
            }
          }
          key--;
        }
        targetEntry = findEnclosingFunction(jsOutput, file, offset, sourceMap);
      }

      String? methodName;
      if (targetEntry!.sourceNameId != null) {
        methodName = sourceMap.names[targetEntry.sourceNameId!];
      } else if (useJsMethodNamesOnAbsence) {
        methodName = jsNameConverter(line.methodName);
      }

      dartStackTrace.add(
        StackTraceLine(
          methodName,
          fileName,
          targetLine,
          targetColumn,
          isMapped: true,
        ),
      );
    }
  }

  Expectations expectations = test.expectationMap[config]!;

  int expectedIndex = 0;
  List<StackTraceLine> unexpectedLines = <StackTraceLine>[];
  List<StackTraceLine> unexpectedBeforeLines = <StackTraceLine>[];
  List<StackTraceLine> unexpectedAfterLines = <StackTraceLine>[];
  for (StackTraceLine line in dartStackTrace) {
    bool found = false;
    if (expectedIndex < expectations.expectedLines.length) {
      StackTraceLine expectedLine = expectations.expectedLines[expectedIndex];
      if (line.methodName == expectedLine.methodName &&
          line.lineNo == expectedLine.lineNo &&
          line.columnNo == expectedLine.columnNo) {
        found = true;
        expectedIndex++;
      }
    }
    for (StackTraceLine unexpectedLine in expectations.unexpectedLines) {
      if (line.methodName == unexpectedLine.methodName &&
          line.lineNo == unexpectedLine.lineNo &&
          line.columnNo == unexpectedLine.columnNo) {
        unexpectedLines.add(line);
      }
    }
    if (line.isMapped && !found) {
      List<LineException> exceptions = expectedIndex == 0
          ? beforeExceptions
          : afterExceptions;
      for (LineException exception in exceptions) {
        String fileName = exception.fileName;
        if (line.methodName == exception.methodName &&
            line.fileName!.endsWith(fileName)) {
          found = true;
        }
      }
      if (!found) {
        if (expectedIndex == 0) {
          unexpectedBeforeLines.add(line);
        } else {
          unexpectedAfterLines.add(line);
        }
      }
    }
  }
  if (verbose) {
    print('JavaScript stacktrace:');
    print(jsStackTrace.join('\n'));
    print('\nDart stacktrace:');
    print(dartStackTrace.join('\n'));
  }
  Expect.equals(
    expectedIndex,
    expectations.expectedLines.length,
    'Missing stack trace lines for test:\n${test.code}\n'
    'Actual:\n${dartStackTrace.join('\n')}\n\n'
    'Expected:\n${expectations.expectedLines.join('\n')}\n',
  );
  Expect.isTrue(
    unexpectedLines.isEmpty,
    'Unexpected stack trace lines for test:\n${test.code}\n'
    'Actual:\n${dartStackTrace.join('\n')}\n\n'
    'Unexpected:\n${expectations.unexpectedLines.join('\n')}\n',
  );
  Expect.isTrue(
    unexpectedBeforeLines.isEmpty && unexpectedAfterLines.isEmpty,
    'Unexpected stack trace lines:\n${test.code}\n'
    'Actual:\n${dartStackTrace.join('\n')}\n\n'
    'Unexpected before:\n${unexpectedBeforeLines.join('\n')}\n\n'
    'Unexpected after:\n${unexpectedAfterLines.join('\n')}\n',
  );

  if (forcedTmpDir == null) {
    print("Deleting '${tmpDir.path}'.");
    tmpDir.deleteSync(recursive: true);
  }
}

class StackTraceLine {
  String? methodName;
  String? fileName;
  int? lineNo;
  int? columnNo;
  bool isMapped;

  StackTraceLine(
    this.methodName,
    this.fileName,
    this.lineNo,
    this.columnNo, {
    this.isMapped = false,
  });

  /// Creates a [StackTraceLine] by parsing a d8 stack trace line [text]. The
  /// expected formats are
  ///
  ///     at <methodName>(<fileName>:<lineNo>:<columnNo>)
  ///     at <methodName>(<fileName>:<lineNo>)
  ///     at <methodName>(<fileName>)
  ///     at <fileName>:<lineNo>:<columnNo>
  ///     at <fileName>:<lineNo>
  ///     at <fileName>
  ///
  factory StackTraceLine.fromText(String text) {
    text = text.trim();
    assert(text.startsWith('at '));
    text = text.substring('at '.length);
    String? methodName;
    if (text.endsWith(')')) {
      int nameEnd = text.indexOf(' (');
      methodName = text.substring(0, nameEnd);
      text = text.substring(nameEnd + 2, text.length - 1);
    }
    int? lineNo;
    int? columnNo;
    String fileName;
    int lastColon = text.lastIndexOf(':');
    if (lastColon != -1) {
      int? lastValue = int.tryParse(text.substring(lastColon + 1));
      if (lastValue != null) {
        int secondToLastColon = text.lastIndexOf(':', lastColon - 1);
        if (secondToLastColon != -1) {
          int? secondToLastValue = int.tryParse(
            text.substring(secondToLastColon + 1, lastColon),
          );
          if (secondToLastValue != null) {
            lineNo = secondToLastValue;
            columnNo = lastValue;
            fileName = text.substring(0, secondToLastColon);
          } else {
            lineNo = lastValue;
            fileName = text.substring(0, lastColon);
          }
        } else {
          lineNo = lastValue;
          fileName = text.substring(0, lastColon);
        }
      } else {
        fileName = text;
      }
    } else {
      fileName = text;
    }
    return StackTraceLine(methodName, fileName, lineNo, columnNo);
  }

  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    sb.write('  at ');
    if (methodName != null) {
      sb.write(methodName);
      sb.write(' (');
      sb.write(fileName ?? '?');
      sb.write(':');
      sb.write(lineNo);
      sb.write(':');
      sb.write(columnNo);
      sb.write(')');
    } else {
      sb.write(fileName ?? '?');
      sb.write(':');
      sb.write(lineNo);
      sb.write(':');
      sb.write(columnNo);
    }
    return sb.toString();
  }
}

/// Returns [TargetLineEntry] which includes the location in the target [line]
/// number. In particular, the resulting entry is the last entry whose line
/// number is lower or equal to [line].
///
/// Copied from [SingleMapping._findLine].
TargetLineEntry? _findLine(SingleMapping sourceMap, StackTraceLine stLine) {
  String filename = stLine.fileName!.substring(
    stLine.fileName!.lastIndexOf(RegExp('[\\/]')) + 1,
  );
  if (sourceMap.targetUrl != filename) return null;
  return _findLineInternal(sourceMap, stLine.lineNo! - 1);
}

TargetLineEntry? _findLineInternal(SingleMapping sourceMap, int line) {
  int index = binarySearch<TargetLineEntry>(
    sourceMap.lines,
    (e) => e.line > line,
  );
  return (index <= 0) ? null : sourceMap.lines[index - 1];
}

/// Returns [TargetEntry] which includes the location denoted by
/// [line], [column]. If [lineEntry] corresponds to [line], then this will be
/// the last entry whose column is lower or equal than [column]. If
/// [lineEntry] corresponds to a line prior to [line], then the result will be
/// the very last entry on that line.
///
/// Copied from [SingleMapping._findColumn].
TargetEntry? _findColumn(int line, int column, TargetLineEntry? lineEntry) {
  if (lineEntry == null || lineEntry.entries.isEmpty) return null;
  if (lineEntry.line != line) return lineEntry.entries.last;
  var entries = lineEntry.entries;
  int index = binarySearch<TargetEntry>(entries, (e) => e.column > column);
  return (index <= 0) ? null : entries[index - 1];
}

/// Returns the path of the d8 executable.
String get d8executable {
  final arch = Abi.current().toString().split('_')[1];
  if (Platform.isWindows) {
    return 'third_party/d8/windows/$arch/d8.exe';
  } else if (Platform.isLinux) {
    return 'third_party/d8/linux/$arch/d8';
  } else if (Platform.isMacOS) {
    return 'third_party/d8/macos/$arch/d8';
  }
  throw UnsupportedError('Unsupported platform.');
}

/// A line allowed in the mapped stack trace.
class LineException {
  final String methodName;
  final String fileName;

  const LineException(this.methodName, this.fileName);
}

/// Search backwards in [sources] for a function declaration that includes the
/// [start] offset.
TargetEntry? findEnclosingFunction(
  String sources,
  SourceFile file,
  int start,
  SingleMapping mapping,
) {
  var index = start;
  while (true) {
    index = nextDeclarationCandidate(sources, index);
    if (index < 0) return null;
    var line = file.getLine(index);
    var lineEntry = _findLineInternal(mapping, line);
    var result = _findColumn(line, file.getColumn(index), lineEntry);
    if (result?.column == file.getColumn(index)) return result;
    index--;
  }
}

/// Returns the index of a candidate location of a enclosing function
/// declaration. We try to find the beginning of a `function` keyword or the
/// `(` of an ES6 method definition, but the search contains some false
/// positives. To rule out false positives, [findEnclosingFunction]
/// validates that the returned location contains a source-map entry, searching
/// for another candidate if not.
int nextDeclarationCandidate(String sources, int start) {
  var indexForFunctionKeyword = sources.lastIndexOf('function', start);
  // We attempt to identify potential method definitions by looking for any '('
  // that precedes a '{'. This method will fail if 1) Dart2JS starts emitting
  // functions with initializers or 2) sourcemap boundaries appear at '(' for
  // non-method-definition constructs.
  var indexForMethodDefinition = sources.lastIndexOf('{', start);
  if (indexForFunctionKeyword > indexForMethodDefinition ||
      indexForFunctionKeyword < 0) {
    return indexForFunctionKeyword;
  }
  indexForMethodDefinition = sources.lastIndexOf('(', indexForMethodDefinition);
  return indexForFunctionKeyword > indexForMethodDefinition
      ? indexForFunctionKeyword
      : indexForMethodDefinition;
}

Map<int, List<FrameEntry>> _loadInlinedFrameData(
  SingleMapping mapping,
  String sourceMapText,
) {
  var json = jsonDecode(sourceMapText);
  return Dart2jsMapping(mapping, json).frames;
}
