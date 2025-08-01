// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'package:analyzer/src/generated/resolver.dart';
library;

import 'package:_fe_analyzer_shared/src/flow_analysis/flow_analysis.dart';
import 'package:_fe_analyzer_shared/src/flow_analysis/flow_analysis_operations.dart';
import 'package:_fe_analyzer_shared/src/type_inference/assigned_variables.dart';
import 'package:_fe_analyzer_shared/src/type_inference/type_analyzer.dart';
import 'package:_fe_analyzer_shared/src/type_inference/type_analyzer_operations.dart';
import 'package:_fe_analyzer_shared/src/types/shared_type.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_constraint_gatherer.dart';
import 'package:analyzer/src/dart/element/type_schema.dart';
import 'package:analyzer/src/dart/element/type_system.dart' show TypeSystemImpl;
import 'package:analyzer/src/generated/inference_log.dart';
import 'package:analyzer/src/generated/variable_type_provider.dart';

export 'package:_fe_analyzer_shared/src/type_inference/nullability_suffix.dart'
    show NullabilitySuffix;

/// Data gathered by flow analysis, retained for testing purposes.
class FlowAnalysisDataForTesting {
  /// The list of nodes, [Expression]s or [Statement]s, that cannot be reached,
  /// for example because a previous statement always exits.
  final List<AstNode> unreachableNodes = [];

  /// The list of [FunctionBody]s that don't complete, for example because
  /// there is a `return` statement at the end of the function body block.
  final List<FunctionBody> functionBodiesThatDontComplete = [];

  /// The list of references to variables, where a variable is read, and
  /// is not definitely assigned.
  final List<SimpleIdentifier> notDefinitelyAssigned = [];

  /// The list of references to variables, where a variable is read, and
  /// is definitely assigned.
  final List<SimpleIdentifier> definitelyAssigned = [];

  /// The list of references to variables, where a variable is written, and
  /// is definitely unassigned.
  final List<SimpleIdentifier> definitelyUnassigned = [];

  /// For each top level or class level declaration, the assigned variables
  /// information that was computed for it.
  final Map<
    AstNode,
    AssignedVariablesForTesting<AstNode, PromotableElementImpl>
  >
  assignedVariables = {};

  /// For each expression that led to an error because it was not promoted, a
  /// string describing the reason it was not promoted.
  Map<SyntacticEntity, String> nonPromotionReasons = {};

  /// For each auxiliary AST node pointed to by a non-promotion reason, a string
  /// describing the non-promotion reason pointing to it.
  Map<AstNode, String> nonPromotionReasonTargets = {};
}

/// The helper for performing flow analysis during resolution.
///
/// It contains related precomputed data, result, and non-trivial pieces of
/// code that are independent from visiting AST during resolution, so can
/// be extracted.
class FlowAnalysisHelper {
  /// The reused instance for creating new [FlowAnalysis] instances.
  final TypeSystemOperations typeOperations;

  /// Precomputed sets of potentially assigned variables.
  AssignedVariables<AstNodeImpl, PromotableElementImpl>? assignedVariables;

  /// The result for post-resolution stages of analysis, for testing only.
  final FlowAnalysisDataForTesting? dataForTesting;

  final TypeAnalyzerOptions typeAnalyzerOptions;

  /// The current flow, when resolving a function body, or `null` otherwise.
  FlowAnalysis<
    AstNodeImpl,
    StatementImpl,
    ExpressionImpl,
    PromotableElementImpl,
    SharedTypeView
  >?
  flow;

  FlowAnalysisHelper(
    bool retainDataForTesting, {
    required TypeSystemOperations typeSystemOperations,
    required TypeAnalyzerOptions typeAnalyzerOptions,
  }) : this._(
         typeSystemOperations,
         retainDataForTesting ? FlowAnalysisDataForTesting() : null,
         typeAnalyzerOptions: typeAnalyzerOptions,
       );

  FlowAnalysisHelper._(
    this.typeOperations,
    this.dataForTesting, {
    required this.typeAnalyzerOptions,
  });

  LocalVariableTypeProvider get localVariableTypeProvider {
    return _LocalVariableTypeProvider(this);
  }

  void asExpression(AsExpressionImpl node) {
    if (flow == null) return;

    var expression = node.expression;
    var typeAnnotation = node.type;

    flow!.asExpression_end(
      expression,
      subExpressionType: SharedTypeView(expression.typeOrThrow),
      castType: SharedTypeView(typeAnnotation.typeOrThrow),
    );
  }

  void assignmentExpression(AssignmentExpressionImpl node) {
    if (flow == null) return;

    if (node.operator.type == TokenType.QUESTION_QUESTION_EQ) {
      flow!.ifNullExpression_rightBegin(
        node.leftHandSide,
        SharedTypeView(node.readType!),
      );
    }
  }

  void assignmentExpression_afterRight(AssignmentExpression node) {
    if (flow == null) return;

    if (node.operator.type == TokenType.QUESTION_QUESTION_EQ) {
      flow!.ifNullExpression_end();
    }
  }

