// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as ir;
import 'package:kernel/type_environment.dart' as ir;

import '../common.dart';
import '../common/names.dart';
import '../common/elements.dart';
import '../constants/values.dart';
import '../elements/entities.dart';
import '../elements/types.dart';
import '../ir/constants.dart';
import '../ir/impact.dart';
import '../ir/impact_data.dart';
import '../ir/runtime_type_analysis.dart';
import '../ir/visitors.dart';
import '../js_backend/annotations.dart';
import '../js_backend/backend_impact.dart';
import '../js_backend/backend_usage.dart';
import '../js_backend/custom_elements_analysis.dart';
import '../js_backend/native_data.dart';
import '../js_backend/runtime_types_resolution.dart';
import '../js_model/elements.dart';
import '../native/behavior.dart';
import '../native/enqueue.dart';
import '../universe/call_structure.dart';
import '../universe/feature.dart';
import '../universe/selector.dart';
import '../universe/use.dart';
import '../universe/world_builder.dart';
import '../universe/world_impact.dart';
import 'element_map.dart';

/// [ImpactRegistry] that converts kernel based impact data to world impact
/// object based on the K model.
class KernelImpactConverter implements ImpactRegistry {
  final KernelToElementMap elementMap;
  final DiagnosticReporter reporter;
  final MemberEntity currentMember;
  final ConstantValuefier _constantValuefier;
  final ir.StaticTypeContext staticTypeContext;
  final BackendImpacts _impacts;
  final NativeResolutionEnqueuer _nativeResolutionEnqueuer;
  final BackendUsageBuilder _backendUsageBuilder;
  final CustomElementsResolutionAnalysis _customElementsResolutionAnalysis;
  final RuntimeTypesNeedBuilder _rtiNeedBuilder;
  final AnnotationsData _annotationsData;
  WorldImpactBuilder? _impactBuilder;
  WorldImpactBuilder get impactBuilder => _impactBuilder!;

  KernelImpactConverter(
    this.elementMap,
    this.currentMember,
    this.reporter,
    this._constantValuefier,
    this.staticTypeContext,
    this._impacts,
    this._nativeResolutionEnqueuer,
    this._backendUsageBuilder,
    this._customElementsResolutionAnalysis,
    this._rtiNeedBuilder,
    this._annotationsData,
  );

  ir.TypeEnvironment get typeEnvironment => elementMap.typeEnvironment;

  CommonElements get commonElements => elementMap.commonElements;

  NativeBasicData get _nativeBasicData => elementMap.nativeBasicData;

  ElementEnvironment get elementEnvironment => elementMap.elementEnvironment;

  DartTypes get dartTypes => commonElements.dartTypes;

  String typeToString(DartType type) => type.toStructuredText(dartTypes);

  Object? _computeReceiverConstraint(ir.DartType receiverType) {
    if (receiverType is ir.InterfaceType) {
      return defaultReceiverClass(
        commonElements,
        _nativeBasicData,
        elementMap.getClass(receiverType.classNode),
      );
    } else if (receiverType is ir.NullType) {
      return elementMap.getClass(typeEnvironment.coreTypes.deprecatedNullClass);
    }
    return null;
  }

  void registerBackendImpact(BackendImpact impact) {
    impact.registerImpact(impactBuilder, elementEnvironment);
    _backendUsageBuilder.processBackendImpact(impact);
  }

  void registerNativeImpact(NativeBehavior behavior) {
    _nativeResolutionEnqueuer.registerNativeBehavior(
      impactBuilder,
      behavior,
      impactBuilder,
    );
  }

