// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:collection/collection.dart';

class UseResultVerifier {
  final DiagnosticReporter _diagnosticReporter;

  UseResultVerifier(this._diagnosticReporter);

  void checkFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    var element = node.element;
    if (element == null) {
      return;
    }

    _check(node, element);
  }

  void checkInstanceCreationExpression(InstanceCreationExpression node) {
    var element = node.constructorName.element;
    if (element == null) {
      return;
    }

    _check(node, element);
  }

  void checkMethodInvocation(MethodInvocation node) {
    var element = node.methodName.element;
    if (element == null) {
      return;
    }

    _check(node, element);
  }

  void checkPropertyAccess(PropertyAccess node) {
    var element = node.propertyName.element;
    if (element == null) {
      return;
    }

    _check(node, element);
  }

  void checkSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext()) {
      return;
    }

    var parent = node.parent;
    // Covered by checkPropertyAccess, checkMethodInvocation
    // and checkFunctionExpressionInvocation respectively.
    if (parent is PropertyAccess ||
        parent is MethodInvocation ||
        parent is FunctionExpressionInvocation) {
      return;
    }

    var element = node.element;
    if (element == null) {
      return;
    }

    _check(node, element);
  }

  void _check(AstNode node, Element element) {
    var parent = node.parent;
    if (parent is PrefixedIdentifier) {
      parent = parent.parent;
    }
    if (parent is CommentReference) {
      // Don't flag references in comments.
      return;
    }
    if (parent is ShowCombinator || parent is HideCombinator) {
      return;
    }

    var annotation = _getUseResultMetadata(element);
    if (annotation == null) {
      return;
    }

    if (_passesUsingParam(node, annotation)) {
      return;
    }

    if (_isUsed(node)) {
      return;
    }

    var toAnnotate = _getNodeToAnnotate(node);
    String displayName;
    if (toAnnotate is SimpleIdentifier) {
      displayName = toAnnotate.name;
    } else {
      displayName = element.displayName;
    }

    var message = _getUseResultMessage(annotation);
    if (message == null || message.isEmpty) {
      _diagnosticReporter.atNode(
        toAnnotate,
        WarningCode.UNUSED_RESULT,
        arguments: [displayName],
      );
    } else {
      _diagnosticReporter.atNode(
        toAnnotate,
        WarningCode.UNUSED_RESULT_WITH_MESSAGE,
        arguments: [displayName, message],
      );
    }
  }

  String? _getUseResultMessage(ElementAnnotation annotation) {
    if (annotation.element is GetterElement) {
      return null;
    }
    var constantValue = annotation.computeConstantValue();
    return constantValue?.getField('message')?.toStringValue();
  }

  String? _getUseResultUnlessParam(ElementAnnotation annotation) {
    var constantValue = annotation.computeConstantValue();
    return constantValue?.getField('parameterDefined')?.toStringValue();
  }

  bool _passesUsingParam(AstNode node, ElementAnnotation annotation) {
    if (node is! MethodInvocation) {
      return false;
    }

    var unlessParam = _getUseResultUnlessParam(annotation);
    if (unlessParam == null) {
      return false;
    }

    var argumentList = node.argumentList as ArgumentListImpl;
    var parameters = argumentList.correspondingStaticParameters;
    if (parameters == null) {
      return false;
    }

    for (var param in parameters) {
      var name = param?.name;
      if (unlessParam == name) {
        return true;
      }
    }

    return false;
  }

  static AstNode _getNodeToAnnotate(AstNode node) {
    if (node is MethodInvocation) {
      return node.methodName;
    }
    if (node is PropertyAccess) {
      return node.propertyName;
    }
    if (node is FunctionExpressionInvocation) {
      return _getNodeToAnnotate(node.function);
    }
    return node;
  }

  static ElementAnnotation? _getUseResultMetadata(Element element) {
    // Implicit getters/setters.
    if (element.isSynthetic && element is PropertyAccessorElement) {
      element = element.variable;
    }

    return element.metadata.annotations.firstWhereOrNull((e) => e.isUseResult);
  }

  static bool _isUsed(AstNode node) {
    var parent = node.parent;
    if (parent == null) {
      return false;
    }

    if (parent is CascadeExpression) {
      return parent.target == node;
    }

    if (parent is PrefixedIdentifier) {
      if (parent.prefix == node) {
        return true;
      } else {
        return _isUsed(parent);
      }
    }

    if (parent is PostfixExpression) {
      if (parent.operator.type == TokenType.BANG) {
        // Null-checking a result is not a "use."
        return _isUsed(parent);
      } else {
        // Other uses, like `++`, count as a "use."
        return true;
      }
    }

    if (parent is AsExpression ||
        parent is AwaitExpression ||
        parent is ConditionalExpression ||
        parent is ForElement ||
        parent is IfElement ||
        parent is ParenthesizedExpression ||
        parent is PrefixExpression ||
        parent is SpreadElement) {
      return _isUsed(parent);
    }

    if (parent is ForParts) {
      // If [node] is the condition of a for-loop, it is used; if it is one of
      // the updaters, it is not.
      return parent.condition == node;
    }

    return parent is ArgumentList ||
        parent is AssertInitializer ||
        parent is AssertStatement ||
        // Node should always be RHS so no need to check for a property
        // assignment.
        parent is AssignmentExpression ||
        parent is BinaryExpression ||
        parent is ConstructorFieldInitializer ||
        parent is DoStatement ||
        parent is ExpressionFunctionBody ||
        parent is ForEachParts ||
        parent is ForLoopParts ||
        parent is FunctionExpressionInvocation ||
        parent is IfStatement ||
        parent is IndexExpression ||
        parent is InterpolationExpression ||
        parent is ListLiteral ||
        parent is MapLiteralEntry ||
        parent is MethodInvocation ||
        parent is NamedExpression ||
        parent is PatternVariableDeclaration ||
        parent is PropertyAccess ||
        parent is RecordLiteral ||
        parent is ReturnStatement ||
        parent is SetOrMapLiteral ||
        parent is SwitchExpressionCase ||
        parent is SwitchStatement ||
        parent is ThrowExpression ||
        parent is VariableDeclaration ||
        parent is WhenClause ||
        parent is WhileStatement ||
        parent is YieldStatement;
  }
}
