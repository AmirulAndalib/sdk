// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/analysis_options.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/generic_inferrer.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/element/type_schema.dart';
import 'package:analyzer/src/dart/element/type_system.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/inference_log.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';

/// Context for inferring the types of elements of a collection literal.
class CollectionLiteralContext {
  /// The type context for ordinary collection elements, if this is a list or
  /// set literal.  Otherwise `null`.
  final TypeImpl? elementType;

  /// The type context for spread expressions.
  final TypeImpl iterableType;

  /// The type context for keys, if this is a map literal.  Otherwise `null`.
  final TypeImpl? keyType;

  /// The type context for values, if this is a map literal.  Otherwise `null`.
  final TypeImpl? valueType;

  CollectionLiteralContext({
    this.elementType,
    required this.iterableType,
    this.keyType,
    this.valueType,
  });
}

/// Helper for resolving [ListLiteral]s and [SetOrMapLiteral]s.
class TypedLiteralResolver {
  final ResolverVisitor _resolver;
  final TypeSystemImpl _typeSystem;
  final TypeProviderImpl _typeProvider;
  final DiagnosticReporter _diagnosticReporter;

  final bool _strictInference;

  factory TypedLiteralResolver(
    ResolverVisitor resolver,
    TypeSystemImpl typeSystem,
    TypeProviderImpl typeProvider,
    AnalysisOptions analysisOptions,
  ) {
    return TypedLiteralResolver._(
      resolver,
      typeSystem,
      typeProvider,
      resolver.diagnosticReporter,
      analysisOptions.strictInference,
    );
  }

  TypedLiteralResolver._(
    this._resolver,
    this._typeSystem,
    this._typeProvider,
    this._diagnosticReporter,
    this._strictInference,
  );

  DynamicTypeImpl get _dynamicType => DynamicTypeImpl.instance;

  bool get _genericMetadataIsEnabled =>
      _resolver.definingLibrary.featureSet.isEnabled(Feature.generic_metadata);

  void resolveListLiteral(
    ListLiteralImpl node, {
    required TypeImpl contextType,
  }) {
    TypeImpl? elementType;
    GenericInferrer? inferrer;

    var typeArguments = node.typeArguments?.arguments;
    if (typeArguments != null) {
      if (typeArguments.length == 1) {
        var type = typeArguments[0].typeOrThrow;
        if (type is! DynamicType) {
          elementType = type;
        }
      }
    } else {
      inferrer = _inferListTypeDownwards(node, contextType: contextType);
      if (contextType is! UnknownInferredType) {
        var typeArguments = inferrer.choosePreliminaryTypes();
        elementType = typeArguments[0];
      }
    }
    CollectionLiteralContext? context;
    if (elementType != null) {
      var iterableType = _typeProvider.iterableType(elementType);
      context = CollectionLiteralContext(
        elementType: elementType,
        iterableType: iterableType,
      );
    }

    node.typeArguments?.accept(_resolver);
    _resolveElements(node.elements, context);
    var staticType = _resolveListLiteral2(
      inferrer,
      node,
      contextType: contextType,
    );
    node.recordStaticType(staticType, resolver: _resolver);
  }

  void resolveSetOrMapLiteral(
    SetOrMapLiteral node, {
    required TypeImpl contextType,
  }) {
    (node as SetOrMapLiteralImpl).becomeUnresolved();
    var typeArguments = node.typeArguments?.arguments;

    InterfaceType? literalType;
    GenericInferrer? inferrer;
    var literalResolution = _computeSetOrMapResolution(
      node,
      contextType: contextType,
    );
    if (literalResolution.kind == _LiteralResolutionKind.set) {
      if (typeArguments != null && typeArguments.length == 1) {
        var elementType = typeArguments[0].typeOrThrow;
        literalType = _typeProvider.setType(elementType);
      } else {
        inferrer = _inferSetTypeDownwards(
          node,
          literalResolution.contextType ?? UnknownInferredType.instance,
        );
        if (literalResolution.contextType != null) {
          var typeArguments = inferrer.choosePreliminaryTypes();
          literalType = _typeProvider.setElement.instantiateImpl(
            typeArguments: typeArguments,
            nullabilitySuffix: NullabilitySuffix.none,
          );
        }
      }
    } else if (literalResolution.kind == _LiteralResolutionKind.map) {
      if (typeArguments != null && typeArguments.length == 2) {
        var keyType = typeArguments[0].typeOrThrow;
        var valueType = typeArguments[1].typeOrThrow;
        literalType = _typeProvider.mapType(keyType, valueType);
      } else {
        inferrer = _inferMapTypeDownwards(
          node,
          literalResolution.contextType ?? UnknownInferredType.instance,
        );
        if (literalResolution.contextType != null) {
          var typeArguments = inferrer.choosePreliminaryTypes();
          literalType = _typeProvider.mapElement.instantiateImpl(
            typeArguments: typeArguments,
            nullabilitySuffix: NullabilitySuffix.none,
          );
        }
      }
    } else {
      assert(literalResolution.kind == _LiteralResolutionKind.ambiguous);
      literalType = null;
    }
    CollectionLiteralContext? context;
    if (literalType is InterfaceTypeImpl) {
      var typeArguments = literalType.typeArguments;
      if (typeArguments.length == 1) {
        var elementType = literalType.typeArguments[0];
        var iterableType = _typeProvider.iterableType(elementType);
        context = CollectionLiteralContext(
          elementType: elementType,
          iterableType: iterableType,
        );
      } else if (typeArguments.length == 2) {
        var keyType = typeArguments[0];
        var valueType = typeArguments[1];
        context = CollectionLiteralContext(
          iterableType: literalType,
          keyType: keyType,
          valueType: valueType,
        );
      }
      node.contextType = literalType;
    } else {
      node.contextType = null;
    }

    node.typeArguments?.accept(_resolver);
    _resolveElements(node.elements, context);
    _resolveSetOrMapLiteral2(
      inferrer,
      literalResolution,
      node,
      contextType: contextType,
    );
  }

