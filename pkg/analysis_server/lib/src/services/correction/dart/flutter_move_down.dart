// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/src/utilities/extensions/flutter.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class FlutterMoveDown extends ResolvedCorrectionProducer {
  FlutterMoveDown({required super.context});

  @override
  CorrectionApplicability get applicability =>
      // TODO(applicability): comment on why.
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => DartAssistKind.flutterMoveDown;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    var widget = node.findWidgetExpression;
    if (widget == null) {
      return;
    }

    var parentList = widget.parent;
    if (parentList is ListLiteral) {
      List<CollectionElement> parentElements = parentList.elements;
      var index = parentElements.indexOf(widget);
      if (index != parentElements.length - 1) {
        await builder.addDartFileEdit(file, (fileBuilder) {
          var nextWidget = parentElements[index + 1];
          var nextRange = range.node(nextWidget);
          var nextText = utils.getRangeText(nextRange);

          var widgetRange = range.node(widget);
          var widgetText = utils.getRangeText(widgetRange);

          fileBuilder.addSimpleReplacement(nextRange, widgetText);
          fileBuilder.addSimpleReplacement(widgetRange, nextText);

          var lengthDelta = nextRange.length - widgetRange.length;
          var newWidgetOffset = nextRange.offset + lengthDelta;
          builder.setSelection(Position(file, newWidgetOffset));
        });
      }
    }
  }
}
