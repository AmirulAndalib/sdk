// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dartdev/src/sdk.dart';
import 'package:test/test.dart';

void main() {
  group('Sdk', _sdk);
  group('Runtime', _runtime);
}

void _sdk() {
  test('sdkPath', () {
    expectDirectoryExists(Sdk().sdkPath);
  });

  test('dart binary', () {
    expectFileExists(Sdk().dart);
  });

  test('analysis_server snapshot', () {
    expectFileExists(Sdk().analysisServerSnapshot);
  });

  test('dds snapshot', () {
    expectSnapshotExists(Sdk().ddsAotSnapshot, Sdk().ddsSnapshot);
  });

  test('dart2js snapshot', () {
    expectSnapshotExists(Sdk().dart2jsAotSnapshot, Sdk().dart2jsSnapshot);
  });
}

void _runtime() {
  test('channel', () {
    final runtime = Runtime.runtime;
    expect(runtime.channel, isNotEmpty);
  });
}

void expectFileExists(String path) {
  expect(File(path).existsSync(), isTrue);
}

void expectSnapshotExists(String aotpath, String jitpath) {
  expect(File(aotpath).existsSync() || File(jitpath).existsSync(), isTrue);
}

void expectDirectoryExists(String path) {
  expect(Directory(path).existsSync(), isTrue);
}
