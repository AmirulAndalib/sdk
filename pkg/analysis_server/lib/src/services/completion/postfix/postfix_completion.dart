// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/protocol_server.dart' hide Element;
import 'package:analysis_server/src/utilities/extensions/ast.dart';
import 'package:analysis_server_plugin/edit/correction_utils.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/generated/java_core.dart';
import 'package:analyzer/src/utilities/extensions/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:collection/collection.dart';

/// An enumeration of possible postfix completion kinds.
abstract final class DartPostfixCompletion {
  static const NO_TEMPLATE = PostfixCompletionKind(
    '',
    'no change',
    _false,
    _null,
  );

  static const List<PostfixCompletionKind> ALL_TEMPLATES = [
    PostfixCompletionKind(
      'assert',
      'expr.assert -> assert(expr);',
      isAssertContext,
      expandAssert,
    ),
    PostfixCompletionKind(
      'fori',
      'limit.fori -> for(var i = 0; i < limit; i++) {}',
      isIntContext,
      expandFori,
    ),
    PostfixCompletionKind(
      'for',
      'values.for -> for(var value in values) {}',
      isIterableContext,
      expandFor,
    ),
    PostfixCompletionKind(
      'iter',
      'values.iter -> for(var value in values) {}',
      isIterableContext,
      expandFor,
    ),
    PostfixCompletionKind(
      'not',
      'bool.not -> !bool',
      isBoolContext,
      expandNegate,
    ),
    PostfixCompletionKind('!', 'bool! -> !bool', isBoolContext, expandNegate),
    PostfixCompletionKind(
      'else',
      'bool.else -> if (!bool) {}',
      isBoolContext,
      expandElse,
    ),
    PostfixCompletionKind(
      'if',
      'bool.if -> if (bool) {}',
      isBoolContext,
      expandIf,
    ),
    PostfixCompletionKind(
      'nn',
      'expr.nn -> if (expr != null) {}',
      isObjectContext,
      expandNotNull,
    ),
    PostfixCompletionKind(
      'notnull',
      'expr.notnull -> if (expr != null) {}',
      isObjectContext,
      expandNotNull,
    ),
    PostfixCompletionKind(
      'null',
      'expr.null -> if (expr == null) {}',
      isObjectContext,
      expandNull,
    ),
    PostfixCompletionKind(
      'par',
      'expr.par -> (expr)',
      isObjectContext,
      expandParen,
    ),
    PostfixCompletionKind(
      'return',
      'expr.return -> return expr',
      isObjectContext,
      expandReturn,
    ),
    PostfixCompletionKind(
      'switch',
      'expr.switch -> switch (expr) {}',
      isSwitchContext,
      expandSwitch,
    ),
    PostfixCompletionKind(
      'try',
      'stmt.try -> try {stmt} catch (e,s) {}',
      isStatementContext,
      expandTry,
    ),
    PostfixCompletionKind(
      'tryon',
      'stmt.try -> try {stmt} on Exception catch (e,s) {}',
      isStatementContext,
      expandTryon,
    ),
    PostfixCompletionKind(
      'while',
      'expr.while -> while (expr) {}',
      isBoolContext,
      expandWhile,
    ),
  ];

  static Future<PostfixCompletion?> expandAssert(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(kind, processor.findAssertExpression, (expr) {
      return 'assert(${processor.utils.getNodeText(expr)});';
    }, withBraces: false);
  }

