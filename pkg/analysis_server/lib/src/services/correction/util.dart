// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:analysis_server/src/services/completion/dart/feature_computer.dart';
import 'package:analyzer/dart/ast/precedence.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/utilities/extensions/ast.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:path/path.dart' as path;

/// Climbs up [PrefixedIdentifier], [PropertyAccess], and
/// [DotShorthandPropertyAccess] nodes that include [node].
Expression climbPropertyAccess(Expression node) {
  while (true) {
    var parent = node.parent;
    if (parent is PrefixedIdentifier && parent.identifier == node) {
      node = parent;
      continue;
    }
    if (parent is PropertyAccess && parent.propertyName == node) {
      node = parent;
      continue;
    }
    if (parent is DotShorthandPropertyAccess && parent.propertyName == node) {
      node = parent;
      continue;
    }
    return node;
  }
}

/// Computes the [InterfaceElement] of the context type of a given
/// [dotShorthandNode].
///
/// Returns `null` if no context type exists or the context type isn't an
/// [InterfaceType].
InterfaceElement? computeDotShorthandContextTypeElement(
  AstNode dotShorthandNode,
  LibraryElement libraryElement,
) {
  var featureComputer = FeatureComputer(
    libraryElement.typeSystem,
    libraryElement.typeProvider,
  );
  var contextType = featureComputer.computeContextType(
    dotShorthandNode,
    dotShorthandNode.offset,
  );
  return contextType is InterfaceType ? contextType.element : null;
}

/// Return references to the [element] inside the [root] node.
List<AstNode> findImportPrefixElementReferences(
  AstNode root,
  PrefixElement element,
) {
  var collector = _ElementReferenceCollector(element);
  root.accept(collector);
  return collector.references;
}

/// Return references to the [element] inside the [root] node.
List<AstNode> findLocalElementReferences(AstNode root, LocalElement element) {
  var collector = _ElementReferenceCollector(element);
  root.accept(collector);
  return collector.references;
}

/// Returns [SourceRange]s of all comments in [unit].
List<SourceRange> getCommentRanges(CompilationUnit unit) {
  var ranges = <SourceRange>[];
  var token = unit.beginToken;
  while (!token.isEof) {
    var commentToken = token.precedingComments;
    while (commentToken != null) {
      ranges.add(range.token(commentToken));
      commentToken = commentToken.next as CommentToken?;
    }
    token = token.next!;
  }
  return ranges;
}

// TODO(scheglov): replace with nodes once there will be
// [CompilationUnit.getComments].
/// Return all [LocalElement]s defined in the given [node].
List<LocalElement> getDefinedLocalElements(AstNode node) {
  var collector = _LocalElementsCollector();
  node.accept(collector);
  return collector.elements;
}

/// Return the name of the kind of the [element].
String getElementKindName(Element element) {
  return element.kind.displayName;
}

/// Returns the name to display in the UI for the given [element].
String getElementQualifiedName(Element element) {
  var kind = element.kind;
  if (kind == ElementKind.FIELD || kind == ElementKind.METHOD) {
    return '${element.enclosingElement!.displayName}.${element.displayName}';
  } else if (kind == ElementKind.LIBRARY) {
    // Libraries may not have names, so use a path relative to the context root.
    var session = element.session!;
    var pathContext = session.resourceProvider.pathContext;
    var rootPath = session.analysisContext.contextRoot.root.path;
    var library = element as LibraryElement;

    return pathContext.relative(
      library.firstFragment.source.fullName,
      from: rootPath,
    );
  } else {
    return element.displayName;
  }
}

/// Returns a class or an unit member enclosing the given [input].
AstNode? getEnclosingClassOrUnitMember(AstNode input) {
  var member = input;
  for (var node in input.withAncestors) {
    switch (node) {
      case ClassDeclaration _:
      case CompilationUnit _:
      case EnumDeclaration _:
      case ExtensionDeclaration _:
      case ExtensionTypeDeclaration _:
      case MixinDeclaration _:
        return member;
    }
    member = node;
  }
  return null;
}

/// Return the enclosing executable [AstNode].
AstNode? getEnclosingExecutableNode(AstNode input) {
  for (var node in input.withAncestors) {
    if (node is FunctionDeclaration) {
      return node;
    }
    if (node is ConstructorDeclaration) {
      return node;
    }
    if (node is MethodDeclaration) {
      return node;
    }
  }
  return null;
}

