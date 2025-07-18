// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/type_inference/type_analyzer_operations.dart'
    show Variance;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_algebra.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/element/type_schema.dart';
import 'package:analyzer/src/dart/element/type_system.dart';

/// Helper for checking the subtype relation.
///
/// https://github.com/dart-lang/language
/// See `resources/type-system/subtyping.md`
class SubtypeHelper {
  final TypeSystemImpl _typeSystem;
  final TypeProviderImpl _typeProvider;
  final InterfaceTypeImpl _nullNone;
  final InterfaceTypeImpl _objectNone;
  final InterfaceTypeImpl _objectQuestion;

  SubtypeHelper(this._typeSystem)
    : _typeProvider = _typeSystem.typeProvider,
      _nullNone = _typeSystem.nullNone,
      _objectNone = _typeSystem.objectNone,
      _objectQuestion = _typeSystem.objectQuestion;

  /// Return `true` if [T0] is a subtype of [T1].
  bool isSubtypeOf(TypeImpl T0, TypeImpl T1) {
    // Reflexivity: if `T0` and `T1` are the same type then `T0 <: T1`.
    if (identical(T0, T1)) {
      return true;
    }

    // `_` is treated as a top and a bottom type during inference.
    if (identical(T0, UnknownInferredType.instance) ||
        identical(T1, UnknownInferredType.instance)) {
      return true;
    }

    // `InvalidType` is treated as a top and a bottom type.
    if (identical(T0, InvalidTypeImpl.instance) ||
        identical(T1, InvalidTypeImpl.instance)) {
      return true;
    }

    var T1_nullability = T1.nullabilitySuffix;
    var T0_nullability = T0.nullabilitySuffix;

    // Right Top: if `T1` is a top type (i.e. `dynamic`, or `void`, or
    // `Object?`) then `T0 <: T1`.
    if (identical(T1, DynamicTypeImpl.instance) ||
        identical(T1, InvalidTypeImpl.instance) ||
        identical(T1, VoidTypeImpl.instance) ||
        T1_nullability == NullabilitySuffix.question && T1.isDartCoreObject) {
      return true;
    }

    // Left Top: if `T0` is `dynamic` or `void`,
    //   then `T0 <: T1` if `Object? <: T1`.
    if (identical(T0, DynamicTypeImpl.instance) ||
        identical(T0, InvalidTypeImpl.instance) ||
        identical(T0, VoidTypeImpl.instance)) {
      if (isSubtypeOf(_objectQuestion, T1)) {
        return true;
      }
    }

    // Left Bottom: if `T0` is `Never`, then `T0 <: T1`.
    if (identical(T0, NeverTypeImpl.instance)) {
      return true;
    }

    // Right Object: if `T1` is `Object` then:
    if (T1_nullability == NullabilitySuffix.none && T1.isDartCoreObject) {
      // * if `T0` is an unpromoted type variable with bound `B`,
      //   then `T0 <: T1` iff `B <: Object`.
      // * if `T0` is a promoted type variable `X & S`,
      //   then `T0 <: T1` iff `S <: Object`.
      if (T0_nullability == NullabilitySuffix.none &&
          T0 is TypeParameterTypeImpl) {
        var S = T0.promotedBound;
        if (S == null) {
          var B = T0.element.bound ?? _objectQuestion;
          return isSubtypeOf(B, _objectNone);
        } else {
          return isSubtypeOf(S, _objectNone);
        }
      }
      // * if `T0` is `FutureOr<S>` for some `S`,
      //   then `T0 <: T1` iff `S <: Object`
      if (T0_nullability == NullabilitySuffix.none &&
          T0 is InterfaceTypeImpl &&
          T0.isDartAsyncFutureOr) {
        return isSubtypeOf(T0.typeArguments[0], T1);
      }
      // * if `T0` is `Null`, `dynamic`, `void`, or `S?` for any `S`,
      //   then the subtyping does not hold, the result is false.
      if (T0_nullability == NullabilitySuffix.none && T0.isDartCoreNull ||
          identical(T0, DynamicTypeImpl.instance) ||
          identical(T0, InvalidTypeImpl.instance) ||
          identical(T0, VoidTypeImpl.instance) ||
          T0_nullability == NullabilitySuffix.question) {
        return false;
      }
      // Extension types require explicit `Object` implementation.
      if (T0 is InterfaceTypeImpl && T0.element is ExtensionTypeElement) {
        for (var interface in T0.interfaces) {
          if (isSubtypeOf(interface, T1)) {
            return true;
          }
        }
        return false;
      }
      // Otherwise `T0 <: T1` is true.
      return true;
    }

    // Left Null: if `T0` is `Null` then:
    if (T0_nullability == NullabilitySuffix.none && T0.isDartCoreNull) {
      // * If `T1` is `FutureOr<S>` for some `S`, then the query is true iff
      // `Null <: S`.
      if (T1_nullability == NullabilitySuffix.none &&
          T1 is InterfaceTypeImpl &&
          T1.isDartAsyncFutureOr) {
        var S = T1.typeArguments[0];
        return isSubtypeOf(_nullNone, S);
      }
      // If `T1` is `Null` or `S?` for some `S`, then the query is true.
      if (T1_nullability == NullabilitySuffix.none && T1.isDartCoreNull ||
          T1_nullability == NullabilitySuffix.question) {
        return true;
      }
      // * if `T1` is a type variable (promoted or not) the query is false
      if (T1 is TypeParameterTypeImpl) {
        return false;
      }
      // Otherwise, the query is false.
      return false;
    }

    // Left FutureOr: if `T0` is `FutureOr<S0>` then:
    if (T0_nullability == NullabilitySuffix.none &&
        T0 is InterfaceTypeImpl &&
        T0.isDartAsyncFutureOr) {
      var S0 = T0.typeArguments[0];
      // * `T0 <: T1` iff `Future<S0> <: T1` and `S0 <: T1`
      if (isSubtypeOf(S0, T1)) {
        var FutureS0 = _typeProvider.futureElement.instantiateImpl(
          typeArguments: fixedTypeList(S0),
          nullabilitySuffix: NullabilitySuffix.none,
        );
        return isSubtypeOf(FutureS0, T1);
      }
      return false;
    }

    // Left Nullable: if `T0` is `S0?` then:
    //   * `T0 <: T1` iff `S0 <: T1` and `Null <: T1`.
    if (T0_nullability == NullabilitySuffix.question) {
      var S0 = T0.withNullability(NullabilitySuffix.none);
      return isSubtypeOf(S0, T1) && isSubtypeOf(_nullNone, T1);
    }

    // Type Variable Reflexivity 1: if T0 is a type variable X0 or a promoted
    // type variables X0 & S0 and T1 is X0 then:
    //   * T0 <: T1
    if (T0 is TypeParameterTypeImpl &&
        T1 is TypeParameterTypeImpl &&
        T1.promotedBound == null &&
        T0.element == T1.element) {
      return true;
    }

    // Right Promoted Variable: if `T1` is a promoted type variable `X1 & S1`:
    //   * `T0 <: T1` iff `T0 <: X1` and `T0 <: S1`
    if (T1 is TypeParameterTypeImpl) {
      var T1_promotedBound = T1.promotedBound;
      if (T1_promotedBound != null) {
        var X1 = TypeParameterTypeImpl(
          element: T1.element,
          nullabilitySuffix: T1.nullabilitySuffix,
        );
        return isSubtypeOf(T0, X1) && isSubtypeOf(T0, T1_promotedBound);
      }
    }

    // Right FutureOr: if `T1` is `FutureOr<S1>` then:
    if (T1_nullability == NullabilitySuffix.none &&
        T1 is InterfaceTypeImpl &&
        T1.isDartAsyncFutureOr) {
      var S1 = T1.typeArguments[0];
      // `T0 <: T1` iff any of the following hold:
      // * either `T0 <: Future<S1>`
      var FutureS1 = _typeProvider.futureElement.instantiateImpl(
        typeArguments: fixedTypeList(S1),
        nullabilitySuffix: NullabilitySuffix.none,
      );
      if (isSubtypeOf(T0, FutureS1)) {
        return true;
      }
      // * or `T0 <: S1`
      if (isSubtypeOf(T0, S1)) {
        return true;
      }
      // * or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
      // * or `T0` is `X0 & S0` and `S0 <: T1`
      if (T0 is TypeParameterTypeImpl) {
        var S0 = T0.promotedBound;
        if (S0 != null && isSubtypeOf(S0, T1)) {
          return true;
        }
        var B0 = T0.element.bound;
        if (B0 != null && isSubtypeOf(B0, T1)) {
          return true;
        }
      }
      // iff
      return false;
    }

    // Right Nullable: if `T1` is `S1?` then:
    if (T1_nullability == NullabilitySuffix.question) {
      var S1 = T1.withNullability(NullabilitySuffix.none);
      // `T0 <: T1` iff any of the following hold:
      // * either `T0 <: S1`
      if (isSubtypeOf(T0, S1)) {
        return true;
      }
      // * or `T0 <: Null`
      if (isSubtypeOf(T0, _nullNone)) {
        return true;
      }
      // or `T0` is `X0` and `X0` has bound `S0` and `S0 <: T1`
      // or `T0` is `X0 & S0` and `S0 <: T1`
      if (T0 is TypeParameterTypeImpl) {
        var S0 = T0.promotedBound;
        if (S0 != null && isSubtypeOf(S0, T1)) {
          return true;
        }
        var B0 = T0.element.bound;
        if (B0 != null && isSubtypeOf(B0, T1)) {
          return true;
        }
      }
      // iff
      return false;
    }

    // Super-Interface: `T0` is an interface type with super-interfaces
    // `S0,...Sn`:
    //   * and `Si <: T1` for some `i`.
    if (T0 is InterfaceTypeImpl && T1 is InterfaceTypeImpl) {
      return _isInterfaceSubtypeOf(T0, T1);
    }

    // Left Promoted Variable: `T0` is a promoted type variable `X0 & S0`
    //   * and `S0 <: T1`
    // Left Type Variable Bound: `T0` is a type variable `X0` with bound `B0`
    //   * and `B0 <: T1`
    if (T0 is TypeParameterTypeImpl) {
      var S0 = T0.promotedBound;
      if (S0 != null && isSubtypeOf(S0, T1)) {
        return true;
      }

      var B0 = T0.element.bound;
      if (B0 != null && isSubtypeOf(B0, T1)) {
        return true;
      }
    }

    if (T0 is FunctionTypeImpl) {
      // Function Type/Function: `T0` is a function type and `T1` is `Function`.
      if (T1.isDartCoreFunction) {
        return true;
      }
      if (T1 is FunctionTypeImpl) {
        return _isFunctionSubtypeOf(T0, T1);
      }
    }

    if (T0 is RecordTypeImpl) {
      // Record Type/Record: `T0` is a record type, and `T1` is `Record`.
      if (T1.isDartCoreRecord) {
        return true;
      }
      if (T1 is RecordTypeImpl) {
        return _isRecordSubtypeOf(T0, T1);
      }
    }

    return false;
  }

