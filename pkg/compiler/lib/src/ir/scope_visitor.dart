// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as ir;
import 'package:kernel/core_types.dart' as ir;
import 'package:kernel/type_environment.dart' as ir;

import 'closure.dart';
import 'scope.dart';

/// This builder walks the code to determine what variables are
/// assigned/captured/free at various points to build a [ClosureScopeModel] and
/// a [VariableScopeModel] that can respond to queries about how a particular
/// variable is being used at any point in the code.
class ScopeModelBuilder extends ir.VisitorDefault<EvaluationComplexity>
    with VariableCollectorMixin, ir.VisitorThrowingMixin<EvaluationComplexity> {
  final ir.TypeEnvironment _typeEnvironment;
  ir.CoreTypes get _coreTypes => _typeEnvironment.coreTypes;

  final ClosureScopeModel _model = ClosureScopeModel();

  /// A map of each visited call node with the associated information about what
  /// variables are captured/used. Each ir.Node key corresponds to a scope that
  /// was encountered while visiting a closure (initially called through
  /// [translateLazyInitializer] or [translateConstructorOrProcedure]).
  Map<ir.Node, KernelCapturedScope> get _scopesCapturedInClosureMap =>
      _model.capturedScopesMap;

  /// A map of the nodes that we have flagged as necessary to generate closure
  /// classes for in a later stage. We map that node to information ascertained
  /// about variable usage in the surrounding scope.
  Map<ir.TreeNode, KernelScopeInfo> get _closuresToGenerate =>
      _model.closuresToGenerate;

  /// The local variables that have been declared in the current scope.
  // Initialized to a const value since it should be assigned in `enterNewScope`
  // before collecting variables.
  List<ir.Node /* ir.VariableDeclaration | TypeParameterTypeWithContext */>
  _scopeVariables = const [];

  /// Pointer to the context in which this closure is executed.
  /// For example, in the expression `var foo = () => 3 + i;`, the executable
  /// context as we walk the nodes in that expression is the ir.Field `foo`.
  ir.TreeNode? _executableContext;

  /// A flag to indicate if we are currently inside a closure.
  bool _isInsideClosure = false;

  /// Pointer to the original node where this closure builder started.
  ir.TreeNode? _outermostNode;

  /// Keep track of the mutated local variables so that we don't need to box
  /// non-mutated variables. We know these are only VariableDeclarations because
  /// type variable types and `this` types can't be mutated!
  final Set<ir.VariableDeclaration> _mutatedVariables = {};

  /// The set of variables that are accessed in some form, whether they are
  /// mutated or not.
  final Set<ir.Node /* ir.VariableDeclaration | TypeParameterTypeWithContext */>
  _capturedVariables = <ir.Node>{};

  /// If true, the visitor is currently traversing some nodes that are inside a
  /// try block.
  bool _inTry = false;

  /// The current scope we are in.
  KernelScopeInfo? __currentScopeInfo;
  KernelScopeInfo get _currentScopeInfo => __currentScopeInfo!;

  bool _hasThisLocal = false;

  /// Keeps track of the number of boxes that we've created so that they each
  /// have unique names.
  int _boxCounter = 0;

  /// The current usage of a type annotation.
  ///
  /// This is updated in the visitor to distinguish between unconditional
  /// type variable usage, such as type literals and is tests, and conditional
  /// type variable usage, such as type argument in method invocations.
  VariableUse? _currentTypeUsage;

  ScopeModelBuilder(this._typeEnvironment);

  ScopeModel computeModel(ir.Member node) {
    if (node.isAbstract && !node.isExternal) {
      return const ScopeModel(
        initializerComplexity: EvaluationComplexity.lazy(),
      );
    }

    if (node is ir.Constructor) {
      _hasThisLocal = true;
    } else if (node is ir.Procedure && node.kind == ir.ProcedureKind.Factory) {
      _hasThisLocal = false;
    } else if (node.isInstanceMember) {
      _hasThisLocal = true;
    } else {
      _hasThisLocal = false;
    }

    EvaluationComplexity initializerComplexity =
        const EvaluationComplexity.lazy();
    if (node is ir.Field) {
      if (node.initializer != null) {
        initializerComplexity = node.accept(this);
      } else {
        initializerComplexity = const EvaluationComplexity.constant();
        _model.scopeInfo = KernelScopeInfo(_hasThisLocal);
      }
    } else {
      assert(node is ir.Procedure || node is ir.Constructor);
      if (!(node is ir.Procedure && node.isRedirectingFactory)) {
        // Skip redirecting factories: they contain invalid expressions only
        // used to support internal CFE modular compilation.
        node.accept(this);
      }
    }
    return ScopeModel(
      closureScopeModel: _model,
      variableScopeModel: variableScopeModel,
      initializerComplexity: initializerComplexity,
    );
  }

  @override
  EvaluationComplexity defaultNode(ir.Node node) =>
      throw UnsupportedError('Unhandled node $node (${node.runtimeType})');

  EvaluationComplexity visitNode(ir.Node node) {
    return node.accept(this);
  }

  /// Tries to extract the constant expression from a node.
  ///
  /// If it succeeds, an [EvaluationComplexity] containing the new
  /// constant is returned. Otherwise a 'lazy' [EvaluationComplexity] is
  /// returned, signaling that [node] is not a constant expression.
  ///
  /// This method should be called in the visit methods of all expressions that
  /// could potentially be constant to bubble up the constness of expressions.
  EvaluationComplexity _evaluateImplicitConstant(ir.Expression node) {
    ir.Constant? constant = (node is ir.ConstantExpression)
        ? node.constant
        : null;
    if (constant != null) {
      return EvaluationComplexity.constant(constant);
    }
    return const EvaluationComplexity.lazy();
  }

  /// Visit all [nodes] returning the combined complexity.
  EvaluationComplexity visitNodes(List<ir.Node> nodes) {
    EvaluationComplexity complexity = const EvaluationComplexity.constant();
    for (ir.Node node in nodes) {
      complexity = complexity.combine(visitNode(node));
    }
    return complexity;
  }

  /// Visit all [nodes] returning the combined complexity.
  ///
  /// Assumes that the Kernel AST already contains simplified constant and
  /// constant-like expressions.
  EvaluationComplexity visitExpressions(List<ir.Expression> nodes) {
    EvaluationComplexity combinedComplexity =
        const EvaluationComplexity.constant();
    for (int i = 0; i < nodes.length; i++) {
      final complexity = visitNode(nodes[i]);
      combinedComplexity = combinedComplexity.combine(complexity);
    }
    return combinedComplexity;
  }

  EvaluationComplexity visitNamedExpressions(
    List<ir.NamedExpression> named,
    EvaluationComplexity combinedComplexity,
  ) {
    for (int i = 0; i < named.length; i++) {
      final complexity = visitNode(named[i].value);
      combinedComplexity = combinedComplexity.combine(complexity);
    }
    return combinedComplexity;
  }

  /// Update the [CapturedScope] object corresponding to
  /// this node if any variables are captured.
  void attachCapturedScopeVariables(ir.TreeNode node) {
    Set<ir.VariableDeclaration> capturedVariablesForScope =
        <ir.VariableDeclaration>{};

    for (ir.Node variable in _scopeVariables) {
      // No need to box non-assignable elements.
      if (variable is ir.VariableDeclaration) {
        if (variable.isConst) continue;
        if (!_mutatedVariables.contains(variable)) continue;
        if (_capturedVariables.contains(variable)) {
          capturedVariablesForScope.add(variable);
        }
      }
    }
    if (capturedVariablesForScope.isNotEmpty) {
      assert(_model.scopeInfo != null);
      KernelScopeInfo from = _model.scopeInfo!;

      KernelCapturedScope capturedScope;
      var nodeBox = NodeBox(getBoxName(), _executableContext!);
      if (node is ir.LoopStatement) {
        capturedScope = KernelCapturedLoopScope(
          capturedVariablesForScope,
          nodeBox,
          [],
          from.localsUsedInTryOrSync,
          from.freeVariables,
          from.freeVariablesForRti,
          from.thisUsedAsFreeVariable,
          from.thisUsedAsFreeVariableIfNeedsRti,
          _hasThisLocal,
        );
      } else {
        capturedScope = KernelCapturedScope(
          capturedVariablesForScope,
          nodeBox,
          from.localsUsedInTryOrSync,
          from.freeVariables,
          from.freeVariablesForRti,
          from.thisUsedAsFreeVariable,
          from.thisUsedAsFreeVariableIfNeedsRti,
          _hasThisLocal,
        );
      }
      _model.scopeInfo = _scopesCapturedInClosureMap[node] = capturedScope;
    }
  }

  /// Generate a unique name for the [_boxCounter]th box field.
  ///
  /// The result is used as the name of [NodeBox]s and [BoxLocal]s, and must
  /// therefore be unique to avoid breaking an invariant in the element model
  /// (classes cannot declare multiple fields with the same name).
  ///
  /// Also, the names should be distinct from real field names to prevent
  /// clashes with selectors for those fields.
  ///
  /// These names are not used in generated code, just as element name.
  String getBoxName() {
    return "_box_${_boxCounter++}";
  }

  /// Perform book-keeping with the current set of local variables that have
  /// been seen thus far before entering this new scope.
  void enterNewScope(ir.TreeNode node, void Function() visitNewScope) {
    List<ir.Node> oldScopeVariables = _scopeVariables;
    _scopeVariables = <ir.Node>[];
    visitNewScope();
    attachCapturedScopeVariables(node);
    _mutatedVariables.removeAll(_scopeVariables);
    _scopeVariables = oldScopeVariables;
  }

  @override
  EvaluationComplexity visitNamedExpression(ir.NamedExpression node) {
    throw UnsupportedError(
      'NamedExpression should be handled through visitArguments',
    );
  }

  @override
  EvaluationComplexity visitTryCatch(ir.TryCatch node) {
    bool oldInTry = _inTry;
    _inTry = true;
    visitInVariableScope(node, () {
      visitNode(node.body);
    });
    visitNodes(node.catches);
    _inTry = oldInTry;
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitTryFinally(ir.TryFinally node) {
    bool oldInTry = _inTry;
    _inTry = true;
    visitInVariableScope(node, () {
      visitNode(node.body);
    });
    visitNode(node.finalizer);
    _inTry = oldInTry;
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitVariableGet(ir.VariableGet node) {
    _markVariableAsUsed(node.variable, SimpleVariableUse.explicit);
    // Don't visit `node.promotedType`.
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitVariableSet(ir.VariableSet node) {
    _mutatedVariables.add(node.variable);
    _markVariableAsUsed(node.variable, SimpleVariableUse.explicit);
    visitInContext(node.variable.type, SimpleVariableUse.localType);
    visitNode(node.value);
    registerAssignedVariable(node.variable);
    return const EvaluationComplexity.lazy();
  }

  void _handleVariableDeclaration(
    ir.VariableDeclaration node,
    VariableUse usage,
  ) {
    if (!node.isInitializingFormal) {
      _scopeVariables.add(node);
    }

    visitInContext(node.type, usage);
    if (node.initializer != null) {
      visitNode(node.initializer!);
    }
  }

  @override
  EvaluationComplexity visitVariableDeclaration(ir.VariableDeclaration node) {
    _handleVariableDeclaration(node, SimpleVariableUse.localType);
    return const EvaluationComplexity.lazy();
  }

  /// Add this variable to the set of free variables if appropriate and add to
  /// the tally of variables used in try or sync blocks.
  /// If [onlyForRtiChecks] is true, add to the freeVariablesForRti set instead
  /// of freeVariables as we will only use it if runtime type information is
  /// checked.
  void _markVariableAsUsed(
    ir.Node /* VariableDeclaration | TypeParameterTypeWithContext */ variable,
    VariableUse usage,
  ) {
    assert(
      variable is ir.VariableDeclaration ||
          variable is TypeVariableTypeWithContext,
    );
    if (_isInsideClosure && !_inCurrentContext(variable)) {
      // If the element is not declared in the current function and the element
      // is not the closure itself we need to mark the element as free variable.
      // Note that the check on [insideClosure] is not just an
      // optimization: factories have type parameters as function
      // parameters, and type parameters are declared in the class, not
      // the factory.
      if (usage == SimpleVariableUse.explicit) {
        _currentScopeInfo.freeVariables.add(variable);
      } else {
        _currentScopeInfo.freeVariablesForRti
            .putIfAbsent(
              variable as TypeVariableTypeWithContext,
              () => <VariableUse>{},
            )
            .add(usage);
      }
    }
    if (_inTry && variable is ir.VariableDeclaration) {
      _currentScopeInfo.localsUsedInTryOrSync.add(variable);
    }
  }

  @override
  EvaluationComplexity visitThisExpression(ir.ThisExpression node) {
    if (_hasThisLocal) {
      _registerNeedsThis(SimpleVariableUse.explicit);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitTypeParameter(ir.TypeParameter node) {
    TypeVariableTypeWithContext typeVariable(ir.Library library) =>
        TypeVariableTypeWithContext(
          ir.TypeParameterType.withDefaultNullability(node),
          // If this typeParameter is part of a function type then its
          // declaration is null because it has no context. Just pass in null
          // for the context in that case.
          node.declaration,
        );

    ir.TreeNode? context = _executableContext;
    if (_isInsideClosure && context is ir.Procedure && context.isFactory) {
      // This is a closure in a factory constructor.  Since there is no
      // [:this:], we have to mark the type arguments as free variables to
      // capture them in the closure.
      _useTypeVariableAsLocal(
        typeVariable(context.enclosingLibrary),
        _currentTypeUsage!,
      );
    }

    if (context is ir.Member && context is! ir.Field) {
      // In checked mode, using a type variable in a type annotation may lead
      // to a runtime type check that needs to access the type argument and
      // therefore the closure needs a this-element, if it is not in a field
      // initializer; field initializers are evaluated in a context where
      // the type arguments are available in locals.

      if (_hasThisLocal) {
        _registerNeedsThis(_currentTypeUsage!);
      } else {
        _useTypeVariableAsLocal(
          typeVariable(context.enclosingLibrary),
          _currentTypeUsage!,
        );
      }
    }

    visitNode(node.bound);

    return const EvaluationComplexity.constant();
  }

  @override
  EvaluationComplexity visitStructuralParameter(ir.StructuralParameter node) {
    // Visit the default type to register any necessary type parameters that RTI
    // might need if the associated function is used as a generic tear off.
    visitNode(node.defaultType);
    return const EvaluationComplexity.constant();
  }

  /// Add `this` as a variable that needs to be accessed (and thus may become a
  /// free/captured variable.
  /// If [onlyIfNeedsRti] is true, set thisUsedAsFreeVariableIfNeedsRti to true
  /// instead of thisUsedAsFreeVariable as we will only use `this` if runtime
  /// type information is checked.
  void _registerNeedsThis(VariableUse usage) {
    if (_isInsideClosure) {
      if (usage == SimpleVariableUse.explicit) {
        _currentScopeInfo.thisUsedAsFreeVariable = true;
      } else {
        _currentScopeInfo.thisUsedAsFreeVariableIfNeedsRti.add(usage);
      }
    }
  }

  @override
  EvaluationComplexity visitForInStatement(ir.ForInStatement node) {
    // We need to set `inTry` to true if this is an async for-in because we
    // desugar it into a try-finally in the SSA phase.
    bool oldInTry = _inTry;
    if (node.isAsync) {
      _inTry = true;
    }
    enterNewScope(node, () {
      visitNode(node.variable);
      if (node.isAsync) {
        // If this is async then the type is explicitly used to instantiate
        // the underlying StreamIterator.
        visitInContext(
          node.variable.type,
          ConstructorTypeArgumentVariableUse(
            _coreTypes.streamIteratorDefaultConstructor,
          ),
        );
      }
      visitInVariableScope(node, () {
        visitNode(node.iterable);
        visitNode(node.body);
      });
    });
    if (node.isAsync) {
      _inTry = oldInTry;
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitWhileStatement(ir.WhileStatement node) {
    enterNewScope(node, () {
      visitInVariableScope(node, () {
        visitNode(node.condition);
        visitNode(node.body);
      });
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitDoStatement(ir.DoStatement node) {
    enterNewScope(node, () {
      visitInVariableScope(node, () {
        visitNode(node.body);
        visitNode(node.condition);
      });
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitForStatement(ir.ForStatement node) {
    List<ir.VariableDeclaration> boxedLoopVariables =
        <ir.VariableDeclaration>[];
    enterNewScope(node, () {
      // First visit initialized variables and update steps so we can easily
      // check if a loop variable was captured in one of these subexpressions.
      visitNodes(node.variables);
      visitInVariableScope(node, () {
        visitExpressions(node.updates);
      });

      // Loop variables that have not been captured yet can safely be flagged as
      // non-mutated, because no nested function can observe the mutation.
      for (ir.VariableDeclaration variable in node.variables) {
        if (!_capturedVariables.contains(variable)) {
          _mutatedVariables.remove(variable);
        }
      }

      // Visit condition and body.
      // This must happen after the above, so any loop variables mutated in the
      // condition or body are indeed flagged as mutated.
      visitInVariableScope(node, () {
        if (node.condition != null) {
          visitNode(node.condition!);
        }
        visitNode(node.body);
      });

      // See if we have declared loop variables that need to be boxed.
      for (ir.VariableDeclaration variable in node.variables) {
        // Non-mutated variables should not be boxed.  The _mutatedVariables set
        // gets cleared when `enterNewScope` returns, so check it here.
        if (_capturedVariables.contains(variable) &&
            _mutatedVariables.contains(variable)) {
          boxedLoopVariables.add(variable);
        }
      }
    });
    KernelCapturedScope? scope = _scopesCapturedInClosureMap[node];
    if (scope != null) {
      _scopesCapturedInClosureMap[node] = KernelCapturedLoopScope(
        scope.boxedVariables,
        scope.capturedVariablesAccessor,
        boxedLoopVariables,
        scope.localsUsedInTryOrSync,
        scope.freeVariables,
        scope.freeVariablesForRti,
        scope.thisUsedAsFreeVariable,
        scope.thisUsedAsFreeVariableIfNeedsRti,
        scope.hasThisLocal,
      );
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitSuperMethodInvocation(
    ir.SuperMethodInvocation node,
  ) {
    if (_hasThisLocal) {
      _registerNeedsThis(SimpleVariableUse.explicit);
    }
    if (node.arguments.types.isNotEmpty) {
      visitNodesInContext(
        node.arguments.types,
        StaticTypeArgumentVariableUse(node.interfaceTarget),
      );
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitSuperPropertySet(ir.SuperPropertySet node) {
    if (_hasThisLocal) {
      _registerNeedsThis(SimpleVariableUse.explicit);
    }
    visitNode(node.value);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitSuperPropertyGet(ir.SuperPropertyGet node) {
    if (_hasThisLocal) {
      _registerNeedsThis(SimpleVariableUse.explicit);
    }
    return const EvaluationComplexity.lazy();
  }

  void visitInvokable(ir.TreeNode node, void Function() f) {
    assert(node is ir.Member || node is ir.LocalFunction);
    bool oldIsInsideClosure = _isInsideClosure;
    ir.TreeNode? oldExecutableContext = _executableContext;
    KernelScopeInfo? oldScopeInfo = __currentScopeInfo;

    // _outermostNode is only null the first time we enter the body of the
    // field, constructor, or method that is being analyzed.
    _isInsideClosure = _outermostNode != null;
    _executableContext = node;

    __currentScopeInfo = KernelScopeInfo(_hasThisLocal);

    if (_isInsideClosure) {
      _closuresToGenerate[node] = _currentScopeInfo;
    } else {
      _outermostNode = node;
      _model.scopeInfo = _currentScopeInfo;
    }

    enterNewScope(node, f);

    KernelScopeInfo savedScopeInfo = _currentScopeInfo;
    bool savedIsInsideClosure = _isInsideClosure;

    // Restore old values.
    _isInsideClosure = oldIsInsideClosure;
    __currentScopeInfo = oldScopeInfo;
    _executableContext = oldExecutableContext;

    // Mark all free variables as captured and expect to encounter them in the
    // outer function.
    Iterable<ir.Node> freeVariables = savedScopeInfo.freeVariables;
    assert(freeVariables.isEmpty || savedIsInsideClosure);
    for (ir.Node freeVariable in freeVariables) {
      _capturedVariables.add(freeVariable);
      _markVariableAsUsed(freeVariable, SimpleVariableUse.explicit);
    }
    savedScopeInfo.freeVariablesForRti.forEach((
      TypeVariableTypeWithContext freeVariableForRti,
      Set<VariableUse> useSet,
    ) {
      for (VariableUse usage in useSet) {
        _markVariableAsUsed(freeVariableForRti, usage);
      }
    });
    if (_isInsideClosure && savedScopeInfo.thisUsedAsFreeVariable) {
      _currentScopeInfo.thisUsedAsFreeVariable = true;
    }
    if (_isInsideClosure) {
      _currentScopeInfo.thisUsedAsFreeVariableIfNeedsRti.addAll(
        savedScopeInfo.thisUsedAsFreeVariableIfNeedsRti,
      );
    }
  }

  /// Return true if [variable]'s context is the same as the current executable
  /// context.
  bool _inCurrentContext(ir.Node variable) {
    assert(
      variable is ir.VariableDeclaration ||
          variable is TypeVariableTypeWithContext,
    );
    if (variable is TypeVariableTypeWithContext) {
      return variable.context == _executableContext;
    }
    ir.TreeNode? node = variable as ir.TreeNode;
    while (node != _outermostNode && node != _executableContext) {
      node = node!.parent;
    }
    return node == _executableContext;
  }

  @override
  EvaluationComplexity visitField(ir.Field node) {
    _currentTypeUsage = SimpleVariableUse.fieldType;
    late final EvaluationComplexity complexity;
    visitInvokable(node, () {
      assert(node.initializer != null);
      complexity = visitNode(node.initializer!);
    });
    _currentTypeUsage = null;
    return complexity;
  }

  @override
  EvaluationComplexity visitConstructor(ir.Constructor node) {
    visitInvokable(node, () {
      visitNodes(node.initializers);
      visitNode(node.function);
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitProcedure(ir.Procedure node) {
    visitInvokable(node, () {
      visitNode(node.function);
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitFunctionExpression(ir.FunctionExpression node) {
    visitInvokable(node, () {
      visitInVariableScope(node, () {
        visitNode(node.function);
      });
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitFunctionDeclaration(ir.FunctionDeclaration node) {
    visitInvokable(node, () {
      visitInVariableScope(node, () {
        visitNode(node.function);
      });
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitDynamicType(ir.DynamicType node) =>
      const EvaluationComplexity.constant();

  @override
  EvaluationComplexity visitNeverType(ir.NeverType node) =>
      const EvaluationComplexity.lazy();

  @override
  EvaluationComplexity visitNullType(ir.NullType node) =>
      const EvaluationComplexity.lazy();

  @override
  EvaluationComplexity visitInvalidType(ir.InvalidType node) =>
      const EvaluationComplexity.lazy();

  @override
  EvaluationComplexity visitVoidType(ir.VoidType node) =>
      const EvaluationComplexity.constant();

  @override
  EvaluationComplexity visitInterfaceType(ir.InterfaceType node) {
    return visitNodes(node.typeArguments);
  }

  @override
  EvaluationComplexity visitRecordType(ir.RecordType node) {
    EvaluationComplexity complexity = visitNodes(node.positional);
    return complexity.combine(visitNodes(node.named));
  }

  @override
  EvaluationComplexity visitFutureOrType(ir.FutureOrType node) {
    return visitNode(node.typeArgument);
  }

  @override
  EvaluationComplexity visitFunctionType(ir.FunctionType node) {
    EvaluationComplexity complexity = visitNode(node.returnType);
    complexity = complexity.combine(visitNodes(node.positionalParameters));
    complexity = complexity.combine(visitNodes(node.namedParameters));
    return complexity.combine(visitNodes(node.typeParameters));
  }

  @override
  EvaluationComplexity visitNamedType(ir.NamedType node) {
    return visitNode(node.type);
  }

  @override
  EvaluationComplexity visitTypeParameterType(ir.TypeParameterType node) {
    _analyzeTypeVariable(node, _currentTypeUsage!);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitStructuralParameterType(
    ir.StructuralParameterType node,
  ) {
    // The type variable is a function type variable, like `T` in
    //
    //     List<void Function<T>(T)> list;
    //
    // which doesn't correspond to a captured local variable.
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitIntersectionType(ir.IntersectionType node) {
    _analyzeTypeVariable(node.left, _currentTypeUsage!);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitExtensionType(ir.ExtensionType node) {
    return visitNode(node.extensionTypeErasure);
  }

  EvaluationComplexity visitInContext(ir.Node node, VariableUse use) {
    VariableUse? oldCurrentTypeUsage = _currentTypeUsage;
    _currentTypeUsage = use;
    EvaluationComplexity complexity = visitNode(node);
    _currentTypeUsage = oldCurrentTypeUsage;
    return complexity;
  }

  EvaluationComplexity visitNodesInContext(
    List<ir.Node> nodes,
    VariableUse use,
  ) {
    VariableUse? oldCurrentTypeUsage = _currentTypeUsage;
    _currentTypeUsage = use;
    EvaluationComplexity complexity = visitNodes(nodes);
    _currentTypeUsage = oldCurrentTypeUsage;
    return complexity;
  }

  @override
  EvaluationComplexity visitTypeLiteral(ir.TypeLiteral node) {
    visitInContext(node.type, SimpleVariableUse.explicit);
    return _evaluateImplicitConstant(node);
  }

  @override
  EvaluationComplexity visitIsExpression(ir.IsExpression node) {
    EvaluationComplexity complexity = visitNode(node.operand);
    visitInContext(node.type, SimpleVariableUse.explicit);
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitAsExpression(ir.AsExpression node) {
    EvaluationComplexity complexity = visitNode(node.operand);
    visitInContext(
      node.type,
      node.isTypeError
          ? SimpleVariableUse.implicitCast
          : SimpleVariableUse.explicit,
    );
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitNullCheck(ir.NullCheck node) {
    EvaluationComplexity complexity = visitNode(node.operand);
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitAwaitExpression(ir.AwaitExpression node) {
    visitNode(node.operand);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitYieldStatement(ir.YieldStatement node) {
    visitNode(node.expression);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitLoadLibrary(ir.LoadLibrary node) {
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitCheckLibraryIsLoaded(ir.CheckLibraryIsLoaded node) {
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitFunctionNode(ir.FunctionNode node) {
    final parent = node.parent;
    VariableUse parameterUsage = parent is ir.Member
        ? MemberParameterVariableUse(parent)
        : LocalParameterVariableUse(parent as ir.LocalFunction);
    visitNodesInContext(node.typeParameters, parameterUsage);
    for (ir.VariableDeclaration declaration in node.positionalParameters) {
      _handleVariableDeclaration(declaration, parameterUsage);
    }
    for (ir.VariableDeclaration declaration in node.namedParameters) {
      _handleVariableDeclaration(declaration, parameterUsage);
    }
    visitInContext(
      node.returnType,
      parent is ir.Member
          ? MemberReturnTypeVariableUse(parent)
          : LocalReturnTypeVariableUse(parent as ir.LocalFunction),
    );
    if (node.body != null) {
      visitNode(node.body!);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitListLiteral(ir.ListLiteral node) {
    EvaluationComplexity complexity = visitInContext(
      node.typeArgument,
      SimpleVariableUse.listLiteral,
    );
    complexity = complexity.combine(visitExpressions(node.expressions));
    if (node.isConst) {
      return const EvaluationComplexity.constant();
    }
    if (complexity.isLazy) return complexity;
    // TODO(45681): Refine heuristic to count operations in the whole
    // initializer. Lists are not expensive to eagerly initialize, but the could
    // contain something expensive (e.g. a big list of many small maps would be
    // slightly more expensive than a big map of similar size).
    return complexity.makeEager();
  }

  @override
  EvaluationComplexity visitSetLiteral(ir.SetLiteral node) {
    EvaluationComplexity complexity = visitInContext(
      node.typeArgument,
      SimpleVariableUse.setLiteral,
    );
    complexity = complexity.combine(visitExpressions(node.expressions));
    if (node.isConst) {
      return const EvaluationComplexity.constant();
    }
    if (complexity.isLazy) return complexity;
    // TODO(45681): Refine heuristic to count operations in whole initializer.
    if (node.expressions.length > 10) return const EvaluationComplexity.lazy();
    if (node.expressions.every(_isWellBehavedEagerHashKey)) {
      // Includes empty set literals.
      return complexity.makeEager();
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitMapLiteral(ir.MapLiteral node) {
    EvaluationComplexity complexity = visitInContext(
      node.keyType,
      SimpleVariableUse.mapLiteral,
    );
    complexity = complexity.combine(
      visitInContext(node.valueType, SimpleVariableUse.mapLiteral),
    );
    complexity = complexity.combine(visitNodes(node.entries));
    if (node.isConst) {
      return const EvaluationComplexity.constant();
    }
    if (complexity.isLazy) return complexity;
    // TODO(45681): Refine heuristic to count operations in whole initializer.
    if (node.entries.length > 10) return const EvaluationComplexity.lazy();
    if (node.entries
        .map((entry) => entry.key)
        .every(_isWellBehavedEagerHashKey)) {
      // Includes empty map literals.
      return complexity.makeEager();
    }
    return const EvaluationComplexity.lazy();
  }

  bool _isWellBehavedEagerHashKey(ir.Expression key) {
    // Well-behaved eager keys for LinkedHashMap and LinkedHashSet must not
    // indirectly use any lazy-initialized variables, e.g. by calling a
    // user-defined `get:hashCode` or `operator==`.
    //
    // TODO(45681): Improve the analysis. (1) Use static type of the [key]
    // expression. (2) Use information about the class hierarchy and overloading
    // of `get:hashCode` to detect safe implementations. This will pick up a lot
    // of enum and enum-like classes.
    if (key is ir.ConstantExpression) {
      if (key.constant is ir.StringConstant) return true;
      if (key.constant is ir.IntConstant) return true;
      if (key.constant is ir.DoubleConstant) return true;
      if (key.constant is ir.StaticTearOffConstant) return true;
    }
    return false;
  }

  @override
  EvaluationComplexity visitMapLiteralEntry(ir.MapLiteralEntry node) {
    EvaluationComplexity keyComplexity = visitNode(node.key);
    EvaluationComplexity valueComplexity = visitNode(node.value);

    return keyComplexity.combine(valueComplexity);
  }

  @override
  EvaluationComplexity visitRecordLiteral(ir.RecordLiteral node) {
    EvaluationComplexity complexity = visitExpressions(node.positional);
    complexity = visitNamedExpressions(node.named, complexity);
    if (complexity.isConstant) return _evaluateImplicitConstant(node);
    return complexity;
  }

  @override
  EvaluationComplexity visitNullLiteral(ir.NullLiteral node) =>
      _evaluateImplicitConstant(node);

  @override
  EvaluationComplexity visitStringLiteral(ir.StringLiteral node) =>
      _evaluateImplicitConstant(node);

  @override
  EvaluationComplexity visitIntLiteral(ir.IntLiteral node) =>
      _evaluateImplicitConstant(node);

  @override
  EvaluationComplexity visitDoubleLiteral(ir.DoubleLiteral node) =>
      _evaluateImplicitConstant(node);

  @override
  EvaluationComplexity visitSymbolLiteral(ir.SymbolLiteral node) =>
      _evaluateImplicitConstant(node);

  @override
  EvaluationComplexity visitBoolLiteral(ir.BoolLiteral node) =>
      _evaluateImplicitConstant(node);

  @override
  EvaluationComplexity visitStringConcatenation(ir.StringConcatenation node) {
    EvaluationComplexity complexity = visitExpressions(node.expressions);
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return complexity;
  }

  @override
  EvaluationComplexity visitStaticGet(ir.StaticGet node) {
    ir.Member target = node.target;
    if (target is ir.Field) {
      return target.isConst
          ? const EvaluationComplexity.constant()
          : EvaluationComplexity.eager(fields: <ir.Field>{target});
    } else if (target is ir.Procedure &&
        target.kind == ir.ProcedureKind.Method) {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitStaticTearOff(ir.StaticTearOff node) {
    return _evaluateImplicitConstant(node);
  }

  @override
  EvaluationComplexity visitStaticSet(ir.StaticSet node) {
    visitNode(node.value);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitStaticInvocation(ir.StaticInvocation node) {
    if (node.arguments.types.isNotEmpty) {
      VariableUse usage;
      if (node.target.kind == ir.ProcedureKind.Factory) {
        usage = ConstructorTypeArgumentVariableUse(node.target);
      } else {
        usage = StaticTypeArgumentVariableUse(node.target);
      }

      visitNodesInContext(node.arguments.types, usage);
    }

    EvaluationComplexity complexity = visitArguments(node.arguments);
    if (complexity.isConstant && node.target == _coreTypes.identicalProcedure) {
      return _evaluateImplicitConstant(node);
    }
    return node.isConst
        ? const EvaluationComplexity.constant()
        : const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitArguments(ir.Arguments node) {
    EvaluationComplexity combinedComplexity = visitExpressions(node.positional);
    combinedComplexity = visitNamedExpressions(node.named, combinedComplexity);
    return combinedComplexity;
  }

  @override
  EvaluationComplexity visitConstructorInvocation(
    ir.ConstructorInvocation node,
  ) {
    ir.Constructor target = node.target;
    ir.Class enclosingClass = target.enclosingClass;

    // TODO(45681): Investigate if other initializers should be made eager.

    // Lazily constructing cells pessimizes certain uses of late variables, so
    // we ensure they get constructed eagerly.
    if (enclosingClass == _coreTypes.cellClass) {
      return EvaluationComplexity.eager();
    }

    if (node.arguments.types.isNotEmpty) {
      visitNodesInContext(
        node.arguments.types,
        ConstructorTypeArgumentVariableUse(target),
      );
    }
    visitArguments(node.arguments);
    return node.isConst
        ? const EvaluationComplexity.constant()
        : const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitConditionalExpression(
    ir.ConditionalExpression node,
  ) {
    EvaluationComplexity conditionComplexity = visitNode(node.condition);

    EvaluationComplexity thenComplexity = visitNode(node.then);

    EvaluationComplexity elseComplexity = visitNode(node.otherwise);

    EvaluationComplexity complexity = conditionComplexity
        .combine(thenComplexity)
        .combine(elseComplexity);
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    // Don't visit `node.staticType`.
    return complexity;
  }

  @override
  EvaluationComplexity visitInstanceInvocation(ir.InstanceInvocation node) {
    EvaluationComplexity receiverComplexity = visitNode(node.receiver);
    if (node.arguments.types.isNotEmpty) {
      ir.TreeNode receiver = node.receiver;
      assert(
        !(receiver is ir.VariableGet &&
            receiver.variable.parent is ir.LocalFunction),
        "Unexpected local function invocation $node "
        "(${node.runtimeType}).",
      );
      final usage = InstanceTypeArgumentVariableUse(node);
      visitNodesInContext(node.arguments.types, usage);
    }
    EvaluationComplexity complexity = visitArguments(node.arguments);
    ir.Member interfaceTarget = node.interfaceTarget;
    if (receiverComplexity.combine(complexity).isConstant &&
        interfaceTarget is ir.Procedure &&
        interfaceTarget.kind == ir.ProcedureKind.Operator) {
      // Only operator invocations can be part of constant expressions so we
      // only try to compute an implicit constant when the receiver and all
      // arguments are constant - and are used in an operator call.
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitInstanceGetterInvocation(
    ir.InstanceGetterInvocation node,
  ) {
    visitNode(node.receiver);
    if (node.arguments.types.isNotEmpty) {
      ir.TreeNode receiver = node.receiver;
      assert(
        !(receiver is ir.VariableGet &&
            receiver.variable.parent is ir.LocalFunction),
        "Unexpected local function invocation $node "
        "(${node.runtimeType}).",
      );
      final usage = InstanceTypeArgumentVariableUse(node);
      visitNodesInContext(node.arguments.types, usage);
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitDynamicInvocation(ir.DynamicInvocation node) {
    visitNode(node.receiver);
    if (node.arguments.types.isNotEmpty) {
      ir.TreeNode receiver = node.receiver;
      assert(
        !(receiver is ir.VariableGet &&
            receiver.variable.parent is ir.LocalFunction),
        "Unexpected local function invocation $node "
        "(${node.runtimeType}).",
      );
      final usage = InstanceTypeArgumentVariableUse(node);
      visitNodesInContext(node.arguments.types, usage);
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitFunctionInvocation(ir.FunctionInvocation node) {
    visitNode(node.receiver);
    if (node.arguments.types.isNotEmpty) {
      assert(
        !(node.receiver is ir.VariableGet &&
            ((node.receiver as ir.VariableGet).variable.parent
                is ir.LocalFunction)),
        "Unexpected local function invocation $node "
        "(${node.runtimeType}).",
      );
      final usage = InstanceTypeArgumentVariableUse(node);
      visitNodesInContext(node.arguments.types, usage);
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitLocalFunctionInvocation(
    ir.LocalFunctionInvocation node,
  ) {
    _markVariableAsUsed(node.variable, SimpleVariableUse.explicit);
    if (node.arguments.types.isNotEmpty) {
      final usage = LocalTypeArgumentVariableUse(node.localFunction, node);
      visitNodesInContext(node.arguments.types, usage);
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitEqualsNull(ir.EqualsNull node) {
    EvaluationComplexity receiverComplexity = visitNode(node.expression);
    if (receiverComplexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitEqualsCall(ir.EqualsCall node) {
    EvaluationComplexity leftComplexity = visitNode(node.left);
    EvaluationComplexity rightComplexity = visitNode(node.right);
    if (leftComplexity.combine(rightComplexity).isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitInstanceGet(ir.InstanceGet node) {
    EvaluationComplexity complexity = visitNode(node.receiver);
    if (complexity.isConstant && node.name.text == 'length') {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitInstanceTearOff(ir.InstanceTearOff node) {
    visitNode(node.receiver);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitRecordIndexGet(ir.RecordIndexGet node) {
    visitNode(node.receiver);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitRecordNameGet(ir.RecordNameGet node) {
    visitNode(node.receiver);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitDynamicGet(ir.DynamicGet node) {
    EvaluationComplexity complexity = visitNode(node.receiver);
    if (complexity.isConstant && node.name.text == 'length') {
      return _evaluateImplicitConstant(node);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitFunctionTearOff(ir.FunctionTearOff node) {
    visitNode(node.receiver);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitInstanceSet(ir.InstanceSet node) {
    visitNode(node.receiver);
    visitNode(node.value);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitDynamicSet(ir.DynamicSet node) {
    visitNode(node.receiver);
    visitNode(node.value);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitNot(ir.Not node) {
    EvaluationComplexity complexity = visitNode(node.operand);
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return complexity;
  }

  @override
  EvaluationComplexity visitLogicalExpression(ir.LogicalExpression node) {
    EvaluationComplexity leftComplexity = visitNode(node.left);

    EvaluationComplexity rightComplexity = visitNode(node.right);

    EvaluationComplexity complexity = leftComplexity.combine(rightComplexity);
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return complexity;
  }

  @override
  EvaluationComplexity visitLet(ir.Let node) {
    visitNode(node.variable);
    visitNode(node.body);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitBlockExpression(ir.BlockExpression node) {
    visitNode(node.body);
    visitNode(node.value);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitCatch(ir.Catch node) {
    visitInContext(node.guard, SimpleVariableUse.explicit);
    if (node.exception != null) {
      visitNode(node.exception!);
    }
    if (node.stackTrace != null) {
      visitNode(node.stackTrace!);
    }
    visitInVariableScope(node, () {
      visitNode(node.body);
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitInstantiation(ir.Instantiation node) {
    EvaluationComplexity typeArgumentsComplexity = visitNodesInContext(
      node.typeArguments,
      InstantiationTypeArgumentVariableUse(node),
    );
    EvaluationComplexity expressionComplexity = visitNode(node.expression);

    EvaluationComplexity complexity = typeArgumentsComplexity.combine(
      expressionComplexity,
    );
    if (complexity.isConstant) {
      return _evaluateImplicitConstant(node);
    }
    return complexity;
  }

  @override
  EvaluationComplexity visitThrow(ir.Throw node) {
    visitNode(node.expression);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitRethrow(ir.Rethrow node) =>
      const EvaluationComplexity.lazy();

  @override
  EvaluationComplexity visitBlock(ir.Block node) {
    final parent = node.parent;
    if (parent is ir.FunctionNode || parent is ir.LoopStatement) {
      // Scoping for these blocks are handled by their parent nodes.
      visitNodes(node.statements);
    } else {
      enterNewScope(node, () {
        visitInVariableScope(node, () {
          visitNodes(node.statements);
        });
      });
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitAssertStatement(ir.AssertStatement node) {
    visitInVariableScope(node, () {
      visitNode(node.condition);
      if (node.message != null) {
        visitNode(node.message!);
      }
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitReturnStatement(ir.ReturnStatement node) {
    if (node.expression != null) {
      visitNode(node.expression!);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitEmptyStatement(ir.EmptyStatement node) {
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitExpressionStatement(ir.ExpressionStatement node) {
    visitNode(node.expression);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitSwitchStatement(ir.SwitchStatement node) {
    visitNode(node.expression);
    visitInVariableScope(node, () {
      visitNodes(node.cases);
    });
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitSwitchCase(ir.SwitchCase node) {
    visitNode(node.body);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitContinueSwitchStatement(
    ir.ContinueSwitchStatement node,
  ) {
    registerContinueSwitch();
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitBreakStatement(ir.BreakStatement node) {
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitLabeledStatement(ir.LabeledStatement node) {
    visitNode(node.body);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitFieldInitializer(ir.FieldInitializer node) {
    visitNode(node.value);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitLocalInitializer(ir.LocalInitializer node) {
    if (node.variable.initializer != null) {
      visitNode(node.variable.initializer!);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitSuperInitializer(ir.SuperInitializer node) {
    if (node.arguments.types.isNotEmpty) {
      visitNodesInContext(
        node.arguments.types,
        ConstructorTypeArgumentVariableUse(node.target),
      );
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitRedirectingInitializer(
    ir.RedirectingInitializer node,
  ) {
    if (node.arguments.types.isNotEmpty) {
      visitNodesInContext(
        node.arguments.types,
        ConstructorTypeArgumentVariableUse(node.target),
      );
    }
    visitArguments(node.arguments);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitAssertInitializer(ir.AssertInitializer node) {
    visitNode(node.statement);
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitIfStatement(ir.IfStatement node) {
    EvaluationComplexity conditionComplexity = visitNode(node.condition);
    if (conditionComplexity.isFreshConstant) {}
    visitNode(node.then);
    if (node.otherwise != null) {
      visitNode(node.otherwise!);
    }
    return const EvaluationComplexity.lazy();
  }

  @override
  EvaluationComplexity visitConstantExpression(ir.ConstantExpression node) {
    assert(node.constant is! ir.UnevaluatedConstant);
    return const EvaluationComplexity.constant();
  }

  @override
  EvaluationComplexity visitFileUriExpression(ir.FileUriExpression node) {
    return visitNode(node.expression);
  }

  /// Returns true if the node is a field, or a constructor (factory or
  /// generative).
  bool _isFieldOrConstructor(ir.Node node) =>
      node is ir.Constructor ||
      node is ir.Field ||
      (node is ir.Procedure && node.isFactory);

  void _analyzeTypeVariable(ir.TypeParameterType type, VariableUse usage) {
    final outermost = _outermostNode;
    if (outermost is ir.Member) {
      TypeVariableTypeWithContext typeVariable = TypeVariableTypeWithContext(
        type,
        outermost,
      );
      switch (typeVariable.kind) {
        case TypeVariableKind.cls:
          if (_isFieldOrConstructor(outermost)) {
            // Class type variable used in a field or constructor.
            _useTypeVariableAsLocal(typeVariable, usage);
          } else {
            // Class type variable used in a method.
            _registerNeedsThis(usage);
          }
          break;
        case TypeVariableKind.method:
        case TypeVariableKind.local:
          _useTypeVariableAsLocal(typeVariable, usage);
          break;
      }
    }
  }

  /// If [onlyForRtiChecks] is true, the variable will be added to a list
  /// indicating it *may* be used only if runtime type information is checked.
  void _useTypeVariableAsLocal(
    TypeVariableTypeWithContext typeVariable,
    VariableUse usage,
  ) {
    _markVariableAsUsed(typeVariable, usage);
  }
}

enum ComplexityLevel { constant, potentiallyEager, definitelyLazy }

class EvaluationComplexity {
  final ComplexityLevel level;
  final Set<ir.Field>? fields;
  final ir.Constant? constant;

  const EvaluationComplexity.constant([this.constant])
    : level = ComplexityLevel.constant,
      fields = null;

  // TODO(johnniwinther): Use this to collect data on the size of the
  //  initializer.
  EvaluationComplexity.eager({this.fields})
    : level = ComplexityLevel.potentiallyEager,
      constant = null;

  const EvaluationComplexity.lazy()
    : level = ComplexityLevel.definitelyLazy,
      fields = null,
      constant = null;

  EvaluationComplexity combine(EvaluationComplexity other) {
    if (identical(this, other)) {
      return this;
    } else if (isLazy || other.isLazy) {
      return const EvaluationComplexity.lazy();
    } else if (isEager || other.isEager) {
      if (fields != null && other.fields != null) {
        fields!.addAll(other.fields!);
        return this;
      } else if (fields != null) {
        return this;
      } else {
        return other;
      }
    } else if (isConstant && other.isConstant) {
      return const EvaluationComplexity.constant();
    } else if (isEager) {
      assert(other.isConstant);
      return this;
    } else {
      assert(isConstant);
      assert(other.isEager);
      return other;
    }
  }

  EvaluationComplexity makeEager() {
    if (isLazy || isEager) {
      return this;
    } else {
      return EvaluationComplexity.eager();
    }
  }

  bool get isConstant => level == ComplexityLevel.constant;

  bool get isFreshConstant => isConstant && constant != null;

  bool get isEager => level == ComplexityLevel.potentiallyEager;

  bool get isLazy => level == ComplexityLevel.definitelyLazy;

  /// Returns a short textual representation used for testing.
  String get shortText {
    StringBuffer sb = StringBuffer();
    switch (level) {
      case ComplexityLevel.constant:
        sb.write('constant');
        break;
      case ComplexityLevel.potentiallyEager:
        sb.write('eager');
        if (fields != null) {
          sb.write('&fields=[');
          List<String> names = fields!.map((f) => f.name.text).toList()..sort();
          sb.write(names.join(','));
          sb.write(']');
        }
        break;
      case ComplexityLevel.definitelyLazy:
        sb.write('lazy');
        break;
    }
    return sb.toString();
  }

  @override
  String toString() => 'InitializerComplexity($shortText)';
}