  TypeImpl _computeElementType(CollectionElementImpl element) {
    switch (element) {
      case ExpressionImpl():
        return element.typeOrThrow;
      case ForElementImpl():
        return _computeElementType(element.body);
      case IfElementImpl():
        var thenElement = element.thenElement;
        var elseElement = element.elseElement;

        var thenType = _computeElementType(thenElement);
        if (elseElement == null) {
          return thenType;
        }

        var elseType = _computeElementType(elseElement);
        return _typeSystem.leastUpperBound(thenType, elseType);
      case MapLiteralEntryImpl():
        // This error will be reported elsewhere.
        return _typeProvider.dynamicType;
      case SpreadElementImpl():
        var expressionType = element.expression.typeOrThrow;

        var iterableType = expressionType.asInstanceOf(
          _typeProvider.iterableElement,
        );
        if (iterableType != null) {
          return iterableType.typeArguments[0];
        }

        if (expressionType is DynamicType) {
          return _typeProvider.dynamicType;
        }

        if (_typeSystem.isSubtypeOf(expressionType, NeverTypeImpl.instance)) {
          return NeverTypeImpl.instance;
        }

        if (_typeSystem.isSubtypeOf(expressionType, _typeSystem.nullNone)) {
          if (element.isNullAware) {
            return NeverTypeImpl.instance;
          }
          return _typeProvider.dynamicType;
        }

        // TODO(brianwilkerson): Report this as an error.
        return _typeProvider.dynamicType;
      case NullAwareElementImpl():
        return _typeSystem.promoteToNonNull(element.value.typeOrThrow);
    }
  }

  /// Compute the context type for the given set or map [literal].
  _LiteralResolution _computeSetOrMapResolution(
    SetOrMapLiteral literal, {
    required TypeImpl? contextType,
  }) {
    _LiteralResolution typeArgumentsResolution = _fromTypeArguments(
      literal.typeArguments?.arguments,
    );
    _LiteralResolution contextResolution = _fromContextType(contextType);
    _LeafElements elementCounts = _LeafElements(literal.elements);
    _LiteralResolution elementResolution = elementCounts.resolution;

    List<_LiteralResolution> unambiguousResolutions = [];
    Set<_LiteralResolutionKind> kinds = <_LiteralResolutionKind>{};
    if (typeArgumentsResolution.kind != _LiteralResolutionKind.ambiguous) {
      unambiguousResolutions.add(typeArgumentsResolution);
      kinds.add(typeArgumentsResolution.kind);
    }
    if (contextResolution.kind != _LiteralResolutionKind.ambiguous) {
      unambiguousResolutions.add(contextResolution);
      kinds.add(contextResolution.kind);
    }
    if (elementResolution.kind != _LiteralResolutionKind.ambiguous) {
      unambiguousResolutions.add(elementResolution);
      kinds.add(elementResolution.kind);
    }

    if (kinds.length == 2) {
      // It looks like it needs to be both a map and a set. Attempt to recover.
      if (elementResolution.kind == _LiteralResolutionKind.ambiguous &&
          elementResolution.contextType != null) {
        return elementResolution;
      } else if (typeArgumentsResolution.kind !=
              _LiteralResolutionKind.ambiguous &&
          typeArgumentsResolution.contextType != null) {
        return typeArgumentsResolution;
      } else if (contextResolution.kind != _LiteralResolutionKind.ambiguous &&
          contextResolution.contextType != null) {
        return contextResolution;
      }
    } else if (unambiguousResolutions.length >= 2) {
      // If there are three resolutions, the last resolution is guaranteed to be
      // from the elements, which always has a context type of `null` (when it
      // is not ambiguous). So, whether there are 2 or 3 resolutions only the
      // first two are potentially interesting.
      return unambiguousResolutions[0].contextType == null
          ? unambiguousResolutions[1]
          : unambiguousResolutions[0];
    } else if (unambiguousResolutions.length == 1) {
      return unambiguousResolutions[0];
    } else if (literal.elements.isEmpty) {
      return _LiteralResolution(
        _LiteralResolutionKind.map,
        _typeProvider.mapType(_dynamicType, _dynamicType),
      );
    }
    return _LiteralResolution(_LiteralResolutionKind.ambiguous, null);
  }