  /// This method is called whenever the [ResolverVisitor] enters the body or
  /// initializer of a top level declaration.
  ///
  /// It causes flow analysis to be initialized.
  ///
  /// [node] is the top level declaration that is being entered. [parameters] is
  /// the formal parameter list of [node], or `null` if [node] doesn't have a
  /// formal parameter list.
  ///
  /// [visit] is a callback that can be used to visit the body or initializer of
  /// the top level declaration. This is used to compute assigned variables
  /// information within the body or initializer. If `null`, the entire [node]
  /// will be visited.
  void bodyOrInitializer_enter(
    AstNodeImpl node,
    FormalParameterListImpl? parameters, {
    void Function(AstVisitor<Object?> visitor)? visit,
  }) {
    inferenceLogWriter?.enterBodyOrInitializer(node);
    assert(flow == null);
    assignedVariables = computeAssignedVariables(
      node,
      parameters,
      retainDataForTesting: dataForTesting != null,
      visit: visit,
    );
    if (dataForTesting != null) {
      dataForTesting!.assignedVariables[node] =
          assignedVariables
              as AssignedVariablesForTesting<
                AstNodeImpl,
                PromotableElementImpl
              >;
    }
    flow = FlowAnalysis<
      AstNodeImpl,
      StatementImpl,
      ExpressionImpl,
      PromotableElementImpl,
      SharedTypeView
    >(
      typeOperations,
      assignedVariables!,
      typeAnalyzerOptions: typeAnalyzerOptions,
    );
  }

  /// This method is called whenever the [ResolverVisitor] leaves the body or
  /// initializer of a top level declaration.
  void bodyOrInitializer_exit() {
    inferenceLogWriter?.exitBodyOrInitializer();
    // Set this.flow to null before doing any clean-up so that if an exception
    // is raised, the state is already updated correctly, and we don't have
    // cascading failures.
    var flow = this.flow;
    this.flow = null;
    assignedVariables = null;

    flow!.finish();
  }

  void breakStatement(BreakStatement node) {
    var target = getLabelTarget(node, node.label?.element, isBreak: true);
    flow!.handleBreak(target);
  }

  /// Mark the [node] as unreachable if it is not covered by another node that
  /// is already known to be unreachable.
  void checkUnreachableNode(AstNode node) {
    if (flow == null) return;
    if (flow!.isReachable) return;

    if (dataForTesting != null) {
      dataForTesting!.unreachableNodes.add(node);
    }
  }

  void continueStatement(ContinueStatement node) {
    var target = getLabelTarget(node, node.label?.element, isBreak: false);
    flow!.handleContinue(target);
  }

  void executableDeclaration_enter(
    AstNodeImpl node,
    FormalParameterList? parameters, {
    required bool isClosure,
  }) {
    if (isClosure) {
      flow!.functionExpression_begin(node);
    }

    if (parameters != null) {
      for (var parameter in parameters.parameters) {
        // TODO(paulberry): try to remove this cast by changing `parameters` to
        // a `FormalParameterListImpl`
        var declaredElement =
            parameter.declaredFragment!.element as PromotableElementImpl;
        flow!.declare(
          declaredElement,
          SharedTypeView(declaredElement.type),
          initialized: true,
        );
      }
    }
  }

  void executableDeclaration_exit(FunctionBody body, bool isClosure) {
    if (isClosure) {
      flow!.functionExpression_end();
    }
    if (!flow!.isReachable) {
      dataForTesting?.functionBodiesThatDontComplete.add(body);
    }
  }

  void for_bodyBegin(AstNode node, ExpressionImpl? condition) {
    flow?.for_bodyBegin(node is StatementImpl ? node : null, condition);
  }

  void for_conditionBegin(AstNodeImpl node) {
    flow?.for_conditionBegin(node);
  }

  bool isDefinitelyAssigned(
    SimpleIdentifier node,
    PromotableElementImpl element,
  ) {
    var isAssigned = flow!.isAssigned(element);

    if (dataForTesting != null) {
      if (isAssigned) {
        dataForTesting!.definitelyAssigned.add(node);
      } else {
        dataForTesting!.notDefinitelyAssigned.add(node);
      }
    }

    return isAssigned;
  }

  bool isDefinitelyUnassigned(
    SimpleIdentifier node,
    PromotableElementImpl element,
  ) {
    var isUnassigned = flow!.isUnassigned(element);

    if (dataForTesting != null && isUnassigned) {
      dataForTesting!.definitelyUnassigned.add(node);
    }

    return isUnassigned;
  }

  void isExpression(IsExpressionImpl node) {
    if (flow == null) return;

    var expression = node.expression;
    var typeAnnotation = node.type;

    flow!.isExpression_end(
      node,
      expression,
      node.notOperator != null,
      subExpressionType: SharedTypeView(expression.typeOrThrow),
      checkedType: SharedTypeView(typeAnnotation.typeOrThrow),
    );
  }

