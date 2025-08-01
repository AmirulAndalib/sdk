// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This test verifies that all files generated by `generate.dart` are up to
// date.

import 'package:analyzer_testing/package_root.dart' as pkg_root;
import 'package:analyzer_utilities/generated_content_check.dart';
import 'package:path/path.dart';

import 'generate.dart';

Future<void> main() async {
  await allTargets.check(
    pkg_root.packageRoot,
    join(analyzerPkgPath, 'tool', 'wolf', 'generate.dart'),
  );
}