  static Future<PostfixCompletion?> expandElse(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findBoolExpression,
      (expr) => 'if (${processor.makeNegatedBoolExpr(expr)})',
    );
  }

  static Future<PostfixCompletion?> expandFor(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(kind, processor.findIterableExpression, (expr) {
      var value = processor.newVariable('value');
      return 'for (var $value in ${processor.utils.getNodeText(expr)})';
    });
  }

  static Future<PostfixCompletion?> expandFori(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(kind, processor.findIntExpression, (expr) {
      var index = processor.newVariable('i');
      return 'for (int $index = 0; $index < ${processor.utils.getNodeText(expr)}; $index++)';
    });
  }

  static Future<PostfixCompletion?> expandIf(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findBoolExpression,
      (expr) => 'if (${processor.utils.getNodeText(expr)})',
    );
  }

  static Future<PostfixCompletion?> expandNegate(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findBoolExpression,
      (expr) => processor.makeNegatedBoolExpr(expr),
      withBraces: false,
    );
  }

  static Future<PostfixCompletion?> expandNotNull(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(kind, processor.findObjectExpression, (expr) {
      return expr is NullLiteral
          ? 'if (false)'
          : 'if (${processor.utils.getNodeText(expr)} != null)';
    });
  }

  static Future<PostfixCompletion?> expandNull(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(kind, processor.findObjectExpression, (expr) {
      return expr is NullLiteral
          ? 'if (true)'
          : 'if (${processor.utils.getNodeText(expr)} == null)';
    });
  }

  static Future<PostfixCompletion?> expandParen(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findObjectExpression,
      (expr) => '(${processor.utils.getNodeText(expr)})',
      withBraces: false,
    );
  }

  static Future<PostfixCompletion?> expandReturn(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findObjectExpression,
      (expr) => 'return ${processor.utils.getNodeText(expr)};',
      withBraces: false,
    );
  }

  static Future<PostfixCompletion?> expandSwitch(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findObjectExpression,
      (expr) => 'switch (${processor.utils.getNodeText(expr)})',
    );
  }

  static Future<PostfixCompletion?> expandTry(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expandTry(kind, processor.findStatement);
  }

  static Future<PostfixCompletion?> expandTryon(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expandTry(kind, processor.findStatement, withOn: true);
  }

  static Future<PostfixCompletion?> expandWhile(
    PostfixCompletionProcessor processor,
    PostfixCompletionKind kind,
  ) {
    return processor.expand(
      kind,
      processor.findBoolExpression,
      (expr) => 'while (${processor.utils.getNodeText(expr)})',
    );
  }

  static PostfixCompletionKind? forKey(String key) =>
      ALL_TEMPLATES.firstWhereOrNull((kind) => kind.key == key);

  static bool isAssertContext(PostfixCompletionProcessor processor) {
    return processor.findAssertExpression() != null;
  }

  static bool isBoolContext(PostfixCompletionProcessor processor) {
    return processor.findBoolExpression() != null;
  }

  static bool isIntContext(PostfixCompletionProcessor processor) {
    return processor.findIntExpression() != null;
  }

  static bool isIterableContext(PostfixCompletionProcessor processor) {
    return processor.findIterableExpression() != null;
  }

  static bool isObjectContext(PostfixCompletionProcessor processor) {
    return processor.findObjectExpression() != null;
  }

  static bool isStatementContext(PostfixCompletionProcessor processor) {
    return processor.findStatement() != null;
  }

  static bool isSwitchContext(PostfixCompletionProcessor processor) {
    return processor.findObjectExpression() != null;
  }

  static bool _false(PostfixCompletionProcessor _) => false;

  static Future<PostfixCompletion?> _null(
    PostfixCompletionProcessor _,
    PostfixCompletionKind _,
  ) async => null;
}

/// A description of a postfix completion.
///
/// Clients may not extend, implement or mix-in this class.
class PostfixCompletion {
  /// A description of the assist being proposed.
  final PostfixCompletionKind kind;

  /// The change to be made in order to apply the assist.
  final SourceChange change;

  /// Initialize a newly created completion to have the given [kind] and
  /// [change].
  PostfixCompletion(this.kind, this.change);
}

/// The context for computing a postfix completion.
class PostfixCompletionContext {
  final ResolvedUnitResult resolveResult;
  final int selectionOffset;
  final String key;

  PostfixCompletionContext(this.resolveResult, this.selectionOffset, this.key);
}

/// A description of a template for postfix completion. Instances are intended
/// to hold the functions required to determine applicability and expand the
/// template, in addition to its name and simple example. The example is shown
/// (in IntelliJ) in a code-completion menu, so must be quite short.
///
/// Clients may not extend, implement or mix-in this class.
class PostfixCompletionKind {
  final String name, example;
  final bool Function(PostfixCompletionProcessor) selector;
  final Future<PostfixCompletion?> Function(
    PostfixCompletionProcessor,
    PostfixCompletionKind,
  )
  computer;

  const PostfixCompletionKind(
    this.name,
    this.example,
    this.selector,
    this.computer,
  );

  String get key => name == '!' ? name : '.$name';

  String get message => 'Expand $key';

  @override
  String toString() => name;
}