  // TODO(johnniwinther): Maybe split this into [onAssertType] and [onTestType].
  void onIsCheck(DartType type) {
    registerBackendImpact(_impacts.typeCheck);
    var typeWithoutNullability = type.withoutNullability;
    if (!dartTypes.treatAsRawType(typeWithoutNullability) ||
        typeWithoutNullability.containsTypeVariables ||
        typeWithoutNullability is FunctionType) {
      registerBackendImpact(_impacts.genericTypeCheck);
      if (typeWithoutNullability is TypeVariableType) {
        registerBackendImpact(_impacts.typeVariableTypeCheck);
      }
    }
    if (typeWithoutNullability is FunctionType) {
      registerBackendImpact(_impacts.functionTypeCheck);
    }
    if (typeWithoutNullability is InterfaceType &&
        _nativeBasicData.isNativeClass(typeWithoutNullability.element)) {
      registerBackendImpact(_impacts.nativeTypeCheck);
    }
    if (typeWithoutNullability is FutureOrType) {
      registerBackendImpact(_impacts.futureOrTypeCheck);
    }
  }

  @override
  void registerParameterCheck(ir.DartType irType) {
    DartType type = elementMap.getDartType(irType);
    if (type is! DynamicType) {
      impactBuilder.registerTypeUse(TypeUse.parameterCheck(type));
      if (_annotationsData.getParameterCheckPolicy(currentMember).isEmitted) {
        onIsCheck(type);
      }
    }
  }

  List<DartType>? _getTypeArguments(List<ir.DartType> types) {
    if (types.isEmpty) return null;
    return types.map(elementMap.getDartType).toList();
  }

  @override
  void registerLazyField() {
    registerBackendImpact(_impacts.lazyField);
  }

  @override
  void registerFieldNode(ir.Field field) {
    if (field.isInstanceMember &&
        _nativeBasicData.isNativeClass(
          elementMap.getClass(field.enclosingClass!),
        )) {
      MemberEntity member = elementMap.getMember(field);
      // TODO(johnniwinther): NativeDataBuilder already has the native behavior
      // at this point. Use that instead.
      bool isJsInterop = _nativeBasicData.isJsInteropMember(member);
      Iterable<ConstantValue> metadata = elementMap.elementEnvironment
          .getMemberMetadata(member as JMember);
      Iterable<String> createsAnnotations = getCreatesAnnotations(
        dartTypes,
        reporter,
        commonElements,
        metadata,
      );
      Iterable<String> returnsAnnotations = getReturnsAnnotations(
        dartTypes,
        reporter,
        commonElements,
        metadata,
      );
      registerNativeImpact(
        elementMap.getNativeBehaviorForFieldLoad(
          field,
          createsAnnotations,
          returnsAnnotations,
          isJsInterop: isJsInterop,
        ),
      );
      registerNativeImpact(elementMap.getNativeBehaviorForFieldStore(field));
    }
  }

  @override
  void registerExternalConstructorNode(ir.Constructor constructor) {
    MemberEntity member = elementMap.getMember(constructor);
    if (constructor.isExternal && !commonElements.isForeignHelper(member)) {
      // TODO(johnniwinther): NativeDataBuilder already has the native behavior
      // at this point. Use that instead.
      bool isJsInterop = _nativeBasicData.isJsInteropMember(member);
      Iterable<ConstantValue> metadata = elementMap.elementEnvironment
          .getMemberMetadata(member as JMember);
      Iterable<String> createsAnnotations = getCreatesAnnotations(
        dartTypes,
        reporter,
        commonElements,
        metadata,
      );
      Iterable<String> returnsAnnotations = getReturnsAnnotations(
        dartTypes,
        reporter,
        commonElements,
        metadata,
      );
      registerNativeImpact(
        elementMap.getNativeBehaviorForMethod(
          constructor,
          createsAnnotations,
          returnsAnnotations,
          isJsInterop: isJsInterop,
        ),
      );
    }
  }

  @override
  void registerSyncStar(ir.DartType elementType) {
    registerBackendImpact(_impacts.syncStarBody);
    impactBuilder.registerStaticUse(
      StaticUse.staticInvoke(
        commonElements.syncStarIterableFactory,
        CallStructure.unnamed(1, 1),
        <DartType>[elementMap.getDartType(elementType)],
      ),
    );
  }

