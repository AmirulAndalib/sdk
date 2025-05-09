// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

// This script updates LINE_* constants in the given test.
void main(List<String> args) {
  if (args.length != 1 || !args[0].endsWith('.dart')) {
    print('Usage: ${Platform.executable} ${Platform.script} <test-file>');
    exit(1);
  }

  final inputFile = File(args[0]);

  final content = inputFile.readAsLinesSync();

  const autogeneratedStart = '// AUTOGENERATED START';
  const autogeneratedEnd = '// AUTOGENERATED END';

  final lineConstantPattern = RegExp(r'^const( int)? LINE_\w+ = \d+;$');

  final prefix = content
      .takeWhile((line) =>
          !lineConstantPattern.hasMatch(line) && autogeneratedStart != line)
      .toList();

  final suffix = content
      .skip(prefix.length)
      .skipWhile(
          (line) => line.startsWith('//') || lineConstantPattern.hasMatch(line))
      .toList();

  final lineCommentPattern =
      RegExp(r' // (LINE_\w+)\.?$|/\*\s*(LINE_\w+)\s*\*/');
  final mapping = <String, int>{};
  for (var i = 0; i < suffix.length; i++) {
    final line = suffix[i];
    final m = lineCommentPattern.firstMatch(line);
    if (m != null) {
      mapping[(m[1] ?? m[2])!] = i;
    }
  }

  final header = [
    ...prefix,
    autogeneratedStart,
    '//',
    '// Update these constants by running:',
    '//',
    '// dart runtime/observatory/tests/service/update_line_numbers.dart '
        '<test.dart>',
    '//',
  ];

  // Mapping currently contains 0 based indices into suffix.
  // Convert them into 1 based line numbers taking into account that we will
  // generate a header + one line for each LINE_* constant plus
  // autogeneratedEnd marker.
  mapping
      .updateAll((_, value) => 1 + header.length + mapping.length + 1 + value);

  inputFile.writeAsString([
    ...header,
    for (var entry in mapping.entries)
      'const int ${entry.key} = ${entry.value};',
    autogeneratedEnd,
    ...suffix,
    '',
  ].join('\n'));
  print('Updated ${inputFile}');
}
