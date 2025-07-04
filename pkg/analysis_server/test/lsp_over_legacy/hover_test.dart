// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/lsp_protocol/protocol.dart';
import 'package:analyzer/src/test_utilities/test_code_format.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../utils/test_code_extensions.dart';
import 'abstract_lsp_over_legacy.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(HoverTest);
  });
}

@reflectiveTest
class HoverTest extends LspOverLegacyTest {
  Future<void> expectHover(String content, String expected) async {
    var code = TestCode.parse(content);
    newFile(testFilePath, code.code);
    await waitForTasksFinished();

    var result = await getHover(testFileUri, code.position.position);
    var markup = _getMarkupContents(result!);
    expect(markup.kind, MarkupKind.Markdown);
    expect(markup.value.trimRight(), expected.trimRight());
    expect(result.range, code.range.range);
  }

  Future<void> test_class_constructor_named() async {
    await expectHover(
      r'''
/// This is my class.
class [!A^aa!] {}
''',
      r'''
```dart
class Aaa
```
Declared in _package:test/test.dart_.

---
This is my class.
''',
    );
  }

  Future<void> test_loggedMethodName() async {
    newFile(testFilePath, 'String s;');
    await waitForTasksFinished();
    await getHover(testFileUri, Position(character: 1, line: 0));

    expect(
      numberOfRecordedResponses(Method.textDocument_hover.toString()),
      isPositive,
    );
    expect(numberOfRecordedResponses('lsp.handle'), isZero);
  }

  MarkupContent _getMarkupContents(Hover hover) {
    return hover.contents.map(
      (t1) => t1,
      (t2) => throw 'Hover contents were String, not MarkupContent',
    );
  }
}