  @override
  void registerAsync(ir.DartType elementType) {
    registerBackendImpact(_impacts.asyncBody);
    impactBuilder.registerStaticUse(
      StaticUse.staticInvoke(
        commonElements.asyncAwaitCompleterFactory,
        CallStructure.unnamed(0, 1),
        <DartType>[elementMap.getDartType(elementType)],
      ),
    );
  }

  @override
  void registerAsyncStar(ir.DartType elementType) {
    registerBackendImpact(_impacts.asyncStarBody);
    impactBuilder.registerStaticUse(
      StaticUse.staticInvoke(
        commonElements.asyncStarStreamControllerFactory,
        CallStructure.unnamed(1, 1),
        <DartType>[elementMap.getDartType(elementType)],
      ),
    );
  }

  @override
  void registerExternalProcedureNode(ir.Procedure procedure) {
    MemberEntity member = elementMap.getMember(procedure);
    if (procedure.isExternal && !commonElements.isForeignHelper(member)) {
      // TODO(johnniwinther): NativeDataBuilder already has the native behavior
      // at this point. Use that instead.
      bool isJsInterop = _nativeBasicData.isJsInteropMember(member);
      Iterable<ConstantValue> metadata = elementMap.elementEnvironment
          .getMemberMetadata(member as JMember);
      Iterable<String> createsAnnotations = getCreatesAnnotations(
        dartTypes,
        reporter,
        commonElements,
        metadata,
      );
      Iterable<String> returnsAnnotations = getReturnsAnnotations(
        dartTypes,
        reporter,
        commonElements,
        metadata,
      );
      registerNativeImpact(
        elementMap.getNativeBehaviorForMethod(
          procedure,
          createsAnnotations,
          returnsAnnotations,
          isJsInterop: isJsInterop,
        ),
      );
    }
  }

  @override
  void registerIntLiteral() {
    registerBackendImpact(_impacts.intLiteral);
  }

  @override
  void registerDoubleLiteral() {
    registerBackendImpact(_impacts.doubleLiteral);
  }

  @override
  void registerBoolLiteral() {
    registerBackendImpact(_impacts.boolLiteral);
  }

  @override
  void registerStringLiteral() {
    registerBackendImpact(_impacts.stringLiteral);
  }

  @override
  void registerSymbolLiteral() {
    registerBackendImpact(_impacts.constSymbol);
  }

  @override
  void registerNullLiteral() {
    registerBackendImpact(_impacts.nullLiteral);
  }

  @override
  void registerListLiteral(
    ir.DartType elementType, {
    required bool isConst,
    required bool isEmpty,
  }) {
    // TODO(johnniwinther): Use the [isConstant] and [isEmpty] property when
    // factory constructors are registered directly.
    impactBuilder.registerTypeUse(
      TypeUse.instantiation(
        commonElements.listType(elementMap.getDartType(elementType)),
      ),
    );
  }

  @override
  void registerSetLiteral(
    ir.DartType elementType, {
    required bool isConst,
    required bool isEmpty,
  }) {
    // TODO(johnniwinther): Use the [isEmpty] property when factory
    // constructors are registered directly.
    if (isConst) {
      registerBackendImpact(_impacts.constantSetLiteral);
    } else {
      impactBuilder.registerTypeUse(
        TypeUse.instantiation(
          commonElements.setType(elementMap.getDartType(elementType)),
        ),
      );
    }
  }

  @override
  void registerMapLiteral(
    ir.DartType keyType,
    ir.DartType valueType, {
    required bool isConst,
    required bool isEmpty,
  }) {
    // TODO(johnniwinther): Use the [isEmpty] property when factory
    // constructors are registered directly.
    if (isConst) {
      registerBackendImpact(_impacts.constantMapLiteral);
    } else {
      impactBuilder.registerTypeUse(
        TypeUse.instantiation(
          commonElements.mapType(
            elementMap.getDartType(keyType),
            elementMap.getDartType(valueType),
          ),
        ),
      );
    }
  }

