// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FlutterConvertToChildrenTest);
  });
}

@reflectiveTest
class FlutterConvertToChildrenTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.flutterConvertToChildren;

  @override
  void setUp() {
    super.setUp();
    writeTestPackageConfig(flutter: true);
  }

  Future<void> test_childUnresolved() async {
    verifyNoTestUnitErrors = false;
    await resolveTestCode('''
import 'package:flutter/material.dart';
build() {
  return Row(
    ^child: Container()
  );
}
''');
    await assertNoAssist();
  }

  Future<void> test_multiLine() async {
    await resolveTestCode('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: Center(
      ^child: Container(
        width: 200.0,
        height: 300.0,
      ),
      key: Key('x'),
    ),
  );
}
''');
    await assertHasAssist('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: Center(
      children: [
        Container(
          width: 200.0,
          height: 300.0,
        ),
      ],
      key: Key('x'),
    ),
  );
}
''');
  }

  Future<void> test_newlineChild() async {
    // This case could occur with deeply nested constructors, common in Flutter.

    await resolveTestCode('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: Center(
      ^child:
          Container(
        width: 200.0,
        height: 300.0,
      ),
      key: Key('x'),
    ),
  );
}
''');
    await assertHasAssist('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: Center(
      children: [
        Container(
          width: 200.0,
          height: 300.0,
        ),
      ],
      key: Key('x'),
    ),
  );
}
''');
  }

  Future<void> test_notOnChild() async {
    await resolveTestCode('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: ^Center(
      child: Container(),
    ),
  );
}
''');
    await assertNoAssist();
  }

  Future<void> test_singleLine() async {
    await resolveTestCode('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: Center(
      ^child: GestureDetector(),
      key: Key('x'),
    ),
  );
}
''');
    await assertHasAssist('''
import 'package:flutter/material.dart';
build() {
  return Scaffold(
    body: Center(
      children: [GestureDetector()],
      key: Key('x'),
    ),
  );
}
''');
  }
}