/// The computer for Dart postfix completions.
final class PostfixCompletionProcessor {
  static final _noCompletion = PostfixCompletion(
    DartPostfixCompletion.NO_TEMPLATE,
    SourceChange('', edits: []),
  );

  final PostfixCompletionContext _completionContext;
  final CorrectionUtils utils;
  AstNode? _node;
  PostfixCompletion? _completion;

  PostfixCompletionProcessor(this._completionContext)
    : utils = CorrectionUtils(_completionContext.resolveResult);

  String get _eol => utils.endOfLine;

  String get _file => _completionContext.resolveResult.path;

  String get _key => _completionContext.key;

  int get _selectionOffset => _completionContext.selectionOffset;

  AnalysisSession get _session => _completionContext.resolveResult.session;

  TypeProvider get _typeProvider =>
      _completionContext.resolveResult.typeProvider;

  TypeSystem get _typeSystem => _completionContext.resolveResult.typeSystem;

  CompilationUnit get _unit => _completionContext.resolveResult.unit;

  Future<PostfixCompletion> compute() async {
    _node = _unit.nodeCovering(offset: _selectionOffset);
    if (_node == null) {
      return _noCompletion;
    }
    var completer = DartPostfixCompletion.forKey(_key);
    if (completer == null) {
      return _noCompletion;
    }
    return await completer.computer(this, completer) ?? _noCompletion;
  }

  Future<PostfixCompletion?> expand(
    PostfixCompletionKind kind,
    Expression? Function() contexter,
    String Function(Expression) sourcer, {
    bool withBraces = true,
  }) async {
    var expr = contexter();
    if (expr == null) {
      return null;
    }

    var changeBuilder = ChangeBuilder(session: _session);
    await changeBuilder.addDartFileEdit(_file, (builder) {
      builder.addReplacement(range.node(expr), (builder) {
        var newSrc = sourcer(expr);
        builder.write(newSrc);
        if (withBraces) {
          builder.write(' {');
          builder.write(_eol);
          var indent = utils.getNodePrefix(expr);
          builder.write(indent);
          builder.write(utils.oneIndent);
          builder.selectHere();
          builder.write(_eol);
          builder.write(indent);
          builder.write('}');
        } else {
          builder.selectHere();
        }
      });
    });
    _setCompletionFromBuilder(changeBuilder, kind);
    return _completion;
  }

  Future<PostfixCompletion?> expandTry(
    PostfixCompletionKind kind,
    Statement? Function() contexter, {
    bool withOn = false,
  }) async {
    var stmt = contexter();
    if (stmt == null) {
      return null;
    }
    var changeBuilder = ChangeBuilder(session: _session);
    await changeBuilder.addDartFileEdit(_file, (builder) {
      var lineInfo = _completionContext.resolveResult.lineInfo;
      // Embed the full line(s) of the statement in the try block.
      var startLine = lineInfo.getLocation(stmt.offset).lineNumber - 1;
      var endLine = lineInfo.getLocation(stmt.end).lineNumber - 1;
      if (stmt is ExpressionStatement) {
        var semicolon = stmt.semicolon;
        if (semicolon != null && !semicolon.isSynthetic) {
          endLine += 1;
        }
      }
      var startOffset = lineInfo.getOffsetOfLine(startLine);
      var endOffset = lineInfo.getOffsetOfLine(endLine);
      var src = utils.getText(startOffset, endOffset - startOffset);
      var indent = utils.getLinePrefix(stmt.offset);
      builder.addReplacement(
        range.startOffsetEndOffset(startOffset, endOffset),
        (builder) {
          builder.write(indent);
          builder.write('try {');
          builder.write(_eol);
          builder.write(
            utils.replaceSourceIndent(
              src,
              indent,
              '$indent${utils.oneIndent}',
              includeLeading: true,
              ensureTrailingNewline: true,
            ),
          );
          builder.selectHere();
          builder.write(indent);
          builder.write('}');
          if (withOn) {
            builder.write(' on ');
            builder.addSimpleLinkedEdit('NAME', nameOfExceptionThrownBy(stmt));
          }
          builder.write(' catch (e, s) {');
          builder.write(_eol);
          builder.write(indent);
          builder.write(utils.oneIndent);
          builder.write('print(s);');
          builder.write(_eol);
          builder.write(indent);
          builder.write('}');
          builder.write(_eol);
        },
      );
    });
    _setCompletionFromBuilder(changeBuilder, kind);
    return _completion;
  }