/// Returns [getExpressionPrecedence] for the parent of [node], or
/// ASSIGNMENT_PRECEDENCE if the parent node is a [ParenthesizedExpression].
///
/// The reason is that `(expr)` is always executed after `expr`.
Precedence getExpressionParentPrecedence(AstNode node) {
  var parent = node.parent!;
  if (parent is ParenthesizedExpression) {
    return Precedence.assignment;
  } else if (parent is IndexExpression && parent.index == node) {
    return Precedence.assignment;
  } else if (parent is AssignmentExpression &&
      node == parent.rightHandSide &&
      parent.parent is CascadeExpression) {
    // This is a hack to allow nesting of cascade expressions within other
    // cascade expressions. The problem is that if the precedence of two
    // expressions are equal it sometimes means that we don't need parentheses
    // (such as replacing the `b` in `a + b` with `c + d`) and sometimes do
    // (such as replacing the `v` in `..f = v` with `a..b`).
    return Precedence.conditional;
  }
  return getExpressionPrecedence(parent);
}

/// Returns the precedence of [node] it is an [Expression], NO_PRECEDENCE
/// otherwise.
Precedence getExpressionPrecedence(AstNode node) {
  if (node is Expression) {
    return node.precedence;
  }
  return Precedence.none;
}

/// Returns the parameter's element if the [node] is a reference to a parameter.
///
/// Returns `null` if it isn't a reference to a parameter.
FormalParameterElement? getFormalParameterElement(SimpleIdentifier node) {
  var element = node.element;
  if (element is FormalParameterElement) {
    return element;
  }
  return null;
}

/// Returns the namespace of the given [LibraryImport].
Map<String, Element> getImportNamespace(LibraryImport imp) {
  return imp.namespace.definedNames2;
}

/// Computes the best URI to import [what] into [from].
String getLibrarySourceUri(
  path.Context pathContext,
  LibraryElement from,
  Uri what,
) {
  if (what.isScheme('file')) {
    var fromFolder = pathContext.dirname(from.firstFragment.source.fullName);
    var relativeFile = pathContext.relative(what.path, from: fromFolder);
    return pathContext.split(relativeFile).join('/');
  }
  return what.toString();
}

/// Return the variable's element if [node] is a reference to a local variable.
///
/// Returns `null` if it isn't a reference to a local variable.
LocalVariableElement? getLocalVariableElement(SimpleIdentifier node) {
  var element = node.element;
  if (element is LocalVariableElement) {
    return element;
  }
  return null;
}

/// Return the nearest common ancestor of the given [nodes].
AstNode? getNearestCommonAncestor(List<AstNode> nodes) {
  // may be no nodes
  if (nodes.isEmpty) {
    return null;
  }
  // prepare parents
  var parents = <List<AstNode>>[];
  for (var node in nodes) {
    parents.add(getParents(node));
  }
  // find min length
  var minLength = 1 << 20;
  for (var parentList in parents) {
    minLength = min(minLength, parentList.length);
  }
  // find deepest parent
  var i = 0;
  for (; i < minLength; i++) {
    if (!_allListsIdentical(parents, i)) {
      break;
    }
  }
  return parents[0][i - 1];
}

/// Returns the [Expression] qualifier if given [node] is the name part of a
/// [PropertyAccess] or a [PrefixedIdentifier]. Maybe `null`.
Expression? getNodeQualifier(SimpleIdentifier node) {
  var parent = node.parent;
  if (parent is MethodInvocation && identical(parent.methodName, node)) {
    return parent.target;
  }
  if (parent is PropertyAccess && identical(parent.propertyName, node)) {
    return parent.target;
  }
  if (parent is PrefixedIdentifier && identical(parent.identifier, node)) {
    return parent.prefix;
  }
  return null;
}

/// Return parent [AstNode]s from compilation unit (at index "0") to the given
/// [node].
List<AstNode> getParents(AstNode node) {
  return node.withAncestors.toList().reversed.toList();
}

/// If given [node] is name of qualified property extraction, returns target
/// from which this property is extracted, otherwise `null`.
Expression? getQualifiedPropertyTarget(AstNode node) => switch (node.parent) {
  PrefixedIdentifier parent when parent.identifier == node => parent.prefix,
  PropertyAccess parent when parent.propertyName == node => parent.realTarget,
  _ => null,
};

/// Returns the given [statement] if not a block, or the first child statement
/// if a block, or `null` if more than one child.
Statement? getSingleStatement(Statement? statement) {
  if (statement is Block) {
    List<Statement> blockStatements = statement.statements;
    if (blockStatements.length != 1) {
      return null;
    }
    return blockStatements[0];
  }
  return statement;
}

/// Returns the given [statement] if not a block, or all the children statements
/// if a block.
List<Statement> getStatements(Statement statement) {
  if (statement is Block) {
    return statement.statements;
  }
  return [statement];
}

/// Checks if the given [element]'s display name equals to the given [name].
bool hasDisplayName(Element? element, String name) {
  return element?.displayName == name;
}