  @override
  void registerRecordLiteral(
    ir.RecordType recordType, {
    required bool isConst,
  }) {
    registerBackendImpact(_impacts.recordInstantiation);
    final type = elementMap.getDartType(recordType) as RecordType;
    impactBuilder.registerTypeUse(TypeUse.recordInstantiation(type));
  }

  @override
  void registerNew(
    ir.Member target,
    ir.InterfaceType type,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
    ir.LibraryDependency? import, {
    required bool isConst,
  }) {
    ConstructorEntity constructor = elementMap.getConstructor(target);
    CallStructure callStructure = CallStructure(
      positionalArguments + namedArguments.length,
      namedArguments,
      typeArguments.length,
    );
    ImportEntity? deferredImport = elementMap.getImport(import);
    impactBuilder.registerStaticUse(
      isConst
          ? StaticUse.constConstructorInvoke(
              constructor,
              callStructure,
              elementMap.getInterfaceType(type),
              deferredImport,
            )
          : StaticUse.typedConstructorInvoke(
              constructor,
              callStructure,
              elementMap.getInterfaceType(type),
              deferredImport,
            ),
    );
    if (type.typeArguments.any((ir.DartType type) => type is! ir.DynamicType)) {
      registerBackendImpact(_impacts.typeVariableBoundCheck);
    }

    if (target.isExternal &&
        constructor.isFromEnvironmentConstructor &&
        !isConst) {
      registerBackendImpact(_impacts.throwUnsupportedError);
      // We need to register the external constructor as live below, so don't
      // return here.
    }
  }

  @override
  void registerConstInstantiation(
    ir.Class cls,
    List<ir.DartType> typeArguments,
    ir.LibraryDependency? import,
  ) {
    ImportEntity? deferredImport = elementMap.getImport(import);
    InterfaceType type = elementMap.createInterfaceType(cls, typeArguments);
    impactBuilder.registerTypeUse(
      TypeUse.constInstantiation(type, deferredImport),
    );
  }

  @override
  void registerConstSymbolConstructorInvocationNode() {
    registerBackendImpact(_impacts.constSymbol);
  }

  @override
  void registerSuperInitializer(
    ir.Constructor source,
    ir.Constructor target,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    // TODO(johnniwinther): Maybe rewrite `node.target` to point to a
    // synthesized unnamed mixin constructor when needed. This would require us
    // to consider impact building a required pre-step for inference and
    // ssa-building.
    ConstructorEntity constructor = elementMap.getSuperConstructor(
      source,
      target,
    );
    impactBuilder.registerStaticUse(
      StaticUse.superConstructorInvoke(
        constructor,
        CallStructure(
          positionalArguments + namedArguments.length,
          namedArguments,
          typeArguments.length,
        ),
      ),
    );
  }

  @override
  void registerStaticInvocation(
    ir.Procedure procedure,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
    ir.LibraryDependency? import,
  ) {
    FunctionEntity target = elementMap.getMethod(procedure);
    CallStructure callStructure = CallStructure(
      positionalArguments + namedArguments.length,
      namedArguments,
      typeArguments.length,
    );
    List<DartType>? dartTypeArguments = _getTypeArguments(typeArguments);
    if (commonElements.isExtractTypeArguments(target)) {
      _handleExtractTypeArguments(target, dartTypeArguments!, callStructure);
      return;
    } else {
      ImportEntity? deferredImport = elementMap.getImport(import);
      impactBuilder.registerStaticUse(
        StaticUse.staticInvoke(
          target,
          callStructure,
          dartTypeArguments,
          deferredImport,
        ),
      );
    }
  }