  bool _interfaceArguments(
    InterfaceElementImpl element,
    InterfaceTypeImpl subType,
    InterfaceTypeImpl superType,
  ) {
    var parameters = element.typeParameters;
    var subArguments = subType.typeArguments;
    var superArguments = superType.typeArguments;

    assert(subArguments.length == superArguments.length);
    assert(parameters.length == subArguments.length);

    for (var i = 0; i < subArguments.length; i++) {
      var parameter = parameters[i];
      var subArgument = subArguments[i];
      var superArgument = superArguments[i];

      Variance variance = parameter.variance;
      if (variance.isCovariant) {
        if (!isSubtypeOf(subArgument, superArgument)) {
          return false;
        }
      } else if (variance.isContravariant) {
        if (!isSubtypeOf(superArgument, subArgument)) {
          return false;
        }
      } else if (variance.isInvariant) {
        if (!isSubtypeOf(subArgument, superArgument) ||
            !isSubtypeOf(superArgument, subArgument)) {
          return false;
        }
      } else {
        throw StateError(
          'Type parameter $parameter has unknown '
          'variance $variance for subtype checking.',
        );
      }
    }
    return true;
  }

  /// Check that [f] is a subtype of [g].
  bool _isFunctionSubtypeOf(FunctionTypeImpl f, FunctionTypeImpl g) {
    var fresh = _typeSystem.relateTypeParameters(
      f.typeParameters,
      g.typeParameters,
    );
    if (fresh == null) {
      return false;
    }

    f = f.instantiate(fresh.typeParameterTypes);
    g = g.instantiate(fresh.typeParameterTypes);

    if (!isSubtypeOf(f.returnType, g.returnType)) {
      return false;
    }

    var fParameters = f.formalParameters;
    var gParameters = g.formalParameters;

    var fIndex = 0;
    var gIndex = 0;
    while (fIndex < fParameters.length && gIndex < gParameters.length) {
      var fParameter = fParameters[fIndex];
      var gParameter = gParameters[gIndex];
      if (fParameter.isRequiredPositional) {
        if (gParameter.isRequiredPositional) {
          if (isSubtypeOf(gParameter.type, fParameter.type)) {
            fIndex++;
            gIndex++;
          } else {
            return false;
          }
        } else {
          return false;
        }
      } else if (fParameter.isOptionalPositional) {
        if (gParameter.isPositional) {
          if (isSubtypeOf(gParameter.type, fParameter.type)) {
            fIndex++;
            gIndex++;
          } else {
            return false;
          }
        } else {
          return false;
        }
      } else if (fParameter.isNamed) {
        if (gParameter.isNamed) {
          var fName = fParameter.name;
          var gName = gParameter.name;
          if (fName == null || gName == null) {
            return false;
          }

          var compareNames = fName.compareTo(gName);
          switch (compareNames) {
            case 0:
              if (fParameter.isRequiredNamed && !gParameter.isRequiredNamed) {
                return false;
              } else if (isSubtypeOf(gParameter.type, fParameter.type)) {
                fIndex++;
                gIndex++;
              } else {
                return false;
              }
            case < 0:
              if (fParameter.isRequiredNamed) {
                return false;
              } else {
                fIndex++;
              }
            default:
              // The subtype must accept all parameters of the supertype.
              return false;
          }
        } else {
          break;
        }
      }
    }

    // The supertype must provide all required parameters to the subtype.
    while (fIndex < fParameters.length) {
      var fParameter = fParameters[fIndex++];
      if (fParameter.isRequired) {
        return false;
      }
    }

    // The subtype must accept all parameters of the supertype.
    assert(fIndex == fParameters.length);
    if (gIndex < gParameters.length) {
      return false;
    }

    return true;
  }