  /// If [contextType] implements `Iterable`, but not `Map`, then *e* is a set
  /// literal.
  ///
  /// If [contextType] implements `Map`, but not `Iterable`, then *e* is a map
  /// literal.
  _LiteralResolution _fromContextType(TypeImpl? contextType) {
    if (contextType != null) {
      var unwrappedContextType = _typeSystem.futureOrBase(contextType);
      // TODO(brianwilkerson): Find out what the "greatest closure" is and use that
      // where [unwrappedContextType] is used below.
      var iterableType = unwrappedContextType.asInstanceOf(
        _typeProvider.iterableElement,
      );
      var mapType = unwrappedContextType.asInstanceOf(_typeProvider.mapElement);
      var isIterable = iterableType != null;
      var isMap = mapType != null;

      // When `S` implements `Iterable` but not `Map`, `e` is a set literal.
      if (isIterable && !isMap) {
        return _LiteralResolution(
          _LiteralResolutionKind.set,
          unwrappedContextType,
        );
      }

      // When `S` implements `Map` but not `Iterable`, `e` is a map literal.
      if (isMap && !isIterable) {
        return _LiteralResolution(
          _LiteralResolutionKind.map,
          unwrappedContextType,
        );
      }
    }

    return _LiteralResolution(_LiteralResolutionKind.ambiguous, null);
  }

  /// Return the resolution that is indicated by the given [arguments].
  _LiteralResolution _fromTypeArguments(List<TypeAnnotation>? arguments) {
    if (arguments != null) {
      if (arguments.length == 1) {
        return _LiteralResolution(
          _LiteralResolutionKind.set,
          _typeProvider.setType(arguments[0].typeOrThrow),
        );
      } else if (arguments.length == 2) {
        return _LiteralResolution(
          _LiteralResolutionKind.map,
          _typeProvider.mapType(
            arguments[0].typeOrThrow,
            arguments[1].typeOrThrow,
          ),
        );
      }
    }
    return _LiteralResolution(_LiteralResolutionKind.ambiguous, null);
  }

  _InferredCollectionElementTypeInformation _inferCollectionElementType(
    CollectionElementImpl element,
  ) {
    switch (element) {
      case ExpressionImpl():
        return _InferredCollectionElementTypeInformation(
          elementType: element.typeOrThrow,
        );
      case ForElementImpl():
        return _inferCollectionElementType(element.body);
      case IfElementImpl():
        _InferredCollectionElementTypeInformation thenType =
            _inferCollectionElementType(element.thenElement);
        if (element.elseElement == null) {
          return thenType;
        }
        _InferredCollectionElementTypeInformation elseType =
            _inferCollectionElementType(element.elseElement!);
        return _InferredCollectionElementTypeInformation.forIfElement(
          _typeSystem,
          thenType,
          elseType,
        );
      case MapLiteralEntryImpl():
        var keyType = element.key.staticType;
        if (keyType != null && element.keyQuestion != null) {
          keyType = _typeSystem.promoteToNonNull(keyType);
        }
        var valueType = element.value.staticType;
        if (valueType != null && element.valueQuestion != null) {
          valueType = _typeSystem.promoteToNonNull(valueType);
        }
        return _InferredCollectionElementTypeInformation(
          keyType: keyType,
          valueType: valueType,
        );
      case SpreadElementImpl():
        var expressionType = element.expression.typeOrThrow;

        var iterableType = expressionType.asInstanceOf(
          _typeProvider.iterableElement,
        );
        if (iterableType != null) {
          return _InferredCollectionElementTypeInformation(
            elementType: iterableType.typeArguments[0],
          );
        }

        var mapType = expressionType.asInstanceOf(_typeProvider.mapElement);
        if (mapType != null) {
          return _InferredCollectionElementTypeInformation(
            keyType: mapType.typeArguments[0],
            valueType: mapType.typeArguments[1],
          );
        }

        if (expressionType is DynamicType) {
          return _InferredCollectionElementTypeInformation(
            elementType: expressionType,
            keyType: expressionType,
            valueType: expressionType,
          );
        }

        if (_typeSystem.isSubtypeOf(expressionType, NeverTypeImpl.instance)) {
          return _InferredCollectionElementTypeInformation(
            elementType: NeverTypeImpl.instance,
            keyType: NeverTypeImpl.instance,
            valueType: NeverTypeImpl.instance,
          );
        }

        if (_typeSystem.isSubtypeOf(expressionType, _typeSystem.nullNone)) {
          if (element.isNullAware) {
            return _InferredCollectionElementTypeInformation(
              elementType: NeverTypeImpl.instance,
              keyType: NeverTypeImpl.instance,
              valueType: NeverTypeImpl.instance,
            );
          }
        }

        return _InferredCollectionElementTypeInformation();
      case NullAwareElementImpl():
        return _InferredCollectionElementTypeInformation(
          elementType: _typeSystem.promoteToNonNull(element.value.typeOrThrow),
        );
    }
  }