  @override
  void registerForeignStaticInvocationNode(ir.StaticInvocation node) {
    switch (elementMap.getForeignKind(node)) {
      case ForeignKind.js:
        registerNativeImpact(elementMap.getNativeBehaviorForJsCall(node));
        break;
      case ForeignKind.jsBuiltin:
        registerNativeImpact(
          elementMap.getNativeBehaviorForJsBuiltinCall(node),
        );
        break;
      case ForeignKind.jsEmbeddedGlobal:
        registerNativeImpact(
          elementMap.getNativeBehaviorForJsEmbeddedGlobalCall(node),
        );
        break;
      case ForeignKind.jsInterceptorConstant:
        InterfaceType? type = elementMap.getInterfaceTypeForJsInterceptorCall(
          node,
        );
        if (type != null) {
          impactBuilder.registerTypeUse(TypeUse.instantiation(type));
        }
        break;
      case ForeignKind.none:
        break;
    }
  }

  void _handleExtractTypeArguments(
    FunctionEntity target,
    List<DartType> typeArguments,
    CallStructure callStructure,
  ) {
    // extractTypeArguments<Map>(obj, fn) has additional impacts:
    //
    //   1. All classes implementing Map need to carry type arguments (similar
    //      to checking `o is Map<K, V>`).
    //
    //   2. There is an invocation of fn with some number of type arguments.
    //
    impactBuilder.registerStaticUse(
      StaticUse.staticInvoke(target, callStructure, typeArguments),
    );

    if (typeArguments.length != 1) return;
    DartType matchedType = typeArguments.single;

    if (matchedType is! InterfaceType) return;
    InterfaceType interfaceType = matchedType;
    ClassEntity cls = interfaceType.element;
    InterfaceType thisType = elementMap.elementEnvironment.getThisType(cls);
    _registerIsCheckInternal(thisType);

    Selector selector = Selector.callClosure(
      0,
      const <String>[],
      thisType.typeArguments.length,
    );
    impactBuilder.registerDynamicUse(
      DynamicUse(selector, null, thisType.typeArguments),
    );
  }

  @override
  void registerStaticTearOff(
    ir.Procedure procedure,
    ir.LibraryDependency? import,
  ) {
    impactBuilder.registerStaticUse(
      StaticUse.staticTearOff(
        elementMap.getMethod(procedure),
        elementMap.getImport(import),
      ),
    );
  }

  @override
  void registerWeakStaticTearOff(
    ir.Procedure procedure,
    ir.LibraryDependency? import,
  ) {
    impactBuilder.registerStaticUse(
      StaticUse.weakStaticTearOff(
        elementMap.getMethod(procedure),
        elementMap.getImport(import),
      ),
    );
  }

  @override
  void registerStaticGet(ir.Member member, ir.LibraryDependency? import) {
    impactBuilder.registerStaticUse(
      StaticUse.staticGet(
        elementMap.getMember(member),
        elementMap.getImport(import),
      ),
    );
  }

  @override
  void registerStaticSet(ir.Member member, ir.LibraryDependency? import) {
    impactBuilder.registerStaticUse(
      StaticUse.staticSet(
        elementMap.getMember(member),
        elementMap.getImport(import),
      ),
    );
  }

  @override
  void registerSuperInvocation(
    ir.Member target,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    FunctionEntity method = elementMap.getMember(target) as FunctionEntity;
    List<DartType>? dartTypeArguments = _getTypeArguments(typeArguments);
    impactBuilder.registerStaticUse(
      StaticUse.superInvoke(
        method,
        CallStructure(
          positionalArguments + namedArguments.length,
          namedArguments,
          typeArguments.length,
        ),
        dartTypeArguments,
      ),
    );
  }

  @override
  void registerSuperGet(ir.Member target) {
    MemberEntity member = elementMap.getMember(target);
    if (member.isFunction) {
      impactBuilder.registerStaticUse(
        StaticUse.superTearOff(member as FunctionEntity),
      );
    } else {
      impactBuilder.registerStaticUse(StaticUse.superGet(member));
    }
  }