  bool _isInterfaceSubtypeOf(
    InterfaceTypeImpl subType,
    InterfaceTypeImpl superType,
  ) {
    // Note: we should never reach `_isInterfaceSubtypeOf` with `i2 == Object`,
    // because top types are eliminated before `isSubtypeOf` calls this.
    // TODO(scheglov): Replace with assert().
    if (identical(subType, superType) || superType.isDartCoreObject) {
      return true;
    }

    // Object cannot subtype anything but itself (handled above).
    if (subType.isDartCoreObject) {
      return false;
    }

    var subElement = subType.element;
    var superElement = superType.element;
    if (identical(subElement, superElement)) {
      return _interfaceArguments(superElement, subType, superType);
    }

    // Classes types cannot subtype `Function` or vice versa.
    if (subType.isDartCoreFunction || superType.isDartCoreFunction) {
      return false;
    }

    for (var interface in subElement.allSupertypes) {
      if (identical(interface.element, superElement)) {
        var substitution = Substitution.fromInterfaceType(subType);
        var substitutedInterface = substitution.mapInterfaceType(interface);
        return _interfaceArguments(
          superElement,
          substitutedInterface,
          superType,
        );
      }
    }

    return false;
  }

  /// Check that [subType] is a subtype of [superType].
  bool _isRecordSubtypeOf(RecordTypeImpl subType, RecordTypeImpl superType) {
    var subPositional = subType.positionalFields;
    var superPositional = superType.positionalFields;
    if (subPositional.length != superPositional.length) {
      return false;
    }

    var subNamed = subType.namedFields;
    var superNamed = superType.namedFields;
    if (subNamed.length != superNamed.length) {
      return false;
    }

    for (var i = 0; i < subPositional.length; i++) {
      var subField = subPositional[i];
      var superField = superPositional[i];
      if (!isSubtypeOf(subField.type, superField.type)) {
        return false;
      }
    }

    for (var i = 0; i < subNamed.length; i++) {
      var subField = subNamed[i];
      var superField = superNamed[i];
      if (subField.name != superField.name) {
        return false;
      }
      if (!isSubtypeOf(subField.type, superField.type)) {
        return false;
      }
    }

    return true;
  }
}
