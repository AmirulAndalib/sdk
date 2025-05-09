// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tool for visualizing the source mapped parts of a generated JS file.

import 'dart:convert';
import 'dart:io';
import 'package:source_maps/source_maps.dart';
import '../helpers/sourcemap_html_helper.dart';

main(List<String> args) {
  String jsFileName = 'out.js';
  if (args.length > 0) {
    jsFileName = args[0];
  }
  String jsMapFileName = '$jsFileName.map';
  if (args.length > 1) {
    jsMapFileName = args[1];
  }
  generateHtml(jsFileName, jsMapFileName);
}

enum MappingState {
  initial('initial', 0, 1),
  mapped0('mapped0', 2, 3),
  mapped0Continued('mapped0continued', 2, 3),
  mapped1('mapped1', 4, 1),
  mapped1Continued('mapped1continued', 4, 1),
  unmapped('unmapped', 5, 1);

  final String cssClass;
  final int _continuedState;
  final int _nextState;

  const MappingState(this.cssClass, this._continuedState, this._nextState);

  MappingState get continuedState => values[_continuedState];

  MappingState get nextState => values[_nextState];
}

void generateHtml(String jsFileName, String jsMapFileName) {
  String jsFile = File(jsFileName).readAsStringSync();
  String jsMapFile = File(jsMapFileName).readAsStringSync();
  SingleMapping mapping = SingleMapping.fromJson(json.decode(jsMapFile));
  StringBuffer output = StringBuffer();
  output.write('''
<html>
  <head>
    <title>${escape(jsFileName)} / ${escape(jsMapFileName)}</title>
    <style type="text/css">
      .initial{
        background-color: #FFFFFF;
      }
      .mapped0 {
        background-color: #E0E0C0;
      }
      .mapped0continued {
        background-color: #F8F8D8;
      }
      .mapped1 {
        background-color: #C0E0E0;
      }
      .mapped1continued {
        background-color: #D8F8F8;
      }
      .unmapped {
        background-color: #E0E0E0;
      }
      .code {
        font-family: monospace;
        white-space: pre;
        font-size: smaller;
      }
      .lineNumber {
        color: #C0C0C0;
        font-size: small;
      }
      .legend {
        position: fixed;
        top: 5px;
        right: 5px;
        border: 1px solid black;
        padding: 5px;
        background-color: #F0F0F0;
      }
      .box {
        border: 1px solid grey;
      }
    </style>
  </head>
  <body>
  <div class="legend">
    <span class="initial">&nbsp;&nbsp;&nbsp;&nbsp;</span> no mapping (yet)<br/>
    <span class="mapped0">&nbsp;&nbsp;</span>
      <span class="mapped1">&nbsp;&nbsp;</span> mapped<br/>
    <span class="mapped0continued">&nbsp;&nbsp;</span>
      <span class="mapped1continued">&nbsp;&nbsp;</span> mapping
        continued from previous line<br/>
    <span class="unmapped">&nbsp;&nbsp;&nbsp;&nbsp;</span> mapping off<br/>
  </div>
  <pre class="code">
''');

  MappingState state = MappingState.initial;
  TargetEntry? lastEntry;

  void write(String text, TargetEntry? entry) {
    output.write('<span class="${state.cssClass}"');
    String prefix = '';
    if (entry == lastEntry) {
      prefix = 'continued: ';
    }
    final currentEntry = lastEntry = entry;
    if (currentEntry != null) {
      if (currentEntry.sourceUrlId != null) {
        output.write(' title="$prefix');
        output.write(escape(mapping.urls[currentEntry.sourceUrlId!]));
        output.write(
          ':${currentEntry.sourceLine! + 1}:${currentEntry.sourceColumn! + 1}',
        );
        if (currentEntry.sourceNameId != null) {
          output.write(' (');
          output.write(escape(mapping.names[currentEntry.sourceNameId!]));
          output.write(')');
        }
        output.write('"');
      } else {
        output.write(' title="unmapped"');
      }
    }
    output.write('>');
    output.write(escape(text));
    output.write('</span>');
  }

  int nextTargetLineIndex = 0;
  List<String> lines = jsFile.split('\n');
  int lineNoWidth = '${lines.length}'.length;
  for (int lineNo = 0; lineNo < lines.length; lineNo++) {
    output.write(lineNumber(lineNo, width: lineNoWidth));
    String line = lines[lineNo];
    TargetLineEntry? targetLineEntry;
    while (nextTargetLineIndex < mapping.lines.length) {
      TargetLineEntry entry = mapping.lines[nextTargetLineIndex];
      if (entry.line == lineNo) {
        targetLineEntry = entry;
        nextTargetLineIndex++;
        break;
      } else if (entry.line > lineNo) {
        break;
      } else {
        nextTargetLineIndex++;
      }
    }
    if (targetLineEntry != null) {
      int columnNo = 0;
      for (int index = 0; index < targetLineEntry.entries.length; index++) {
        TargetEntry entry = targetLineEntry.entries[index];
        if (entry.column > columnNo) {
          write(line.substring(columnNo, entry.column), lastEntry);
          columnNo = entry.column;
        }
        state = entry.sourceUrlId != null
            ? state.nextState
            : MappingState.unmapped;
        int end;
        if (index + 1 < targetLineEntry.entries.length) {
          end = targetLineEntry.entries[index + 1].column;
        } else {
          end = line.length;
        }
        write(line.substring(entry.column, end), entry);
        columnNo = end;
      }
    } else {
      write(line, lastEntry);
    }
    output.write('\n');
    state = state.continuedState;
  }
  output.write('</pre></body></html>');
  File outputFile = File('out.js.map.html');
  outputFile.writeAsStringSync(output.toString());
  print('Output written to: ${outputFile.absolute.uri}');
}