  @override
  void registerSuperSet(ir.Member target) {
    MemberEntity member = elementMap.getMember(target);
    if (member is FieldEntity) {
      impactBuilder.registerStaticUse(StaticUse.superFieldSet(member));
    } else {
      impactBuilder.registerStaticUse(
        StaticUse.superSetterSet(member as FunctionEntity),
      );
    }
  }

  @override
  void registerLocalFunctionInvocation(
    ir.FunctionDeclaration localFunction,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    CallStructure callStructure = CallStructure(
      positionalArguments + namedArguments.length,
      namedArguments,
      typeArguments.length,
    );
    List<DartType>? dartTypeArguments = _getTypeArguments(typeArguments);
    // Invocation of a local function. No need for dynamic use, but
    // we need to track the type arguments.
    impactBuilder.registerStaticUse(
      StaticUse.closureCall(
        elementMap.getLocalFunction(localFunction),
        callStructure,
        dartTypeArguments,
      ),
    );
    // TODO(johnniwinther): Yet, alas, we need the dynamic use for now. Remove
    // this when kernel adds an `isFunctionCall` flag to
    // [ir.MethodInvocation].
    impactBuilder.registerDynamicUse(
      DynamicUse(callStructure.callSelector, null, dartTypeArguments),
    );
  }

  @override
  void registerDynamicInvocation(
    ir.DartType receiverType,
    ir.Name name,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    Selector selector = elementMap.getInvocationSelector(
      name,
      positionalArguments,
      namedArguments,
      typeArguments.length,
    );
    List<DartType>? dartTypeArguments = _getTypeArguments(typeArguments);
    impactBuilder.registerDynamicUse(
      DynamicUse(
        selector,
        _computeReceiverConstraint(receiverType),
        dartTypeArguments,
      ),
    );
  }

  @override
  void registerFunctionInvocation(
    ir.DartType receiverType,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    CallStructure callStructure = CallStructure(
      positionalArguments + namedArguments.length,
      namedArguments,
      typeArguments.length,
    );
    List<DartType>? dartTypeArguments = _getTypeArguments(typeArguments);
    impactBuilder.registerDynamicUse(
      DynamicUse(
        callStructure.callSelector,
        _computeReceiverConstraint(receiverType),
        dartTypeArguments,
      ),
    );
  }

  @override
  void registerInstanceInvocation(
    ir.DartType receiverType,
    ir.Member target,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    List<DartType>? dartTypeArguments = _getTypeArguments(typeArguments);
    impactBuilder.registerDynamicUse(
      DynamicUse(
        elementMap.getInvocationSelector(
          target.name,
          positionalArguments,
          namedArguments,
          typeArguments.length,
        ),
        _computeReceiverConstraint(receiverType),
        dartTypeArguments,
      ),
    );
  }

  @override
  void registerDynamicGet(ir.DartType receiverType, ir.Name name) {
    impactBuilder.registerDynamicUse(
      DynamicUse(
        Selector.getter(elementMap.getName(name)),
        _computeReceiverConstraint(receiverType),
        const <DartType>[],
      ),
    );
  }

  @override
  void registerInstanceGet(ir.DartType receiverType, ir.Member target) {
    impactBuilder.registerDynamicUse(
      DynamicUse(
        Selector.getter(elementMap.getName(target.name)),
        _computeReceiverConstraint(receiverType),
        const <DartType>[],
      ),
    );
  }

  @override
  void registerDynamicSet(ir.DartType receiverType, ir.Name name) {
    impactBuilder.registerDynamicUse(
      DynamicUse(
        Selector.setter(elementMap.getName(name)),
        _computeReceiverConstraint(receiverType),
        const <DartType>[],
      ),
    );
  }

  @override
  void registerInstanceSet(ir.DartType receiverType, ir.Member target) {
    impactBuilder.registerDynamicUse(
      DynamicUse(
        Selector.setter(elementMap.getName(target.name)),
        _computeReceiverConstraint(receiverType),
        const <DartType>[],
      ),
    );
  }