  void labeledStatement_enter(LabeledStatementImpl node) {
    if (flow == null) return;

    flow!.labeledStatement_begin(node);
  }

  void labeledStatement_exit(LabeledStatement node) {
    if (flow == null) return;

    flow!.labeledStatement_end();
  }

  /// Transfers any test data that was recorded for [oldNode] so that it is now
  /// associated with [newNode].  We need to do this when doing AST rewriting,
  /// so that test data can be found using the rewritten tree.
  void transferTestData(AstNode oldNode, AstNode newNode) {
    var dataForTesting = this.dataForTesting;
    if (dataForTesting != null) {
      var oldNonPromotionReasons = dataForTesting.nonPromotionReasons[oldNode];
      if (oldNonPromotionReasons != null) {
        dataForTesting.nonPromotionReasons[newNode] = oldNonPromotionReasons;
      }
    }
  }

  void variableDeclarationList(VariableDeclarationListImpl node) {
    if (flow != null) {
      var variables = node.variables;
      for (var i = 0; i < variables.length; ++i) {
        var variable = variables[i];
        var declaredElement = variable.declaredElement!;
        flow!.declare(
          declaredElement,
          SharedTypeView(declaredElement.type),
          initialized: variable.initializer != null,
        );
      }
    }
  }

  /// Computes the [AssignedVariables] map for the given [node].
  static AssignedVariables<AstNodeImpl, PromotableElementImpl>
  computeAssignedVariables(
    AstNodeImpl node,
    FormalParameterListImpl? parameters, {
    bool retainDataForTesting = false,
    void Function(AstVisitor<Object?> visitor)? visit,
  }) {
    AssignedVariables<AstNodeImpl, PromotableElementImpl> assignedVariables =
        retainDataForTesting
            ? AssignedVariablesForTesting()
            : AssignedVariables();
    var assignedVariablesVisitor = _AssignedVariablesVisitor(assignedVariables);
    assignedVariablesVisitor._declareParameters(parameters);
    if (visit != null) {
      visit(assignedVariablesVisitor);
    } else {
      node.visitChildren(assignedVariablesVisitor);
    }
    assignedVariables.finish();
    return assignedVariables;
  }

  /// Return the target of the `break` or `continue` statement with the
  /// [element] label. The [element] might be `null` (when the statement does
  /// not specify a label), so the default enclosing target is returned.
  ///
  /// [isBreak] is `true` for `break`, and `false` for `continue`.
  static StatementImpl? getLabelTarget(
    AstNode? node,
    Element? element, {
    required bool isBreak,
  }) {
    for (; node != null; node = node.parent) {
      if (element == null) {
        switch (node) {
          case DoStatementImpl():
            return node;
          case ForStatementImpl():
            return node;
          case SwitchStatementImpl() when isBreak:
            return node;
          case WhileStatementImpl():
            return node;
        }
      } else {
        if (node is LabeledStatementImpl) {
          if (_hasLabel(node.labels, element)) {
            var statement = node.statement;
            // The inner statement is returned for labeled loops and
            // switch statements, while the LabeledStatement is returned
            // for the other known targets. This could be possibly changed
            // so that the inner statement is always returned.
            if (statement is Block ||
                statement is BreakStatement ||
                statement is IfStatement ||
                statement is TryStatement) {
              return node;
            }
            return statement;
          }
        }
        if (node is SwitchStatementImpl) {
          for (var member in node.members) {
            if (_hasLabel(member.labels, element)) {
              return node;
            }
          }
        }
      }
    }
    return null;
  }

  static bool _hasLabel(List<Label> labels, Element element) {
    for (var nodeLabel in labels) {
      if (identical(nodeLabel.label.element, element)) {
        return true;
      }
    }
    return false;
  }
}

