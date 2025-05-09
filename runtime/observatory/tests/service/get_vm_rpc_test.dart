// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// VMOptions=--vm-name=Walter

import 'dart:io';

import 'package:test/test.dart';

import 'package:observatory/service_io.dart';
import 'test_helper.dart';

var tests = <VMTest>[
  (VM vm) async {
    var result = await vm.invokeRpcNoUpgrade('getVM', {});
    expect(result['type'], equals('VM'));
    expect(result['name'], equals('Walter'));
    expect(result['architectureBits'], isPositive);
    expect(result['targetCPU'], isA<String>());
    expect(result['hostCPU'], isA<String>());
    expect(result['operatingSystem'], Platform.operatingSystem);
    expect(result['version'], isA<String>());
    expect(result['pid'], isA<int>());
    expect(result['startTime'], isPositive);
    expect(result['isolates'].length, isPositive);
    expect(result['isolates'][0]['type'], equals('@Isolate'));
    expect(result['isolates'][0]['id'], startsWith('isolates/'));
    expect(
        result['isolates'][0]['isolateGroupId'], startsWith('isolateGroups/'));
    expect(result['isolateGroups'].length, isPositive);
    expect(result['isolateGroups'][0]['type'], equals('@IsolateGroup'));
    expect(result['isolateGroups'][0]['id'], startsWith('isolateGroups/'));
  },
];

main(args) async => runVMTests(args, tests);