  @override
  void registerRuntimeTypeUse(
    RuntimeTypeUseKind kind,
    ir.DartType receiverType,
    ir.DartType? argumentType,
  ) {
    DartType receiverDartType = elementMap.getDartType(receiverType);
    DartType? argumentDartType = argumentType == null
        ? null
        : elementMap.getDartType(argumentType);

    // Enable runtime type support if we discover a getter called
    // runtimeType. We have to enable runtime type before hitting the
    // codegen, so that constructors know whether they need to generate code
    // for runtime type.
    _backendUsageBuilder.registerRuntimeTypeUse(
      RuntimeTypeUse(kind, receiverDartType, argumentDartType),
    );
  }

  @override
  void registerAssert({required bool withMessage}) {
    registerBackendImpact(
      withMessage ? _impacts.assertWithMessage : _impacts.assertWithoutMessage,
    );
  }

  @override
  void registerGenericInstantiation(
    ir.FunctionType expressionType,
    List<ir.DartType> typeArguments,
  ) {
    // TODO(johnniwinther): Track which arities are used in instantiation.
    final instantiation = GenericInstantiation(
      elementMap.getDartType(expressionType).withoutNullability as FunctionType,
      typeArguments.map(elementMap.getDartType).toList(),
    );
    registerBackendImpact(
      _impacts.getGenericInstantiation(instantiation.typeArguments.length),
    );
    _rtiNeedBuilder.registerGenericInstantiation(instantiation);
  }

  @override
  void registerStringConcatenation() {
    registerBackendImpact(_impacts.stringInterpolation);
    registerBackendImpact(_impacts.stringJuxtaposition);
  }

  @override
  void registerLocalFunction(covariant ir.LocalFunction node) {
    Local function = elementMap.getLocalFunction(node);
    impactBuilder.registerStaticUse(StaticUse.closure(function));
    registerBackendImpact(_impacts.closure);
    registerBackendImpact(_impacts.computeSignature);
  }

  @override
  void registerLocalWithoutInitializer() {
    impactBuilder.registerTypeUse(
      TypeUse.instantiation(commonElements.nullType),
    );
    registerBackendImpact(_impacts.nullLiteral);
  }

  void _registerIsCheckInternal(DartType type) {
    impactBuilder.registerTypeUse(TypeUse.isCheck(type));
    onIsCheck(type);
  }

  @override
  void registerIsCheck(ir.DartType irType) {
    _registerIsCheckInternal(elementMap.getDartType(irType));
  }

  @override
  void registerImplicitCast(ir.DartType irType) {
    DartType type = elementMap.getDartType(irType);
    impactBuilder.registerTypeUse(TypeUse.implicitCast(type));
    if (_annotationsData
        .getImplicitDowncastCheckPolicy(currentMember)
        .isEmitted) {
      onIsCheck(type);
    }
  }

  @override
  void registerAsCast(ir.DartType irType) {
    DartType type = elementMap.getDartType(irType);
    impactBuilder.registerTypeUse(TypeUse.asCast(type));
    if (_annotationsData.getExplicitCastCheckPolicy(currentMember).isEmitted) {
      onIsCheck(type);
      registerBackendImpact(_impacts.asCheck);
    }
  }

  @override
  void registerThrow() {
    registerBackendImpact(_impacts.throwExpression);
  }

  @override
  void registerSyncForIn(ir.DartType iterableType, ir.DartType iteratorType) {
    Object? receiverConstraint = _computeReceiverConstraint(iteratorType);
    registerBackendImpact(_impacts.syncForIn);
    impactBuilder.registerDynamicUse(
      DynamicUse(Selectors.iterator, receiverConstraint, const []),
    );
    impactBuilder.registerDynamicUse(
      DynamicUse(Selectors.current, receiverConstraint, const []),
    );
    impactBuilder.registerDynamicUse(
      DynamicUse(Selectors.moveNext, receiverConstraint, const []),
    );
  }