class TypeSystemOperations
    with
        TypeAnalyzerOperationsMixin<
          PromotableElementImpl,
          InterfaceTypeImpl,
          InterfaceElementImpl
        >
    implements
        TypeAnalyzerOperations<
          PromotableElementImpl,
          InterfaceTypeImpl,
          InterfaceElementImpl
        > {
  final bool strictCasts;
  final TypeSystemImpl typeSystem;

  TypeSystemOperations(this.typeSystem, {required this.strictCasts});

  @override
  SharedTypeView get boolType {
    return SharedTypeView(typeSystem.typeProvider.boolType);
  }

  @override
  SharedTypeView get doubleType {
    throw UnimplementedError('TODO(paulberry)');
  }

  @override
  SharedTypeView get dynamicType {
    return SharedTypeView(typeSystem.typeProvider.dynamicType);
  }

  @override
  SharedTypeView get errorType {
    return SharedTypeView(InvalidTypeImpl.instance);
  }

  @override
  SharedTypeView get intType {
    throw UnimplementedError('TODO(paulberry)');
  }

  @override
  SharedTypeView get neverType {
    return SharedTypeView(typeSystem.typeProvider.neverType);
  }

  @override
  SharedTypeView get nullType {
    return SharedTypeView(typeSystem.typeProvider.nullType);
  }

  @override
  SharedTypeView get objectQuestionType {
    return SharedTypeView(typeSystem.objectQuestion);
  }

  @override
  SharedTypeView get objectType {
    return SharedTypeView(typeSystem.objectNone);
  }

  @override
  SharedTypeSchemaView get unknownType {
    return SharedTypeSchemaView(UnknownInferredType.instance);
  }

  @override
  TypeClassification classifyType(SharedTypeView type) {
    TypeImpl unwrapped = type.unwrapTypeView();
    if (type is InvalidType) {
      return TypeClassification.potentiallyNullable;
    } else if (isSubtypeOfInternal(
      unwrapped,
      typeSystem.typeProvider.objectType,
    )) {
      return TypeClassification.nonNullable;
    } else if (isSubtypeOfInternal(
      unwrapped,
      typeSystem.typeProvider.nullType,
    )) {
      return TypeClassification.nullOrEquivalent;
    } else {
      return TypeClassification.potentiallyNullable;
    }
  }

  @override
  TypeConstraintGenerator<
    PromotableElementImpl,
    InterfaceTypeImpl,
    InterfaceElementImpl,
    AstNodeImpl
  >
  createTypeConstraintGenerator({
    required covariant TypeConstraintGenerationDataForTesting?
    typeConstraintGenerationDataForTesting,
    required List<SharedTypeParameterView> typeParametersToInfer,
    required covariant TypeSystemOperations typeAnalyzerOperations,
    required bool inferenceUsingBoundsIsEnabled,
  }) {
    return TypeConstraintGatherer(
      typeParameters: typeParametersToInfer.cast<TypeParameterElementImpl>(),
      inferenceUsingBoundsIsEnabled: inferenceUsingBoundsIsEnabled,
      typeSystemOperations: typeAnalyzerOperations,
      dataForTesting: typeConstraintGenerationDataForTesting,
    );
  }

  @override
  SharedTypeView extensionTypeErasure(SharedTypeView type) {
    return SharedTypeView(type.unwrapTypeView<TypeImpl>().extensionTypeErasure);
  }

  @override
  SharedTypeView factor(SharedTypeView from, SharedTypeView what) {
    return SharedTypeView(
      typeSystem.factor(
        from.unwrapTypeView<TypeImpl>(),
        what.unwrapTypeView<TypeImpl>(),
      ),
    );
  }

  @override
  TypeImpl futureTypeInternal(TypeImpl argumentType) {
    return typeSystem.typeProvider.futureType(argumentType);
  }

  @override
  TypeDeclarationKind? getTypeDeclarationKindInternal(TypeImpl type) {
    if (isInterfaceTypeInternal(type)) {
      return TypeDeclarationKind.interfaceDeclaration;
    } else if (isExtensionTypeInternal(type)) {
      return TypeDeclarationKind.extensionTypeDeclaration;
    } else {
      return null;
    }
  }

  @override
  Variance getTypeParameterVariance(
    InterfaceElementImpl typeDeclaration,
    int parameterIndex,
  ) {
    return typeDeclaration.typeParameters[parameterIndex].variance;
  }

  @override
  TypeImpl glbInternal(TypeImpl type1, TypeImpl type2) {
    return typeSystem.greatestLowerBound(type1, type2);
  }

  @override
  SharedTypeView greatestClosureOfSchema(
    SharedTypeSchemaView schema, {
    SharedTypeView? topType,
  }) {
    return SharedTypeView(
      typeSystem.greatestClosureOfSchema(schema.unwrapTypeSchemaView()),
    );
  }

  @override
  TypeImpl greatestClosureOfTypeInternal(
    TypeImpl type,
    List<SharedTypeParameter> typeParametersToEliminate,
  ) {
    return typeSystem.greatestClosure(
      type,
      typeParametersToEliminate.cast<TypeParameterElementImpl>(),
    );
  }

  @override
  bool isAlwaysExhaustiveType(SharedTypeView type) {
    return typeSystem.isAlwaysExhaustive(type.unwrapTypeView<TypeImpl>());
  }

  @override
  bool isAssignableTo(SharedTypeView fromType, SharedTypeView toType) {
    return typeSystem.isAssignableTo(
      fromType.unwrapTypeView<TypeImpl>(),
      toType.unwrapTypeView<TypeImpl>(),
      strictCasts: strictCasts,
    );
  }

  @override
  bool isBottomType(SharedTypeView type) {
    return type.unwrapTypeView<TypeImpl>().isBottom;
  }

  @override
  bool isDartCoreFunctionInternal(TypeImpl type) {
    return type.nullabilitySuffix == NullabilitySuffix.none &&
        type.isDartCoreFunction;
  }

  @override
  bool isDartCoreRecordInternal(TypeImpl type) {
    return type.nullabilitySuffix == NullabilitySuffix.none &&
        type.isDartCoreRecord;
  }

  @override
  bool isExtensionTypeInternal(TypeImpl type) {
    return type is InterfaceType && type.element is ExtensionTypeElement;
  }

  @override
  bool isFinal(PromotableElementImpl variable) {
    return variable.isFinal;
  }

  @override
  bool isInterfaceTypeInternal(TypeImpl type) {
    return type is InterfaceType &&
        !type.isDartCoreNull &&
        !type.isDartAsyncFutureOr &&
        type.element is! ExtensionTypeElement;
  }

  @override
  bool isKnownType(SharedTypeSchemaView typeSchema) {
    return UnknownInferredType.isKnown(
      typeSchema.unwrapTypeSchemaView<TypeImpl>(),
    );
  }

  @override
  bool isNonNullableInternal(TypeImpl type) {
    return typeSystem.isNonNullable(type);
  }

  @override
  bool isNullableInternal(TypeImpl type) {
    return typeSystem.isNullable(type);
  }

  @override
  bool isObject(SharedTypeView type) {
    return type.unwrapTypeView<TypeImpl>().isDartCoreObject &&
        !type.isQuestionType;
  }

  @override
  bool isPropertyPromotable(Object property) {
    if (property is! PropertyAccessorElement) return false;
    var field = property.variable;
    if (field is! FieldElement) return false;
    return field.isPromotable;
  }

  @override
  bool isSubtypeOfInternal(TypeImpl leftType, TypeImpl rightType) {
    return typeSystem.isSubtypeOf(leftType, rightType);
  }

  @override
  bool isTypeParameterType(SharedTypeView type) {
    return type.unwrapTypeView<TypeImpl>() is TypeParameterType;
  }

  @override
  bool isTypeSchemaSatisfied({
    required SharedTypeSchemaView typeSchema,
    required SharedTypeView type,
  }) {
    return typeSystem.isSubtypeOf(
      type.unwrapTypeView<TypeImpl>(),
      typeSchema.unwrapTypeSchemaView(),
    );
  }

  @override
  bool isVariableFinal(PromotableElementImpl element) {
    return element.isFinal;
  }

  @override
  SharedTypeSchemaView iterableTypeSchema(
    SharedTypeSchemaView elementTypeSchema,
  ) {
    return SharedTypeSchemaView(
      typeSystem.typeProvider.iterableType(
        elementTypeSchema.unwrapTypeSchemaView<TypeImpl>(),
      ),
    );
  }

  @override
  SharedTypeView leastClosureOfSchema(SharedTypeSchemaView schema) {
    return SharedTypeView(
      typeSystem.leastClosureOfSchema(schema.unwrapTypeSchemaView()),
    );
  }

  @override
  TypeImpl leastClosureOfTypeInternal(
    TypeImpl type,
    List<SharedTypeParameter> typeParametersToEliminate,
  ) {
    return typeSystem.leastClosure(
      type,
      typeParametersToEliminate.cast<TypeParameterElementImpl>(),
    );
  }

  @override
  TypeImpl listTypeInternal(TypeImpl elementType) {
    return typeSystem.typeProvider.listType(elementType);
  }

  @override
  TypeImpl lubInternal(TypeImpl type1, TypeImpl type2) {
    return typeSystem.leastUpperBound(type1, type2);
  }

  @override
  TypeImpl makeNullableInternal(TypeImpl type) {
    return typeSystem.makeNullable(type);
  }

  @override
  TypeImpl mapTypeInternal({
    required TypeImpl keyType,
    required TypeImpl valueType,
  }) {
    return typeSystem.typeProvider.mapType(keyType, valueType);
  }

  @override
  TypeImpl? matchFutureOrInternal(TypeImpl type) {
    if (type is InterfaceTypeImpl && type.isDartAsyncFutureOr) {
      return type.typeArguments[0];
    } else {
      return null;
    }
  }

  @override
  TypeParameterElementImpl? matchInferableParameterInternal(TypeImpl type) {
    if (type is TypeParameterTypeImpl) {
      return type.element;
    } else {
      return null;
    }
  }

  @override
  TypeImpl? matchIterableTypeInternal(TypeImpl type) {
    var iterableElement = typeSystem.typeProvider.iterableElement;
    var listType = type.asInstanceOf(iterableElement);
    return listType?.typeArguments[0];
  }

  @override
  SharedTypeView? matchListType(SharedTypeView type) {
    var listElement = typeSystem.typeProvider.listElement;
    var listType = type.unwrapTypeView<TypeImpl>().asInstanceOf(listElement);
    return listType == null ? null : SharedTypeView(listType.typeArguments[0]);
  }

  @override
  ({SharedTypeView keyType, SharedTypeView valueType})? matchMapType(
    SharedTypeView type,
  ) {
    var mapElement = typeSystem.typeProvider.mapElement;
    var mapType = type.unwrapTypeView<TypeImpl>().asInstanceOf(mapElement);
    if (mapType != null) {
      return (
        keyType: SharedTypeView(mapType.typeArguments[0]),
        valueType: SharedTypeView(mapType.typeArguments[1]),
      );
    }
    return null;
  }

  @override
  SharedTypeView? matchStreamType(SharedTypeView type) {
    var streamElement = typeSystem.typeProvider.streamElement;
    var listType = type.unwrapTypeView<TypeImpl>().asInstanceOf(streamElement);
    return listType == null ? null : SharedTypeView(listType.typeArguments[0]);
  }

  @override
  TypeDeclarationMatchResult<InterfaceTypeImpl, InterfaceElementImpl>?
  matchTypeDeclarationTypeInternal(TypeImpl type) {
    if (isInterfaceTypeInternal(type)) {
      InterfaceTypeImpl interfaceType = type as InterfaceTypeImpl;
      return TypeDeclarationMatchResult(
        typeDeclarationKind: TypeDeclarationKind.interfaceDeclaration,
        typeDeclarationType: interfaceType,
        typeDeclaration: interfaceType.element,
        typeArguments: interfaceType.typeArguments,
      );
    } else if (isExtensionTypeInternal(type)) {
      InterfaceTypeImpl interfaceType = type as InterfaceTypeImpl;
      return TypeDeclarationMatchResult(
        typeDeclarationKind: TypeDeclarationKind.extensionTypeDeclaration,
        typeDeclarationType: interfaceType,
        typeDeclaration: interfaceType.element,
        typeArguments: interfaceType.typeArguments,
      );
    } else {
      return null;
    }
  }

  @override
  TypeImpl? matchTypeParameterBoundInternal(TypeImpl type) {
    if (type is TypeParameterTypeImpl &&
        type.nullabilitySuffix == NullabilitySuffix.none) {
      return type.promotedBound ?? type.element.bound;
    } else {
      return null;
    }
  }

  @override
  SharedTypeView normalize(SharedTypeView type) {
    return SharedTypeView(
      typeSystem.normalize(type.unwrapTypeView<TypeImpl>()),
    );
  }

  @override
  SharedTypeView promoteToNonNull(SharedTypeView type) {
    return SharedTypeView(
      typeSystem.promoteToNonNull(type.unwrapTypeView<TypeImpl>()),
    );
  }

  @override
  TypeImpl recordTypeInternal({
    required List<SharedType> positional,
    required List<(String, SharedType)> named,
  }) {
    return RecordTypeImpl(
      positionalFields:
          positional.map((type) {
            return RecordTypePositionalFieldImpl(type: type as DartType);
          }).toList(),
      namedFields:
          named.map((namedType) {
            var (name, type) = namedType;
            return RecordTypeNamedFieldImpl(name: name, type: type as DartType);
          }).toList(),
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  @override
  SharedTypeSchemaView streamTypeSchema(
    SharedTypeSchemaView elementTypeSchema,
  ) {
    return SharedTypeSchemaView(
      typeSystem.typeProvider.streamType(
        elementTypeSchema.unwrapTypeSchemaView<TypeImpl>(),
      ),
    );
  }

  @override
  SharedTypeView? tryPromoteToType(SharedTypeView to, SharedTypeView from) {
    var result = typeSystem.tryPromoteToType(
      to.unwrapTypeView<TypeImpl>(),
      from.unwrapTypeView<TypeImpl>(),
    );
    return result == null ? null : SharedTypeView(result);
  }

  @override
  SharedTypeSchemaView typeToSchema(SharedTypeView type) {
    return SharedTypeSchemaView(type.unwrapTypeView());
  }

  @override
  SharedTypeView variableType(PromotableElementImpl variable) {
    return SharedTypeView(variable.type);
  }

  @override
  PropertyNonPromotabilityReason? whyPropertyIsNotPromotable(
    covariant ExecutableElement property,
  ) {
    if (property.isPublic) return PropertyNonPromotabilityReason.isNotPrivate;
    if (property is! PropertyAccessorElement) {
      return PropertyNonPromotabilityReason.isNotField;
    }
    var field = property.variable;
    if (field is! FieldElement) {
      return PropertyNonPromotabilityReason.isNotField;
    }
    if (field.isSynthetic && !property.isSynthetic) {
      // The field is synthetic but not the property; this means that what was
      // declared by the user was the property (the getter).
      return PropertyNonPromotabilityReason.isNotField;
    }
    if (field.isPromotable) return null;
    if (field.isExternal) return PropertyNonPromotabilityReason.isExternal;
    if (!field.isFinal) return PropertyNonPromotabilityReason.isNotFinal;
    // Non-promotion reason must be due to a conflict with some other
    // declaration, or because field promotion is disabled.
    return null;
  }
}

/// The visitor that gathers local variables that are potentially assigned
/// in corresponding statements, such as loops, `switch` and `try`.
class _AssignedVariablesVisitor extends RecursiveAstVisitor<void> {
  final AssignedVariables<AstNode, PromotableElementImpl> assignedVariables;

  _AssignedVariablesVisitor(this.assignedVariables);

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    var element = node.element;
    if (element is PromotableElementImpl) {
      assignedVariables.write(element);
    }
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    var left = node.leftHandSide;

    super.visitAssignmentExpression(node);

    if (left is SimpleIdentifier) {
      var element = left.element;
      if (element is PromotableElementImpl) {
        assignedVariables.write(element);
      }
    }
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.type == TokenType.AMPERSAND_AMPERSAND) {
      node.leftOperand.accept(this);
      assignedVariables.beginNode();
      node.rightOperand.accept(this);
      assignedVariables.endNode(node);
    } else {
      super.visitBinaryExpression(node);
    }
  }

  @override
  void visitCatchClause(covariant CatchClauseImpl node) {
    for (var identifier in [
      node.exceptionParameter,
      node.stackTraceParameter,
    ]) {
      if (identifier != null) {
        assignedVariables.declare(identifier.declaredElement!);
      }
    }
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    node.condition.accept(this);
    assignedVariables.beginNode();
    node.thenExpression.accept(this);
    assignedVariables.endNode(node);
    node.elseExpression.accept(this);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    throw StateError('Should not visit top level declarations');
  }

  @override
  void visitDoStatement(DoStatement node) {
    assignedVariables.beginNode();
    super.visitDoStatement(node);
    assignedVariables.endNode(node);
  }

  @override
  void visitForElement(covariant ForElementImpl node) {
    _handleFor(node, node.forLoopParts, node.body);
  }

  @override
  void visitForStatement(covariant ForStatementImpl node) {
    _handleFor(node, node.forLoopParts, node.body);
  }

  @override
  void visitFunctionDeclaration(covariant FunctionDeclarationImpl node) {
    if (node.parent is CompilationUnit) {
      throw StateError('Should not visit top level declarations');
    }
    assignedVariables.beginNode();
    _declareParameters(node.functionExpression.parameters);
    super.visitFunctionDeclaration(node);
    assignedVariables.endNode(node, isClosureOrLateVariableInitializer: true);
  }

  @override
  void visitFunctionExpression(covariant FunctionExpressionImpl node) {
    if (node.parent is FunctionDeclaration) {
      // A FunctionExpression just inside a FunctionDeclaration is an analyzer
      // artifact--it doesn't correspond to a separate closure.  So skip our
      // usual processing.
      return super.visitFunctionExpression(node);
    }
    assignedVariables.beginNode();
    _declareParameters(node.parameters);
    super.visitFunctionExpression(node);
    assignedVariables.endNode(node, isClosureOrLateVariableInitializer: true);
  }

  @override
  void visitIfElement(covariant IfElementImpl node) {
    _visitIf(node);
  }

  @override
  void visitIfStatement(covariant IfStatementImpl node) {
    _visitIf(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    throw StateError('Should not visit top level declarations');
  }

  @override
  void visitPatternVariableDeclaration(
    covariant PatternVariableDeclarationImpl node,
  ) {
    for (var variable in node.elements) {
      assignedVariables.declare(variable);
    }
    super.visitPatternVariableDeclaration(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    super.visitPostfixExpression(node);
    if (node.operator.type.isIncrementOperator) {
      var operand = node.operand;
      if (operand is SimpleIdentifier) {
        var element = operand.element;
        if (element is PromotableElementImpl) {
          assignedVariables.write(element);
        }
      }
    }
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    super.visitPrefixExpression(node);
    if (node.operator.type.isIncrementOperator) {
      var operand = node.operand;
      if (operand is SimpleIdentifier) {
        var element = operand.element;
        if (element is PromotableElementImpl) {
          assignedVariables.write(element);
        }
      }
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    var element = node.element;
    if (element is PromotableElementImpl &&
        node.inGetterContext() &&
        node.parent is! FormalParameter &&
        node.parent is! CatchClause &&
        node.parent is! CommentReference) {
      assignedVariables.read(element);
    }
  }

  @override
  void visitSwitchExpression(covariant SwitchExpressionImpl node) {
    node.expression.accept(this);

    for (var case_ in node.cases) {
      var guardedPattern = case_.guardedPattern;
      var variables = guardedPattern.variables;
      for (var variable in variables.values) {
        assignedVariables.declare(variable);
      }
      case_.accept(this);
    }
  }

  @override
  void visitSwitchStatement(covariant SwitchStatementImpl node) {
    node.expression.accept(this);

    assignedVariables.beginNode();
    for (var group in node.memberGroups) {
      for (var member in group.members) {
        if (member is SwitchCaseImpl) {
          member.expression.accept(this);
        } else if (member is SwitchPatternCaseImpl) {
          var guardedPattern = member.guardedPattern;
          guardedPattern.pattern.accept(this);
          for (var variable in guardedPattern.variables.values) {
            assignedVariables.declare(variable);
          }
          guardedPattern.whenClause?.accept(this);
        }
      }
      for (var variable in group.variables.values) {
        // We pass `ignoreDuplicates: true` because this variable might be the
        // same as one of the variables declared earlier under a specific switch
        // case.
        assignedVariables.declare(variable, ignoreDuplicates: true);
      }
      group.statements.accept(this);
    }
    assignedVariables.endNode(node);
  }

  @override
  void visitTryStatement(TryStatement node) {
    var finallyBlock = node.finallyBlock;
    assignedVariables.beginNode(); // Begin info for [node].
    assignedVariables.beginNode(); // Begin info for [node.body].
    node.body.accept(this);
    assignedVariables.endNode(node.body);

    node.catchClauses.accept(this);
    assignedVariables.endNode(node);

    finallyBlock?.accept(this);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    var grandParent = node.parent!.parent;
    if (grandParent is TopLevelVariableDeclaration ||
        grandParent is FieldDeclaration) {
      throw StateError('Should not visit top level declarations');
    }
    var declaredElement = node.declaredElement as PromotableElementImpl;
    assignedVariables.declare(declaredElement);
    if (declaredElement.isLate && node.initializer != null) {
      assignedVariables.beginNode();
      super.visitVariableDeclaration(node);
      assignedVariables.endNode(node, isClosureOrLateVariableInitializer: true);
    } else {
      super.visitVariableDeclaration(node);
    }
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    assignedVariables.beginNode();
    super.visitWhileStatement(node);
    assignedVariables.endNode(node);
  }

  void _declareParameters(FormalParameterListImpl? parameters) {
    if (parameters == null) return;
    for (var parameter in parameters.parameters) {
      assignedVariables.declare(parameter.declaredFragment!.element);
    }
  }

  void _handleFor(AstNode node, ForLoopPartsImpl forLoopParts, AstNode body) {
    if (forLoopParts is ForPartsImpl) {
      if (forLoopParts is ForPartsWithExpressionImpl) {
        forLoopParts.initialization?.accept(this);
      } else if (forLoopParts is ForPartsWithDeclarationsImpl) {
        forLoopParts.variables.accept(this);
      } else if (forLoopParts is ForPartsWithPatternImpl) {
        forLoopParts.variables.accept(this);
      } else {
        throw StateError('Unrecognized for loop parts');
      }

      assignedVariables.beginNode();
      forLoopParts.condition?.accept(this);
      body.accept(this);
      forLoopParts.updaters.accept(this);
      assignedVariables.endNode(node);
    } else if (forLoopParts is ForEachPartsImpl) {
      var iterable = forLoopParts.iterable;

      iterable.accept(this);

      if (forLoopParts is ForEachPartsWithIdentifierImpl) {
        var element = forLoopParts.identifier.element;
        if (element is PromotableElementImpl) {
          assignedVariables.write(element);
        }
      } else if (forLoopParts is ForEachPartsWithDeclarationImpl) {
        var variable = forLoopParts.loopVariable.declaredElement!;
        assignedVariables.declare(variable);
      } else if (forLoopParts is ForEachPartsWithPatternImpl) {
        for (var variable in forLoopParts.variables) {
          assignedVariables.declare(variable.element);
        }
      } else {
        throw StateError('Unrecognized for loop parts');
      }
      assignedVariables.beginNode();
      body.accept(this);
      assignedVariables.endNode(node);
    } else {
      throw StateError('Unrecognized for loop parts');
    }
  }

  void _visitIf(IfElementOrStatementImpl node) {
    node.expression.accept(this);

    var caseClause = node.caseClause;
    if (caseClause != null) {
      var guardedPattern = caseClause.guardedPattern;
      assignedVariables.beginNode();
      for (var variable in guardedPattern.variables.values) {
        assignedVariables.declare(variable);
      }
      guardedPattern.whenClause?.accept(this);
      node.ifTrue.accept(this);
      assignedVariables.endNode(node);
      node.ifFalse?.accept(this);
    } else {
      assignedVariables.beginNode();
      node.ifTrue.accept(this);
      assignedVariables.endNode(node);
      node.ifFalse?.accept(this);
    }
  }
}

/// The flow analysis based implementation of [LocalVariableTypeProvider].
class _LocalVariableTypeProvider implements LocalVariableTypeProvider {
  final FlowAnalysisHelper _manager;

  _LocalVariableTypeProvider(this._manager);

  @override
  TypeImpl getType(SimpleIdentifierImpl node, {required bool isRead}) {
    var variable = node.element as InternalVariableElement;
    if (variable is PromotableElementImpl) {
      var promotedType =
          isRead
              ? _manager.flow?.variableRead(node, variable)
              : _manager.flow?.promotedType(variable);
      if (promotedType != null) {
        return promotedType.unwrapTypeView<TypeImpl>();
      }
    }
    return variable.type;
  }
}
