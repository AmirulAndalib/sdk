// Copyright 2017 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

mixin Diagnosticable {
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}
}

abstract class DiagnosticableTree with Diagnosticable {
  const DiagnosticableTree();

  List<DiagnosticsNode> debugDescribeChildren() => const [];
}

class DiagnosticPropertiesBuilder {
  void add(DiagnosticsNode property) {}
}

abstract class DiagnosticsNode {}

class DiagnosticsProperty<T> extends DiagnosticsNode {
  DiagnosticsProperty(String name, T value);
}
