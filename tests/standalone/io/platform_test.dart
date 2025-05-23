// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import "dart:io";
import "dart:isolate";

import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

final executableSuffix = Platform.isWindows ? '.exe' : '';
final jitExecutableName = 'dart$executableSuffix';
final aotExecutableName = 'dartaotruntime$executableSuffix';

bool hasJitOrAotExecutableName(String executable) =>
    executable.endsWith(jitExecutableName) ||
    executable.endsWith(aotExecutableName);

bool isRunningFromSource() =>
    Platform.executable.endsWith(jitExecutableName) &&
    Platform.script.toFilePath().endsWith('.dart');

test() {
  Expect.isTrue(Platform.numberOfProcessors > 0);
  var os = Platform.operatingSystem;
  Expect.isTrue(
    os == "android" || os == "linux" || os == "macos" || os == "windows",
  );
  Expect.equals(Platform.isLinux, Platform.operatingSystem == "linux");
  Expect.equals(Platform.isMacOS, Platform.operatingSystem == "macos");
  Expect.equals(Platform.isWindows, Platform.operatingSystem == "windows");
  Expect.equals(Platform.isAndroid, Platform.operatingSystem == "android");
  if (Platform.isWindows) {
    Expect.equals("\r\n", Platform.lineTerminator, "windows lineTerminator");
    Expect.equals("\\", Platform.pathSeparator, "$os path-seperator");
  } else {
    Expect.equals("\n", Platform.lineTerminator, "$os lineTerminator");
    Expect.equals("/", Platform.pathSeparator, "$os path-seperator");
  }
  var hostname = Platform.localHostname;
  Expect.isTrue(hostname is String && hostname != "");
  var environment = Platform.environment;
  Expect.isTrue(environment is Map<String, String>);

  Expect.isTrue(hasJitOrAotExecutableName(Platform.executable));
  Expect.isTrue(hasJitOrAotExecutableName(Platform.resolvedExecutable));

  if (!Platform.isWindows) {
    Expect.isTrue(Platform.resolvedExecutable.startsWith('/'));
  } else {
    // This assumes that tests (both locally and on the bots) are
    // running off a location referred to by a drive letter. If a UNC
    // location is used or long names ("\\?\" prefix) is used this
    // needs to be fixed.
    Expect.equals(Platform.resolvedExecutable.substring(1, 3), ':\\');
  }
  // Move directory to be sure script is correct.
  var oldDir = Directory.current;
  Directory.current = Directory.current.parent;
  if (isRunningFromSource()) {
    Expect.isTrue(
      Platform.script.path.endsWith('tests/standalone/io/platform_test.dart'),
    );
    Expect.isTrue(Platform.script.toFilePath().startsWith(oldDir.path));
  }
}

void f(reply) {
  reply.send({
    "Platform.executable": Platform.executable,
    "Platform.script": Platform.script,
    "Platform.executableArguments": Platform.executableArguments,
  });
}

testIsolate() {
  asyncStart();
  ReceivePort port = new ReceivePort();
  Isolate.spawn(f, port.sendPort);
  port.first.then((results) {
    Expect.equals(Platform.executable, results["Platform.executable"]);

    Uri uri = results["Platform.script"];
    // SpawnFunction retains the script url of the parent which in this
    // case was a relative path.
    Expect.equals("file", uri.scheme);
    if (isRunningFromSource()) {
      Expect.isTrue(
        uri.path.endsWith('tests/standalone/io/platform_test.dart'),
      );
    }
    Expect.listEquals(
      Platform.executableArguments,
      results["Platform.executableArguments"],
    );
    asyncEnd();
  });
}

testVersion() {
  checkValidVersion(String version) {
    RegExp re = new RegExp(r'(\d+)\.(\d+)\.(\d+)(-dev\.([^\.]*)\.([^\.]*))?');
    var match = re.firstMatch(version);
    if (match == null) {
      throw new FormatException();
    }
    var major = int.parse(match.group(1)!);
    // Major version.
    Expect.isTrue(major == 1 || major == 2 || major == 3);
    // Minor version.
    Expect.isTrue(int.parse(match.group(2)!) >= 0);
    // Patch version.
    Expect.isTrue(int.parse(match.group(3)!) >= 0);
    // Dev
    if (match.group(4) != null) {
      // Dev prerelease minor version
      Expect.isTrue(int.parse(match.group(5)!) >= 0);
      // Dev prerelease patch version
      Expect.isTrue(int.parse(match.group(6)!) >= 0);
    }
  }

  checkInvalidVersion(String version) {
    try {
      checkValidVersion(version);
    } on FormatException {
      return;
    } on ExpectException {
      return;
    }
    Expect.testError("checkValidVersion accepts invalid version: $version");
  }

  String stripAdditionalInfo(String version) {
    var index = version.indexOf(' ');
    if (index == -1) return version;
    return version.substring(0, index);
  }

  // Sanity-checks for `checkValidVersion`.
  // Ensure we can match valid versions.
  checkValidVersion('1.9.0');
  checkValidVersion('2.0.0');
  checkValidVersion('3.0.0');
  checkValidVersion('1.9.0-dev.0.0');
  checkValidVersion('1.9.0-edge');
  checkValidVersion('1.9.0-edge.r41234');
  // Check stripping of additional information.
  checkValidVersion(
    stripAdditionalInfo(
      '1.9.0-dev.1.2 (Wed Feb 25 02:22:19 2015) on "linux_ia32"',
    ),
  );
  // Reject some invalid versions.
  checkInvalidVersion('1.9');
  checkInvalidVersion('..');
  checkInvalidVersion('1..');
  checkInvalidVersion('1.9.');
  checkInvalidVersion('1.9.0-dev..');
  checkInvalidVersion('1.9.0-dev..0');
  checkInvalidVersion('1.9.0-dev.0.');
  checkInvalidVersion('1.9.0-dev.x.y');
  checkInvalidVersion('x');
  checkInvalidVersion('x.y.z');

  // Test current version.
  checkValidVersion(stripAdditionalInfo(Platform.version));
}

main() {
  // This tests assumes paths relative to dart main directory
  Directory.current = Platform.script.resolve('../../..').toFilePath();
  test();
  testIsolate();
  testVersion();
}
