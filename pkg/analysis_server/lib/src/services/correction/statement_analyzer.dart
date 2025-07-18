// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/protocol_server.dart';
import 'package:analysis_server/src/services/correction/selection_analyzer.dart';
import 'package:analysis_server/src/services/correction/status.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server/src/utilities/extensions/iterable.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/src/dart/scanner/reader.dart';
import 'package:analyzer/src/dart/scanner/scanner.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Returns [Token]s of the given Dart source, not `null`, may be empty if no
/// tokens or some exception happens.
List<Token> _getTokens(String text, FeatureSet featureSet) {
  try {
    var tokens = <Token>[];
    var scanner = Scanner(
      _SourceMock.instance,
      CharSequenceReader(text),
      DiagnosticListener.nullListener,
    )..configureFeatures(
      featureSetForOverriding: featureSet,
      featureSet: featureSet,
    );
    var token = scanner.tokenize();
    while (!token.isEof) {
      tokens.add(token);
      token = token.next!;
    }
    return tokens;
  } catch (e) {
    return const <Token>[];
  }
}

/// Analyzer to check if a selection covers a valid set of statements of AST.
class StatementAnalyzer extends SelectionAnalyzer {
  final ResolvedUnitResult resolveResult;

  final RefactoringStatus _status = RefactoringStatus();

  StatementAnalyzer(this.resolveResult, SourceRange selection)
    : super(selection);

  /// Returns the [RefactoringStatus] result of selection checking.
  RefactoringStatus get status => _status;

  /// Analyze the selection, compute [status] and nodes.
  void analyze() {
    resolveResult.unit.accept(this);
  }

  /// Records fatal error with given message and [Location].
  void invalidSelection(String message, [Location? context]) {
    if (!_status.hasFatalError) {
      _status.addFatalError(message, context);
    }
    reset();
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    super.visitCompilationUnit(node);
    if (!hasSelectedNodes) {
      return;
    }
    // check that selection does not begin/end in comment
    {
      var selectionStart = selection.offset;
      var selectionEnd = selection.end;
      var commentRanges = getCommentRanges(resolveResult.unit);
      for (var commentRange in commentRanges) {
        if (commentRange.contains(selectionStart)) {
          invalidSelection('Selection begins inside a comment.');
        }
        if (commentRange.containsExclusive(selectionEnd)) {
          invalidSelection('Selection ends inside a comment.');
        }
      }
    }
    // more checks
    if (!_status.hasFatalError) {
      _checkSelectedNodes(node);
    }
  }

  @override
  void visitDoStatement(DoStatement node) {
    super.visitDoStatement(node);
    if (selectedNodes.contains(node.body)) {
      invalidSelection(
        "Operation not applicable to a 'do' statement's body and expression.",
      );
    }
  }

  @override
  void visitForStatement(ForStatement node) {
    super.visitForStatement(node);
    var forLoopParts = node.forLoopParts;
    if (forLoopParts is ForParts) {
      var selectedNodes = this.selectedNodes;
      bool containsInit;
      if (forLoopParts is ForPartsWithExpression) {
        containsInit = selectedNodes.contains(forLoopParts.initialization);
      } else if (forLoopParts is ForPartsWithDeclarations) {
        containsInit = selectedNodes.contains(forLoopParts.variables);
      } else if (forLoopParts is ForPartsWithPattern) {
        containsInit = selectedNodes.contains(forLoopParts.variables);
      } else {
        throw StateError('Unrecognized for loop parts');
      }
      var containsCondition = selectedNodes.contains(forLoopParts.condition);
      var containsUpdaters = selectedNodes.containsAny(forLoopParts.updaters);
      var containsBody = selectedNodes.contains(node.body);
      if (containsInit && containsCondition) {
        invalidSelection(
          "Operation not applicable to a 'for' statement's initializer and condition.",
        );
      } else if (containsCondition && containsUpdaters) {
        invalidSelection(
          "Operation not applicable to a 'for' statement's condition and updaters.",
        );
      } else if (containsUpdaters && containsBody) {
        invalidSelection(
          "Operation not applicable to a 'for' statement's updaters and body.",
        );
      }
    }
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    super.visitSwitchStatement(node);
    var selectedNodes = this.selectedNodes;
    List<SwitchMember> switchMembers = node.members;
    for (var selectedNode in selectedNodes) {
      if (switchMembers.contains(selectedNode)) {
        invalidSelection(
          'Selection must either cover whole switch statement or parts of a single case block.',
        );
        break;
      }
    }
  }

  @override
  void visitTryStatement(TryStatement node) {
    super.visitTryStatement(node);
    var firstSelectedNode = this.firstSelectedNode;
    if (firstSelectedNode != null) {
      if (firstSelectedNode == node.body ||
          firstSelectedNode == node.finallyBlock) {
        invalidSelection(
          'Selection must either cover whole try statement or parts of try, catch, or finally block.',
        );
      } else {
        List<CatchClause> catchClauses = node.catchClauses;
        for (var catchClause in catchClauses) {
          if (firstSelectedNode == catchClause ||
              firstSelectedNode == catchClause.body ||
              firstSelectedNode == catchClause.exceptionParameter) {
            invalidSelection(
              'Selection must either cover whole try statement or parts of try, catch, or finally block.',
            );
          }
        }
      }
    }
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    super.visitWhileStatement(node);
    if (selectedNodes.contains(node.condition) &&
        selectedNodes.contains(node.body)) {
      invalidSelection(
        "Operation not applicable to a while statement's expression and body.",
      );
    }
  }

  /// Checks final selected [AstNode]s after processing [CompilationUnit].
  void _checkSelectedNodes(CompilationUnit unit) {
    var nodes = selectedNodes;
    // some tokens before first selected node
    {
      var firstNode = nodes[0];
      var rangeBeforeFirstNode = range.startOffsetEndOffset(
        selection.offset,
        firstNode.offset,
      );
      if (_hasTokens(rangeBeforeFirstNode)) {
        invalidSelection(
          'The beginning of the selection contains characters that '
          'do not belong to a statement.',
          newLocation_fromUnit(unit, rangeBeforeFirstNode),
        );
      }
    }
    // some tokens after last selected node
    {
      var lastNode = nodes.last;
      var rangeAfterLastNode = range.startOffsetEndOffset(
        lastNode.end,
        selection.end,
      );
      if (_hasTokens(rangeAfterLastNode)) {
        invalidSelection(
          'The end of the selection contains characters that '
          'do not belong to a statement.',
          newLocation_fromUnit(unit, rangeAfterLastNode),
        );
      }
    }
  }

  /// Returns `true` if there are [Token]s in the given [SourceRange].
  bool _hasTokens(SourceRange range) {
    var fullText = resolveResult.content;
    var rangeText = fullText.substring(range.offset, range.end);
    return _getTokens(rangeText, resolveResult.unit.featureSet).isNotEmpty;
  }
}

class _SourceMock implements Source {
  static final Source instance = _SourceMock();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