/// Return whether the specified [name] is declared inside the [root] node
/// or not.
bool isDeclaredIn(AstNode root, String name) {
  bool isDeclaredIn(FormalParameterList? parameters) {
    if (parameters != null) {
      for (var parameter in parameters.parameters) {
        if (parameter.name?.lexeme == name) {
          return true;
        }
      }
    }
    return false;
  }

  if (root is MethodDeclaration && isDeclaredIn(root.parameters)) {
    return true;
  }
  if (root is FunctionDeclaration &&
      isDeclaredIn(root.functionExpression.parameters)) {
    return true;
  }

  var collector = _DeclarationCollector(name);
  root.accept(collector);
  return collector.isDeclared;
}

/// Returns whether the given [node] is the left hand side of an assignment, or
/// a declaration of a variable.
bool isLeftHandOfAssignment(SimpleIdentifier node) {
  if (node.inSetterContext()) {
    return true;
  }
  return node.parent is VariableDeclaration &&
      (node.parent as VariableDeclaration).name == node.token;
}

/// Return `true` if the given [node] is the name of a [NamedExpression].
bool isNamedExpressionName(SimpleIdentifier node) {
  var parent = node.parent;
  if (parent is Label) {
    var label = parent;
    if (identical(label.label, node)) {
      var parent2 = label.parent;
      if (parent2 is NamedExpression) {
        return identical(parent2.name, label);
      }
    }
  }
  return false;
}

/// If the given [expression] is the `expression` property of a
/// [NamedExpression] then returns this [NamedExpression], otherwise returns
/// [expression].
Expression stepUpNamedExpression(Expression expression) {
  var parent = expression.parent;
  return parent is NamedExpression ? parent : expression;
}

/// Return `true` if the given [lists] are identical at the given [position].
bool _allListsIdentical(List<List<Object>> lists, int position) {
  var element = lists[0][position];
  for (var list in lists) {
    if (list[position] != element) {
      return false;
    }
  }
  return true;
}

/// Computes a valid return type for a function based on the contained return
/// statements.
class ReturnTypeComputer extends RecursiveAstVisitor<void> {
  final TypeSystem _typeSystem;

  final bool _isGenerator;

  DartType? returnType;

  ReturnTypeComputer(this._typeSystem, {bool isGenerator = false})
    : _isGenerator = isGenerator;

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {}

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (_isGenerator) {
      // Return statements are illegal in generators. Ignore.
      return;
    }
    var type = node.expression?.typeOrThrow;
    if (type == null || type.isBottom) {
      return;
    }
    var current = returnType;
    if (current == null) {
      returnType = type;
    } else {
      returnType = _typeSystem.leastUpperBound(current, type);
    }
  }

  @override
  void visitYieldStatement(YieldStatement node) {
    if (!_isGenerator) {
      // Yield statements are illegal in non-generators. Ignore.
      return;
    }
    var type = node.expression.typeOrThrow;
    if (type.isBottom) {
      return;
    }
    var current = returnType;
    if (current == null) {
      returnType = type;
    } else {
      returnType = _typeSystem.leastUpperBound(current, type);
    }
  }
}

class _DeclarationCollector extends RecursiveAstVisitor<void> {
  final String name;
  bool isDeclared = false;

  _DeclarationCollector(this.name);

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme == name) {
      isDeclared = true;
    }
  }
}

class _ElementReferenceCollector extends RecursiveAstVisitor<void> {
  final Element element;
  final List<AstNode> references = [];

  _ElementReferenceCollector(this.element);

  @override
  void visitImportPrefixReference(ImportPrefixReference node) {
    if (node.element == element) {
      references.add(SimpleIdentifierImpl(token: node.name));
    }
  }

  @override
  void visitListPattern(ListPattern node) {
    for (var item in node.elements) {
      if (item is AssignedVariablePattern) {
        if (item.element == element) {
          references.add(item);
        }
      }
    }
  }

  @override
  void visitRecordPattern(RecordPattern node) {
    for (var field in node.fields) {
      var pattern = field.pattern.unparenthesized;
      if (pattern is AssignedVariablePattern) {
        if (pattern.element == element) {
          references.add(field.pattern);
        }
      }
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == element) {
      references.add(node);
    }
  }
}

/// Visitor that collects defined [LocalElement]s.
class _LocalElementsCollector extends RecursiveAstVisitor<void> {
  final elements = <LocalElement>[];

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    var element = node.declaredFragment?.element;
    if (element is LocalVariableElement) {
      elements.add(element);
    }

    super.visitVariableDeclaration(node);
  }
}

extension on DartPattern {
  DartPattern get unparenthesized {
    var self = this;
    if (self is! ParenthesizedPattern) return self;
    return self.pattern.unParenthesized;
  }
}