  @override
  void registerAsyncForIn(ir.DartType iterableType, ir.DartType iteratorType) {
    Object? receiverConstraint = _computeReceiverConstraint(iteratorType);
    registerBackendImpact(_impacts.asyncForIn);
    impactBuilder.registerDynamicUse(
      DynamicUse(Selectors.cancel, receiverConstraint, const []),
    );
    impactBuilder.registerDynamicUse(
      DynamicUse(Selectors.current, receiverConstraint, const []),
    );
    impactBuilder.registerDynamicUse(
      DynamicUse(Selectors.moveNext, receiverConstraint, const []),
    );
  }

  @override
  void registerCatch() {
    registerBackendImpact(_impacts.catchStatement);
  }

  @override
  void registerStackTrace() {
    registerBackendImpact(_impacts.stackTraceInCatch);
  }

  @override
  void registerCatchType(ir.DartType irType) {
    DartType type = elementMap.getDartType(irType);
    impactBuilder.registerTypeUse(TypeUse.catchType(type));
    onIsCheck(type);
  }

  @override
  void registerTypeLiteral(ir.DartType irType, ir.LibraryDependency? import) {
    ImportEntity? deferredImport = elementMap.getImport(import);
    DartType type = elementMap.getDartType(irType);
    impactBuilder.registerTypeUse(TypeUse.typeLiteral(type, deferredImport));
    _customElementsResolutionAnalysis.registerTypeLiteral(type);
    type.forEachTypeVariable((TypeVariableType variable) {
      _rtiNeedBuilder.registerTypeVariableLiteral(variable);
      registerBackendImpact(_impacts.typeVariableExpression);
    });
    impactBuilder.registerTypeUse(
      TypeUse.instantiation(commonElements.typeType),
    );
    registerBackendImpact(_impacts.typeLiteral);
  }

  @override
  void registerFieldInitialization(ir.Field node) {
    impactBuilder.registerStaticUse(
      StaticUse.fieldInit(elementMap.getField(node)),
    );
  }

  @override
  void registerFieldConstantInitialization(
    ir.Field node,
    ConstantReference constant,
  ) {
    impactBuilder.registerStaticUse(
      StaticUse.fieldConstantInit(
        elementMap.getField(node),
        _constantValuefier.visitConstant(constant.constant),
      ),
    );
  }

  @override
  void registerRedirectingInitializer(
    ir.Constructor constructor,
    int positionalArguments,
    List<String> namedArguments,
    List<ir.DartType> typeArguments,
  ) {
    ConstructorEntity target = elementMap.getConstructor(constructor);
    impactBuilder.registerStaticUse(
      StaticUse.superConstructorInvoke(
        target,
        CallStructure(
          positionalArguments + namedArguments.length,
          namedArguments,
          typeArguments.length,
        ),
      ),
    );
  }

  @override
  void registerLoadLibrary() {
    impactBuilder.registerStaticUse(
      StaticUse.staticInvoke(
        commonElements.loadDeferredLibrary,
        CallStructure.oneArg,
      ),
    );
    registerBackendImpact(_impacts.loadLibrary);
  }

  /// Converts a [ImpactData] object based on kernel to the corresponding
  /// [WorldImpact] based on the K model.
  WorldImpact convert(ImpactData impactData) {
    final oldBuilder = _impactBuilder;
    final newBuilder = _impactBuilder = WorldImpactBuilderImpl(currentMember);
    impactData.apply(this);
    _impactBuilder = oldBuilder;
    return newBuilder;
  }

  @override
  void registerConditionalImpact(ConditionalImpactData impact) {
    final conditionalUse = ConditionalUse.withReplacement(
      impact: convert(impact.impactData),
      replacementImpact: convert(impact.replacementImpactData),
      originalConditions: impact.originalConditions
          .map(elementMap.getMember)
          .toList(),
      original: impact.original,
      replacement: impact.replacement,
    );
    impactBuilder.registerConditionalUse(conditionalUse);
  }
}
