// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

main() {
  asyncStart();
  var executable = new File(Platform.executable).resolveSymbolicLinksSync();
  var tempDir = Directory.systemTemp.createTempSync('dart_process_non_ascii');
  var nonAsciiDir = new Directory('${tempDir.path}/æøå');
  nonAsciiDir.createSync();
  var nonAsciiFile = new File('${nonAsciiDir.path}/æøå.dart');
  nonAsciiFile.writeAsStringSync("""
import 'dart:io';

main() {
  if ('æøå' != new File('æøå.txt').readAsStringSync()) {
    throw new StateError("not equal");
  }
}
""");
  var nonAsciiTxtFile = new File('${nonAsciiDir.path}/æøå.txt');
  nonAsciiTxtFile.writeAsStringSync('æøå');
  var script = nonAsciiFile.path;
  // Note: we prevent this child process from using Crashpad handler because
  // this introduces an issue with deleting the temporary directory.
  Process.run(
    executable,
    []
      ..addAll(Platform.executableArguments)
      ..add(script),
    workingDirectory: nonAsciiDir.path,
    environment: {'DART_CRASHPAD_HANDLER': ''},
  ).then((result) {
    if (result.exitCode != 0) {
      print('exitCode:\n${result.exitCode}');
      print('stdout:\n${result.stdout}');
      print('stderr:\n${result.stderr}');
    }
    Expect.equals(0, result.exitCode);
    tempDir.deleteSync(recursive: true);
    asyncEnd();
  });
}
