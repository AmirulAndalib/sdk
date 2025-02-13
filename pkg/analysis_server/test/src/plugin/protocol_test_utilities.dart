// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart' as server;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;

class ProtocolTestUtilities {
  static const List<String> strings = <String>[
    'aa',
    'ab',
    'ac',
    'ad',
    'ae',
    'af',
    'ag',
    'ah',
    'ai',
    'aj',
    'ak',
    'al',
    'am',
    'an',
    'ao',
    'ap',
    'aq',
    'ar',
    'as',
    'at',
    'au',
    'av',
    'aw',
    'ax',
    'ay',
    'az',
    'ba',
    'bb',
    'bc',
    'bd',
    'be',
    'bf',
    'bg',
    'bh',
    'bi',
    'bj',
    'bk',
    'bl',
    'bm',
    'bn',
    'bo',
    'bp',
    'bq',
    'br',
    'bs',
    'bt',
    'bu',
    'bv',
    'bw',
    'bx',
    'by',
    'bz',
  ];

  /// On return, increment [stringIndex] by 3 (or 4 if no [file] name is
  /// provided) and [intIndex] by 4.
  AnalysisError analysisError(int stringIndex, int intIndex, {String? file}) {
    return AnalysisError(
      AnalysisErrorSeverity.ERROR,
      AnalysisErrorType.COMPILE_TIME_ERROR,
      location(stringIndex, intIndex, file: file),
      strings[stringIndex++],
      strings[stringIndex++],
      correction: strings[stringIndex++],
      hasFix: true,
    );
  }

  /// On return, increment [stringIndex] by 5 and [intIndex] by 5.
  Element element(int stringIndex, int intIndex, {ElementKind? kind}) =>
      Element(
        kind ?? ElementKind.CLASS,
        strings[stringIndex++],
        intIndex++,
        location: Location(
          fileName(stringIndex++),
          intIndex++,
          intIndex++,
          intIndex++,
          intIndex++,
          endLine: intIndex++,
          endColumn: intIndex++,
        ),
        parameters: strings[stringIndex++],
        returnType: strings[stringIndex++],
        typeParameters: strings[stringIndex++],
      );

  String fileName(int stringIndex) => '${strings[stringIndex]}.dart';

  FoldingRegion foldingRegion(int offset, int length) =>
      FoldingRegion(FoldingKind.FILE_HEADER, offset, length);

  HighlightRegion highlightRegion(int offset, int length) =>
      HighlightRegion(HighlightRegionType.FIELD, offset, length);

  /// On return, increment [stringIndex] by 1 and [intIndex] by 4.
  Location location(int stringIndex, int intIndex, {String? file}) => Location(
    file ?? fileName(stringIndex),
    intIndex++,
    intIndex++,
    intIndex++,
    intIndex++,
    endLine: intIndex++,
    endColumn: intIndex++,
  );

  /// On return, increment [stringIndex] by 5 and [intIndex] by 7.
  Occurrences occurrences(int stringIndex, int intIndex) {
    var referencedElement = element(stringIndex, intIndex);
    return Occurrences(referencedElement, <int>[
      intIndex + 5,
      intIndex + 6,
    ], referencedElement.name.length);
  }

  /// On return, increment [stringIndex] by 10 and [intIndex] by 14.
  Outline outline(int stringIndex, int intIndex) => Outline(
    element(stringIndex, intIndex),
    intIndex + 5,
    intIndex + 6,
    intIndex + 5,
    intIndex + 6,
    children: <Outline>[
      Outline(
        element(stringIndex + 5, intIndex + 7, kind: ElementKind.METHOD),
        intIndex + 12,
        intIndex + 13,
        intIndex + 12,
        intIndex + 13,
      ),
    ],
  );

  /// On return, increment [stringIndex] by 2 (or 3 if no [file] name is
  /// provided) and [intIndex] by 4.
  plugin.AnalysisNavigationParams pluginNavigationParams(
    int stringIndex,
    int intIndex, {
    String? file,
  }) => plugin.AnalysisNavigationParams(
    file ?? fileName(stringIndex++),
    <NavigationRegion>[
      NavigationRegion(intIndex++, 2, <int>[0]),
    ],
    <NavigationTarget>[
      NavigationTarget(
        ElementKind.FIELD,
        0,
        intIndex++,
        2,
        intIndex++,
        intIndex++,
      ),
    ],
    <String>[strings[stringIndex++], strings[stringIndex++]],
  );

  /// On return, increment [stringIndex] by 2 and [intIndex] by 4.
  RefactoringProblem refactoringProblem(int stringIndex, int intIndex) {
    return RefactoringProblem(
      RefactoringProblemSeverity.FATAL,
      strings[stringIndex++],
      location: location(stringIndex, intIndex),
    );
  }

  /// On return, increment [stringIndex] by 2 (or 3 if no [file] name is
  /// provided) and [intIndex] by 4.
  server.AnalysisNavigationParams serverNavigationParams(
    int stringIndex,
    int intIndex, {
    String? file,
  }) => server.AnalysisNavigationParams(
    file ?? fileName(stringIndex++),
    <NavigationRegion>[
      NavigationRegion(intIndex++, 2, <int>[0]),
    ],
    <NavigationTarget>[
      NavigationTarget(
        ElementKind.FIELD,
        0,
        intIndex++,
        2,
        intIndex++,
        intIndex++,
      ),
    ],
    <String>[strings[stringIndex++], strings[stringIndex++]],
  );

  /// On return, increment [stringIndex] by 6 and [intIndex] by 6.
  SourceChange sourceChange(int stringIndex, int intIndex) => SourceChange(
    strings[stringIndex++],
    edits: <SourceFileEdit>[
      SourceFileEdit(
        fileName(stringIndex),
        intIndex++,
        edits: <SourceEdit>[
          SourceEdit(intIndex++, intIndex++, strings[stringIndex++]),
        ],
      ),
    ],
    linkedEditGroups: <LinkedEditGroup>[
      LinkedEditGroup(
        <Position>[Position(fileName(stringIndex), intIndex++)],
        intIndex++,
        <LinkedEditSuggestion>[
          LinkedEditSuggestion(
            strings[stringIndex++],
            LinkedEditSuggestionKind.METHOD,
          ),
        ],
      ),
    ],
    selection: Position(fileName(stringIndex), intIndex++),
  );
}
