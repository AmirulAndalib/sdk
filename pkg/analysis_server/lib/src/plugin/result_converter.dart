// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart' as server;
import 'package:analysis_server/src/protocol/protocol_internal.dart' as server;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;

/// An object used to convert between similar objects defined by both the plugin
/// protocol and the server protocol.
class ResultConverter {
  /// The decoder used to decode Json representations of server objects.
  static final server.ResponseDecoder decoder = server.ResponseDecoder(null);

  server.AnalysisErrorFixes convertAnalysisErrorFixes(
    plugin.AnalysisErrorFixes fixes,
  ) {
    var changes =
        fixes.fixes
            .map(
              (plugin.PrioritizedSourceChange change) =>
                  convertPrioritizedSourceChange(change),
            )
            .toList();
    return server.AnalysisErrorFixes(fixes.error, fixes: changes);
  }

  server.AnalysisNavigationParams convertAnalysisNavigationParams(
    plugin.AnalysisNavigationParams params,
  ) {
    return server.AnalysisNavigationParams.fromJson(
      decoder,
      '',
      params.toJson(),
      // Converter not needed because the plugin class toJson'd above is always
      // file paths.
      clientUriConverter: null,
    );
  }

  server.EditGetRefactoringResult convertEditGetRefactoringResult(
    RefactoringKind kind,
    plugin.EditGetRefactoringResult result,
  ) {
    return server.EditGetRefactoringResult.fromJson(
      server.ResponseDecoder(kind),
      '',
      result.toJson(),
      // Converter not needed because the plugin class toJson'd above is always
      // file paths.
      clientUriConverter: null,
    );
  }

  SourceChange convertPrioritizedSourceChange(
    plugin.PrioritizedSourceChange change,
  ) {
    return change.change;
  }
}