  Expression? findAssertExpression() {
    if (_node is Expression) {
      var boolExpr = _findOuterExpression(_node, _typeProvider.boolType);
      if (boolExpr == null) {
        return null;
      }
      var parent = boolExpr.parent;
      var grandParent = parent?.parent;
      if (parent is ExpressionFunctionBody &&
          grandParent is FunctionExpression) {
        var type = grandParent.staticType;
        if (type is! FunctionType) {
          return boolExpr;
        }
        if (type.returnType == _typeProvider.boolType) {
          return grandParent;
        }
      }
      if (boolExpr.staticType == _typeProvider.boolType) {
        return boolExpr;
      }
    }
    return null;
  }

  Expression? findBoolExpression() =>
      _findOuterExpression(_node, _typeProvider.boolType);

  Expression? findIntExpression() =>
      _findOuterExpression(_node, _typeProvider.intType);

  Expression? findIterableExpression() =>
      _findOuterExpression(_node, _typeProvider.iterableDynamicType);

  Expression? findObjectExpression() =>
      _findOuterExpression(_node, _typeProvider.objectQuestionType);

  Statement? findStatement() {
    var astNode = _node;
    while (astNode != null) {
      if (astNode is Statement && astNode is! Block) {
        // Disallow control-flow statements.
        if (astNode is DoStatement ||
            astNode is IfStatement ||
            astNode is ForStatement ||
            astNode is SwitchStatement ||
            astNode is TryStatement ||
            astNode is WhileStatement) {
          return null;
        }
        return astNode;
      }
      astNode = astNode.parent;
    }
    return null;
  }

  Future<bool> isApplicable() async {
    _node = _unit.nodeCovering(offset: _selectionOffset);
    if (_node == null) {
      return false;
    }

    var offset = _completionContext.selectionOffset;
    if (_node?.commentTokenCovering(offset) != null) {
      return false;
    }

    var completer = DartPostfixCompletion.forKey(_key);
    if (completer == null) {
      return false;
    }
    return completer.selector(this);
  }

  String makeNegatedBoolExpr(Expression expr) {
    var originalSrc = utils.getNodeText(expr);
    var newSrc = utils.invertCondition(expr);
    if (newSrc != originalSrc) {
      return newSrc;
    } else {
      return '!${utils.getNodeText(expr)}';
    }
  }

  String nameOfExceptionThrownBy(AstNode astNode) {
    if (astNode is ExpressionStatement) {
      astNode = astNode.expression;
    }
    if (astNode is ThrowExpression) {
      var expr = astNode;
      var type = expr.expression.staticType;
      if (type is! TypeImpl) {
        return 'Exception';
      }

      // Can't catch nullable types, strip `?`s now that we've checked for `*`s.
      return type.withNullability(NullabilitySuffix.none).getDisplayString();
    }
    return 'Exception';
  }

  String newVariable(String base) {
    var name = base;
    var i = 1;
    var vars = _unit.findPossibleLocalVariableConflicts(_selectionOffset);
    while (vars.contains(name)) {
      name = '$base${i++}';
    }
    return name;
  }

  Expression? _findOuterExpression(AstNode? start, InterfaceType builtInType) {
    if (start is SimpleIdentifier && start.element is PrefixElement) {
      return null;
    }

    AstNode? parent;
    if (start is Expression) {
      parent = start;
    } else if (start is ArgumentList) {
      parent = start.parent;
    }
    if (parent == null) {
      return null;
    }

    var list = <Expression>[];
    while (parent is Expression) {
      list.add(parent);
      parent = parent.parent;
    }

    var expr = list.firstWhereOrNull((expr) {
      var type = expr.staticType;
      if (type == null) return false;
      return _typeSystem.isSubtypeOf(type, builtInType);
    });
    var exprParent = expr?.parent;
    if (expr is SimpleIdentifier && exprParent is PropertyAccess) {
      expr = exprParent;
    }
    if (exprParent is CascadeExpression) {
      expr = exprParent;
    }
    return expr;
  }

  void _setCompletionFromBuilder(
    ChangeBuilder builder,
    PostfixCompletionKind kind,
  ) {
    var change = builder.sourceChange;
    if (change.edits.isEmpty) {
      _completion = null;
      return;
    }
    change.message = formatList(kind.message, null);
    _completion = PostfixCompletion(kind, change);
  }
}