  GenericInferrer _inferListTypeDownwards(
    ListLiteralImpl node, {
    required TypeImpl contextType,
  }) {
    var element = _typeProvider.listElement;
    var typeParameters = element.typeParameters;
    inferenceLogWriter?.enterGenericInference(typeParameters, element.thisType);

    return _typeSystem.setupGenericTypeInference(
      typeParameters: typeParameters,
      declaredReturnType: element.thisType,
      contextReturnType: contextType,
      isConst: node.isConst,
      diagnosticReporter: _diagnosticReporter,
      errorEntity: node,
      genericMetadataIsEnabled: _genericMetadataIsEnabled,
      inferenceUsingBoundsIsEnabled: _resolver.inferenceUsingBoundsIsEnabled,
      strictInference: _resolver.analysisOptions.strictInference,
      strictCasts: _resolver.analysisOptions.strictCasts,
      typeSystemOperations: _resolver.flowAnalysis.typeOperations,
      dataForTesting: _resolver.inferenceHelper.dataForTesting,
      nodeForTesting: node,
    );
  }

  InterfaceType? _inferListTypeUpwards(
    GenericInferrer inferrer,
    ListLiteralImpl node, {
    required DartType contextType,
  }) {
    var element = _typeProvider.listElement;
    var typeParameters = element.typeParameters;
    var genericElementType = typeParameters[0].instantiate(
      nullabilitySuffix: NullabilitySuffix.none,
    );

    // Also use upwards information to infer the type.
    List<TypeImpl> elementTypes =
        node.elements.map(_computeElementType).toList();
    var syntheticParameter = FormalParameterElementImpl.synthetic(
      'element',
      genericElementType,
      ParameterKind.POSITIONAL,
    );
    var parameters = List.filled(elementTypes.length, syntheticParameter);
    if (_strictInference &&
        parameters.isEmpty &&
        contextType is UnknownInferredType) {
      // We cannot infer the type of a collection literal with no elements, and
      // no context type. If there are any elements, inference has not failed,
      // as the types of those elements are considered resolved.
      _diagnosticReporter.atNode(
        node,
        WarningCode.INFERENCE_FAILURE_ON_COLLECTION_LITERAL,
        arguments: ['List'],
      );
    }

    inferrer.constrainArguments(
      parameters: parameters,
      argumentTypes: elementTypes,
      nodeForTesting: node,
    );
    var typeArguments = inferrer.chooseFinalTypes();
    return element.instantiateImpl(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  GenericInferrer _inferMapTypeDownwards(
    SetOrMapLiteralImpl node,
    TypeImpl contextType,
  ) {
    var element = _typeProvider.mapElement;
    inferenceLogWriter?.enterGenericInference(
      element.typeParameters,
      element.thisType,
    );
    return _typeSystem.setupGenericTypeInference(
      typeParameters: element.typeParameters,
      declaredReturnType: element.thisType,
      contextReturnType: contextType,
      isConst: node.isConst,
      genericMetadataIsEnabled: _genericMetadataIsEnabled,
      inferenceUsingBoundsIsEnabled: _resolver.inferenceUsingBoundsIsEnabled,
      strictInference: _resolver.analysisOptions.strictInference,
      strictCasts: _resolver.analysisOptions.strictCasts,
      typeSystemOperations: _resolver.flowAnalysis.typeOperations,
      dataForTesting: _resolver.inferenceHelper.dataForTesting,
      nodeForTesting: node,
    );
  }

  /// Ends generic inference if it's in progress.
  DartType _inferSetOrMapLiteralType(
    GenericInferrer? inferrer,
    _LiteralResolution literalResolution,
    SetOrMapLiteral literal,
  ) {
    inferenceLogWriter?.assertGenericInferenceState(
      inProgress: inferrer != null,
    );
    var literalImpl = literal as SetOrMapLiteralImpl;
    var contextType = literalImpl.contextType;
    literalImpl.contextType = null; // Not needed anymore.
    List<CollectionElementImpl> elements = literal.elements;
    List<_InferredCollectionElementTypeInformation> inferredTypes = [];
    bool canBeAMap = true;
    bool mustBeAMap = false;
    bool canBeASet = true;
    bool mustBeASet = false;
    for (CollectionElementImpl element in elements) {
      _InferredCollectionElementTypeInformation inferredType =
          _inferCollectionElementType(element);
      inferredTypes.add(inferredType);
      canBeAMap = canBeAMap && inferredType.canBeMap;
      mustBeAMap = mustBeAMap || inferredType.mustBeMap;
      canBeASet = canBeASet && inferredType.canBeSet;
      mustBeASet = mustBeASet || inferredType.mustBeSet;
    }
    if (canBeASet && mustBeASet) {
      return _toSetType(inferrer, literalResolution, literal, inferredTypes);
    } else if (canBeAMap && mustBeAMap) {
      return _toMapType(inferrer, literalResolution, literal, inferredTypes);
    }

    // Note: according to the spec, the following computations should be based
    // on the greatest closure of the context type (unless the context type is
    // `_`).  In practice, we can just use the context type directly, because
    // the only way the greatest closure of the context type could possibly have
    // a different subtype relationship to `Iterable<Object>` and
    // `Map<Object, Object>` is if the context type is `_`.
    if (contextType != null) {
      var contextIterableType = contextType.asInstanceOf(
        _typeProvider.iterableElement,
      );
      var contextMapType = contextType.asInstanceOf(_typeProvider.mapElement);
      var contextIsIterable = contextIterableType != null;
      var contextIsMap = contextMapType != null;

      // When `S` implements `Iterable` but not `Map`, `e` is a set literal.
      if (contextIsIterable && !contextIsMap) {
        return _toSetType(inferrer, literalResolution, literal, inferredTypes);
      }

      // When `S` implements `Map` but not `Iterable`, `e` is a map literal.
      if (contextIsMap && !contextIsIterable) {
        return _toMapType(inferrer, literalResolution, literal, inferredTypes);
      }
    }

    // When `e` is of the form `{}` and `S` is undefined, `e` is a map literal.
    if (elements.isEmpty && contextType == null) {
      return _typeProvider.mapType(
        DynamicTypeImpl.instance,
        DynamicTypeImpl.instance,
      );
    }

    // Ambiguous.  We're not going to get any more information to resolve the
    // ambiguity.  We don't want to make an arbitrary decision at this point
    // because it will interfere with future type inference (see
    // dartbug.com/36210), so we return a type of `dynamic`.
    if (inferrer != null) {
      inferenceLogWriter?.exitGenericInference(failed: true);
    }
    if (mustBeAMap && mustBeASet) {
      _diagnosticReporter.atNode(
        literal,
        CompileTimeErrorCode.AMBIGUOUS_SET_OR_MAP_LITERAL_BOTH,
      );
    } else {
      _diagnosticReporter.atNode(
        literal,
        CompileTimeErrorCode.AMBIGUOUS_SET_OR_MAP_LITERAL_EITHER,
      );
    }
    return _typeProvider.dynamicType;
  }

  GenericInferrer _inferSetTypeDownwards(
    SetOrMapLiteralImpl node,
    TypeImpl contextType,
  ) {
    var element = _typeProvider.setElement;
    inferenceLogWriter?.enterGenericInference(
      element.typeParameters,
      element.thisType,
    );
    return _typeSystem.setupGenericTypeInference(
      typeParameters: element.typeParameters,
      declaredReturnType: element.thisType,
      contextReturnType: contextType,
      isConst: node.isConst,
      genericMetadataIsEnabled: _genericMetadataIsEnabled,
      inferenceUsingBoundsIsEnabled: _resolver.inferenceUsingBoundsIsEnabled,
      strictInference: _resolver.analysisOptions.strictInference,
      strictCasts: _resolver.analysisOptions.strictCasts,
      typeSystemOperations: _resolver.flowAnalysis.typeOperations,
      dataForTesting: _resolver.inferenceHelper.dataForTesting,
      nodeForTesting: node,
    );
  }

  void _resolveElements(
    List<CollectionElement> elements,
    CollectionLiteralContext? context,
  ) {
    for (var element in elements) {
      (element as CollectionElementImpl).resolveElement(_resolver, context);
      _resolver.popRewrite();
    }
  }

  DartType _resolveListLiteral2(
    GenericInferrer? inferrer,
    ListLiteralImpl node, {
    required DartType contextType,
  }) {
    var typeArguments = node.typeArguments?.arguments;

    // If we have explicit arguments, use them.
    if (typeArguments != null) {
      TypeImpl? elementType = _dynamicType;
      if (typeArguments.length == 1) {
        elementType = typeArguments[0].typeOrThrow;
      }
      return _typeProvider.listElement.instantiateImpl(
        typeArguments: fixedTypeList(elementType),
        nullabilitySuffix: NullabilitySuffix.none,
      );
    }

    DartType listDynamicType = _typeProvider.listType(_dynamicType);

    // If there are no type arguments, try to infer some arguments.
    var inferred = _inferListTypeUpwards(
      inferrer!,
      node,
      contextType: contextType,
    );

    if (inferred != listDynamicType) {
      // TODO(brianwilkerson): Determine whether we need to make the inferred
      //  type non-nullable here or whether it will already be non-nullable.
      return inferred!;
    }

    // If we have no type arguments and couldn't infer any, use dynamic.
    return listDynamicType;
  }

  /// Ends generic inference if inferrer != null.
  void _resolveSetOrMapLiteral2(
    GenericInferrer? inferrer,
    _LiteralResolution literalResolution,
    SetOrMapLiteralImpl node, {
    required DartType contextType,
  }) {
    inferenceLogWriter?.assertGenericInferenceState(
      inProgress: inferrer != null,
    );
    var typeArguments = node.typeArguments?.arguments;

    // If we have type arguments, use them.
    // TODO(paulberry): this logic seems redundant with
    //  ResolverVisitor._fromTypeArguments
    if (typeArguments != null) {
      if (typeArguments.length == 1) {
        inferenceLogWriter?.assertGenericInferenceState(inProgress: false);
        node.becomeSet();
        var elementType = typeArguments[0].typeOrThrow;
        node.recordStaticType(
          _typeProvider.setElement.instantiateImpl(
            typeArguments: fixedTypeList(elementType),
            nullabilitySuffix: NullabilitySuffix.none,
          ),
          resolver: _resolver,
        );
        return;
      } else if (typeArguments.length == 2) {
        inferenceLogWriter?.assertGenericInferenceState(inProgress: false);
        node.becomeMap();
        var keyType = typeArguments[0].typeOrThrow;
        var valueType = typeArguments[1].typeOrThrow;
        node.recordStaticType(
          _typeProvider.mapElement.instantiateImpl(
            typeArguments: fixedTypeList(keyType, valueType),
            nullabilitySuffix: NullabilitySuffix.none,
          ),
          resolver: _resolver,
        );
        return;
      }
      // If we get here, then a nonsense number of type arguments were provided,
      // so treat it as though no type arguments were provided.
    }
    DartType literalType = _inferSetOrMapLiteralType(
      inferrer,
      literalResolution,
      node,
    );
    if (literalType is DynamicType) {
      // The literal is ambiguous, and further analysis won't resolve the
      // ambiguity.  Leave it as neither a set nor a map.
    } else if (literalType is InterfaceType &&
        literalType.element == _typeProvider.mapElement) {
      node.becomeMap();
    } else {
      assert(
        literalType is InterfaceType &&
            literalType.element == _typeProvider.setElement,
      );
      node.becomeSet();
    }
    if (_strictInference &&
        node.elements.isEmpty &&
        contextType is UnknownInferredType) {
      // We cannot infer the type of a collection literal with no elements, and
      // no context type. If there are any elements, inference has not failed,
      // as the types of those elements are considered resolved.
      _diagnosticReporter.atNode(
        node,
        WarningCode.INFERENCE_FAILURE_ON_COLLECTION_LITERAL,
        arguments: [node.isMap ? 'Map' : 'Set'],
      );
    }
    // TODO(brianwilkerson): Decide whether the literalType needs to be made
    //  non-nullable here or whether that will have happened in
    //  _inferSetOrMapLiteralType.
    node.recordStaticType(literalType, resolver: _resolver);
  }

  /// Ends generic inference if it's in progress
  DartType _toMapType(
    GenericInferrer? inferrer,
    _LiteralResolution literalResolution,
    SetOrMapLiteralImpl node,
    List<_InferredCollectionElementTypeInformation> inferredTypes,
  ) {
    inferenceLogWriter?.assertGenericInferenceState(
      inProgress: inferrer != null,
    );
    TypeImpl dynamicType = _typeProvider.dynamicType;

    var element = _typeProvider.mapElement;
    var typeParameters = element.typeParameters;
    var genericKeyType = typeParameters[0].instantiate(
      nullabilitySuffix: NullabilitySuffix.none,
    );
    var genericValueType = typeParameters[1].instantiate(
      nullabilitySuffix: NullabilitySuffix.none,
    );

    var parameters = <FormalParameterElementImpl>[];
    var argumentTypes = <TypeImpl>[];
    for (var i = 0; i < inferredTypes.length; i++) {
      parameters.add(
        FormalParameterElementImpl.synthetic(
          'key',
          genericKeyType,
          ParameterKind.POSITIONAL,
        ),
      );
      parameters.add(
        FormalParameterElementImpl.synthetic(
          'value',
          genericValueType,
          ParameterKind.POSITIONAL,
        ),
      );
      argumentTypes.add(inferredTypes[i].keyType ?? dynamicType);
      argumentTypes.add(inferredTypes[i].valueType ?? dynamicType);
    }

    if (inferrer == null ||
        literalResolution.kind == _LiteralResolutionKind.set) {
      if (inferrer != null) {
        inferenceLogWriter?.exitGenericInference(aborted: true);
      }
      inferrer = _inferMapTypeDownwards(node, UnknownInferredType.instance);
    }
    inferrer.constrainArguments(
      parameters: parameters,
      argumentTypes: argumentTypes,
      nodeForTesting: node,
    );
    var typeArguments = inferrer.chooseFinalTypes();
    inferenceLogWriter?.assertGenericInferenceState(inProgress: false);
    return element.instantiateImpl(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  /// Ends generic inference if it's in progress.
  DartType _toSetType(
    GenericInferrer? inferrer,
    _LiteralResolution literalResolution,
    SetOrMapLiteralImpl node,
    List<_InferredCollectionElementTypeInformation> inferredTypes,
  ) {
    inferenceLogWriter?.assertGenericInferenceState(
      inProgress: inferrer != null,
    );
    var dynamicType = _typeProvider.dynamicType;

    var element = _typeProvider.setElement;
    var typeParameters = element.typeParameters;
    var genericElementType = typeParameters[0].instantiate(
      nullabilitySuffix: NullabilitySuffix.none,
    );

    var parameters = <FormalParameterElementImpl>[];
    var argumentTypes = <TypeImpl>[];
    for (var i = 0; i < inferredTypes.length; i++) {
      parameters.add(
        FormalParameterElementImpl.synthetic(
          'element',
          genericElementType,
          ParameterKind.POSITIONAL,
        ),
      );
      argumentTypes.add(inferredTypes[i].elementType ?? dynamicType);
    }

    if (inferrer == null ||
        literalResolution.kind == _LiteralResolutionKind.map) {
      if (inferrer != null) {
        inferenceLogWriter?.exitGenericInference(aborted: true);
      }
      inferrer = _inferSetTypeDownwards(node, UnknownInferredType.instance);
    }
    inferrer.constrainArguments(
      parameters: parameters,
      argumentTypes: argumentTypes,
      nodeForTesting: node,
    );
    var typeArguments = inferrer.chooseFinalTypes();
    inferenceLogWriter?.assertGenericInferenceState(inProgress: false);
    return element.instantiateImpl(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }
}

class _InferredCollectionElementTypeInformation {
  final TypeImpl? elementType;
  final TypeImpl? keyType;
  final TypeImpl? valueType;

  _InferredCollectionElementTypeInformation({
    this.elementType,
    this.keyType,
    this.valueType,
  });

  factory _InferredCollectionElementTypeInformation.forIfElement(
    TypeSystemImpl typeSystem,
    _InferredCollectionElementTypeInformation thenInfo,
    _InferredCollectionElementTypeInformation elseInfo,
  ) {
    if (thenInfo.isDynamic) {
      var dynamic = thenInfo.elementType!;
      return _InferredCollectionElementTypeInformation(
        elementType: _dynamicOrNull(elseInfo.elementType, dynamic),
        keyType: _dynamicOrNull(elseInfo.keyType, dynamic),
        valueType: _dynamicOrNull(elseInfo.valueType, dynamic),
      );
    } else if (elseInfo.isDynamic) {
      var dynamic = elseInfo.elementType!;
      return _InferredCollectionElementTypeInformation(
        elementType: _dynamicOrNull(thenInfo.elementType, dynamic),
        keyType: _dynamicOrNull(thenInfo.keyType, dynamic),
        valueType: _dynamicOrNull(thenInfo.valueType, dynamic),
      );
    }
    return _InferredCollectionElementTypeInformation(
      elementType: _leastUpperBoundOfTypes(
        typeSystem,
        thenInfo.elementType,
        elseInfo.elementType,
      ),
      keyType: _leastUpperBoundOfTypes(
        typeSystem,
        thenInfo.keyType,
        elseInfo.keyType,
      ),
      valueType: _leastUpperBoundOfTypes(
        typeSystem,
        thenInfo.valueType,
        elseInfo.valueType,
      ),
    );
  }

  bool get canBeMap => keyType != null || valueType != null;

  bool get canBeSet => elementType != null;

  bool get isDynamic =>
      elementType is DynamicType &&
      keyType is DynamicType &&
      valueType is DynamicType;

  bool get mustBeMap => canBeMap && elementType == null;

  bool get mustBeSet => canBeSet && keyType == null && valueType == null;

  @override
  String toString() {
    return '($elementType, $keyType, $valueType)';
  }

  static TypeImpl? _dynamicOrNull(DartType? type, TypeImpl dynamic) {
    if (type == null) {
      return null;
    }
    return dynamic;
  }

  static TypeImpl? _leastUpperBoundOfTypes(
    TypeSystemImpl typeSystem,
    TypeImpl? first,
    TypeImpl? second,
  ) {
    if (first == null) {
      return second;
    } else if (second == null) {
      return first;
    } else {
      return typeSystem.leastUpperBound(first, second);
    }
  }
}

/// A set of counts of the kinds of leaf elements in a collection, used to help
/// disambiguate map and set literals.
class _LeafElements {
  /// The number of expressions found in the collection.
  int expressionCount = 0;

  /// The number of map entries found in the collection.
  int mapEntryCount = 0;

  /// Initialize a newly created set of counts based on the given collection
  /// [elements].
  _LeafElements(List<CollectionElement> elements) {
    for (CollectionElement element in elements) {
      _count(element);
    }
  }

  /// Return the resolution suggested by the set elements.
  _LiteralResolution get resolution {
    if (expressionCount > 0 && mapEntryCount == 0) {
      return _LiteralResolution(_LiteralResolutionKind.set, null);
    } else if (mapEntryCount > 0 && expressionCount == 0) {
      return _LiteralResolution(_LiteralResolutionKind.map, null);
    }
    return _LiteralResolution(_LiteralResolutionKind.ambiguous, null);
  }

  /// Recursively add the given collection [element] to the counts.
  void _count(CollectionElement? element) {
    if (element is Expression) {
      if (_isComplete(element)) {
        expressionCount++;
      }
    } else if (element is ForElement) {
      _count(element.body);
    } else if (element is IfElement) {
      _count(element.thenElement);
      _count(element.elseElement);
    } else if (element is MapLiteralEntry) {
      if (_isComplete(element)) {
        mapEntryCount++;
      }
    }
  }

  /// Return `true` if the given collection [element] does not contain any
  /// synthetic tokens.
  bool _isComplete(CollectionElement element) {
    // TODO(brianwilkerson): (shared below)
    // TODO(paulberry): the code below doesn't work because it
    // assumes access to token offsets, which aren't available when working with
    // expressions resynthesized from summaries.  For now we just assume the
    // collection element is complete.
    return true;
    //    Token token = element.beginToken;
    //    int endOffset = element.endToken.offset;
    //    while (token != null && token.offset <= endOffset) {
    //      if (token.isSynthetic) {
    //        return false;
    //      }
    //      token = token.next;
    //    }
    //    return true;
  }
}

/// An indication of the way in which a set or map literal should be resolved to
/// be either a set literal or a map literal.
class _LiteralResolution {
  /// The kind of collection that the literal should be.
  final _LiteralResolutionKind kind;

  /// The type that should be used as the inference context when performing type
  /// inference for the literal.
  TypeImpl? contextType;

  /// Initialize a newly created resolution.
  _LiteralResolution(this.kind, this.contextType);

  @override
  String toString() {
    return '$kind ($contextType)';
  }
}

/// The kind of literal to which an unknown literal should be resolved.
enum _LiteralResolutionKind { ambiguous, map, set }
