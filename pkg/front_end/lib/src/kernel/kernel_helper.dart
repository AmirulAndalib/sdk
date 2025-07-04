// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';
import 'package:kernel/clone.dart' show CloneVisitorNotMembers;
import 'package:kernel/type_algebra.dart' show Substitution;
import 'package:kernel/type_environment.dart';

import '../base/messages.dart';
import '../builder/library_builder.dart';

/// Data for clone default values for synthesized function nodes once the
/// original default values have been computed.
///
/// This is used for constructors in unnamed mixin application, which are
/// created from the constructors in the superclass, and for tear off lowerings
/// for redirecting factories, which are created from the effective target
/// constructor.
class DelayedDefaultValueCloner {
  /// The original constructor or procedure.
  final Member original;

  /// The synthesized constructor or procedure.
  final Member synthesized;

  /// If `true`, the [_synthesized] is guaranteed to have the same parameters in
  /// the same order as [_original]. Otherwise [_original] is only guaranteed to
  /// be callable from [_synthesized], meaning that is has at most the same
  /// number of positional parameters and a, possibly reordered, subset of the
  /// named parameters.
  final bool identicalSignatures;

  final List<int?>? _positionalSuperParameters;

  final List<String>? _namedSuperParameters;

  bool isOutlineNode;

  final LibraryBuilder _libraryBuilder;

  CloneVisitorNotMembers? _cloner;

  /// Set to `true` we default values have been cloned, ensuring that cloning
  /// isn't performed twice.
  bool _hasCloned = false;

  DelayedDefaultValueCloner(this.original, this.synthesized,
      {this.identicalSignatures = true,
      List<int?>? positionalSuperParameters = null,
      List<String>? namedSuperParameters = null,
      this.isOutlineNode = false,
      required LibraryBuilder libraryBuilder})
      : _positionalSuperParameters = positionalSuperParameters,
        _namedSuperParameters = namedSuperParameters,
        _libraryBuilder = libraryBuilder,
        // Check that [positionalSuperParameters] and [namedSuperParameters] are
        // provided or omitted together.
        assert((positionalSuperParameters == null) ==
            (namedSuperParameters == null)),
        assert(positionalSuperParameters == null ||
            () {
              // Check that [positionalSuperParameters] is sorted if it's
              // provided. The `null` values are allowed in-between the sorted
              // values.
              for (int i = -1, j = 0;
                  j < positionalSuperParameters.length;
                  j++) {
                int? currentValue = positionalSuperParameters[j];
                if (currentValue != null) {
                  if (i == -1 || positionalSuperParameters[i]! < currentValue) {
                    i = j;
                  } else {
                    return false;
                  }
                }
              }
              return true;
            }()),
        assert(namedSuperParameters == null ||
            () {
              // Check that [namedSuperParameters] are the subset of and in the
              // same order as the named parameters of [_synthesized].
              int superParameterIndex = 0;
              for (int namedParameterIndex = 0;
                  namedParameterIndex <
                          synthesized.function!.namedParameters.length &&
                      superParameterIndex < namedSuperParameters.length;
                  namedParameterIndex++) {
                if (synthesized
                        .function!.namedParameters[namedParameterIndex].name ==
                    namedSuperParameters[superParameterIndex]) {
                  ++superParameterIndex;
                }
              }
              return superParameterIndex == namedSuperParameters.length;
            }());

  void cloneDefaultValues(TypeEnvironment typeEnvironment) {
    if (_hasCloned) return;

    // TODO(ahe): It is unclear if it is legal to use type parameters in
    // default values, but Fasta is currently allowing it, and the VM
    // accepts it. If it isn't legal, the we can speed this up by using a
    // single cloner without substitution.

    // For mixin application constructors, the argument count is the same, but
    // for redirecting tear off lowerings, the argument count of the tear off
    // can be less than that of the redirection target or, in errors cases, be
    // unrelated.

    FunctionNode _original = original.function!;
    FunctionNode _synthesized = synthesized.function!;

    if (identicalSignatures) {
      assert(_positionalSuperParameters != null ||
          _synthesized.positionalParameters.length ==
              _original.positionalParameters.length);
      List<int?>? positionalSuperParameters = _positionalSuperParameters;
      for (int i = 0; i < _original.positionalParameters.length; i++) {
        if (positionalSuperParameters == null) {
          _cloneInitializer(_original.positionalParameters[i],
              _synthesized.positionalParameters[i]);
        } else if (i < positionalSuperParameters.length) {
          int? superParameterIndex = positionalSuperParameters[i];
          if (superParameterIndex != null) {
            VariableDeclaration originalParameter =
                _original.positionalParameters[i];
            VariableDeclaration synthesizedParameter =
                _synthesized.positionalParameters[superParameterIndex];
            _cloneDefaultValueForSuperParameters(
                originalParameter, synthesizedParameter, typeEnvironment,
                isOptional:
                    superParameterIndex >= _synthesized.requiredParameterCount);
          }
        }
      }

      assert(_namedSuperParameters != null ||
          _synthesized.namedParameters.length ==
              _original.namedParameters.length);
      List<String>? namedSuperParameters = _namedSuperParameters;
      int superParameterNameIndex = 0;
      Map<String, int> originalNamedParameterIndices = {};
      for (int i = 0; i < _original.namedParameters.length; i++) {
        originalNamedParameterIndices[_original.namedParameters[i].name!] = i;
      }
      for (int i = 0; i < _synthesized.namedParameters.length; i++) {
        if (namedSuperParameters == null) {
          _cloneInitializer(
              _original.namedParameters[i], _synthesized.namedParameters[i]);
        } else if (superParameterNameIndex < namedSuperParameters.length &&
            namedSuperParameters[superParameterNameIndex] ==
                _synthesized.namedParameters[i].name) {
          String superParameterName =
              namedSuperParameters[superParameterNameIndex];
          int? originalNamedParameterIndex =
              originalNamedParameterIndices[superParameterName];
          if (originalNamedParameterIndex != null) {
            VariableDeclaration originalParameter =
                _original.namedParameters[originalNamedParameterIndex];
            VariableDeclaration synthesizedParameter =
                _synthesized.namedParameters[i];
            _cloneDefaultValueForSuperParameters(
                originalParameter, synthesizedParameter, typeEnvironment,
                isOptional: !synthesizedParameter.isRequired);
          } else {
            // TODO(cstefantsova): Handle the erroneous case of missing names.
          }
          superParameterNameIndex++;
        }
      }
    } else {
      for (int i = 0; i < _synthesized.positionalParameters.length; i++) {
        VariableDeclaration synthesizedParameter =
            _synthesized.positionalParameters[i];
        if (i < _original.positionalParameters.length) {
          if (i >= _synthesized.requiredParameterCount) {
            if (i < _original.requiredParameterCount) {
              // Coverage-ignore-block(suite): Not run.
              // Error case: use `null` as initializer.
              synthesizedParameter.initializer = new NullLiteral()
                ..parent = synthesizedParameter;
              if (synthesizedParameter.type.nullability !=
                  Nullability.nullable) {
                synthesizedParameter.isErroneouslyInitialized = true;
              }
            } else {
              _cloneInitializer(
                  _original.positionalParameters[i], synthesizedParameter);
            }
          }
        } else {
          if (i >= _synthesized.requiredParameterCount) {
            // Error case: use `null` as initializer.
            synthesizedParameter.initializer = new NullLiteral()
              ..parent = synthesizedParameter;
            if (synthesizedParameter.type.nullability != Nullability.nullable) {
              // Coverage-ignore-block(suite): Not run.
              synthesizedParameter.isErroneouslyInitialized = true;
            }
          }
        }
      }
      if (_synthesized.namedParameters.isNotEmpty) {
        Map<String, VariableDeclaration> originalParameters = {};
        for (int i = 0; i < _original.namedParameters.length; i++) {
          originalParameters[_original.namedParameters[i].name!] =
              _original.namedParameters[i];
        }
        for (int i = 0; i < _synthesized.namedParameters.length; i++) {
          VariableDeclaration synthesizedParameter =
              _synthesized.namedParameters[i];
          VariableDeclaration? originalParameter =
              originalParameters[synthesizedParameter.name!];
          if (originalParameter != null) {
            if (!originalParameter.isRequired &&
                !synthesizedParameter.isRequired) {
              _cloneInitializer(originalParameter, synthesizedParameter);
            }
          } else {
            if (!synthesizedParameter.isRequired) {
              // Error case: use `null` as initializer.
              synthesizedParameter.initializer = new NullLiteral()
                ..parent = synthesizedParameter;
              if (synthesizedParameter.type.nullability !=
                  Nullability.nullable) {
                synthesizedParameter.isErroneouslyInitialized = true;
              }
            }
          }
        }
      }
    }
    _hasCloned = true;
  }

  void _cloneInitializer(VariableDeclaration originalParameter,
      VariableDeclaration clonedParameter) {
    if (originalParameter.initializer != null) {
      CloneVisitorNotMembers cloner = _cloner ??= new CloneVisitorNotMembers();
      clonedParameter.initializer = cloner.clone(originalParameter.initializer!)
        ..parent = clonedParameter;
    }
    clonedParameter.isErroneouslyInitialized |=
        originalParameter.isErroneouslyInitialized;
  }

  void _cloneDefaultValueForSuperParameters(
      VariableDeclaration originalParameter,
      VariableDeclaration synthesizedParameter,
      TypeEnvironment typeEnvironment,
      {required bool isOptional}) {
    Expression? originalParameterInitializer = originalParameter.initializer;
    DartType? originalParameterInitializerType = originalParameterInitializer
        ?.getStaticType(new StaticTypeContext(synthesized, typeEnvironment));
    DartType synthesizedParameterType = synthesizedParameter.type;
    if (originalParameterInitializerType != null &&
        typeEnvironment.isSubtypeOf(
            originalParameterInitializerType, synthesizedParameterType)) {
      _cloneInitializer(originalParameter, synthesizedParameter);
    } else if (originalParameterInitializer == null && isOptional) {
      synthesizedParameter.initializer = new NullLiteral()
        ..parent = synthesizedParameter;
    } else {
      synthesizedParameter.hasDeclaredInitializer = false;
      if (synthesizedParameterType.isPotentiallyNonNullable) {
        _libraryBuilder.addProblem(
            templateOptionalSuperParameterWithoutInitializer.withArguments(
                synthesizedParameter.type, synthesizedParameter.name!),
            synthesizedParameter.fileOffset,
            synthesizedParameter.name?.length ?? 1,
            _libraryBuilder.fileUri);
        synthesizedParameter.isErroneouslyInitialized = true;
      }
    }
  }

  @override
  String toString() {
    return "DelayedDefaultValueCloner(original=${original}, "
        "synthesized=${synthesized})";
  }
}

class TypeDependency {
  final Member synthesized;
  final Member original;
  final Substitution substitution;
  final bool copyReturnType;
  bool _hasBeenInferred = false;

  TypeDependency(this.synthesized, this.original, this.substitution,
      {required this.copyReturnType});

  void copyInferred() {
    if (_hasBeenInferred) return;
    for (int i = 0; i < original.function!.positionalParameters.length; i++) {
      VariableDeclaration synthesizedParameter =
          synthesized.function!.positionalParameters[i];
      VariableDeclaration originalParameter =
          original.function!.positionalParameters[i];
      synthesizedParameter.type =
          substitution.substituteType(originalParameter.type);
      if (!synthesizedParameter.hasDeclaredInitializer) {
        synthesizedParameter.hasDeclaredInitializer =
            originalParameter.hasDeclaredInitializer;
      }
    }
    for (int i = 0; i < original.function!.namedParameters.length; i++) {
      VariableDeclaration synthesizedParameter =
          synthesized.function!.namedParameters[i];
      VariableDeclaration originalParameter =
          original.function!.namedParameters[i];
      synthesizedParameter.type =
          substitution.substituteType(originalParameter.type);
      if (!synthesizedParameter.hasDeclaredInitializer) {
        synthesizedParameter.hasDeclaredInitializer =
            originalParameter.hasDeclaredInitializer;
      }
    }
    if (copyReturnType) {
      synthesized.function!.returnType =
          substitution.substituteType(original.function!.returnType);
    }
    _hasBeenInferred = true;
  }
}

// Coverage-ignore(suite): Not run.
/// Copies properties, function parameters and body from the [augmentation]
/// procedure to its [origin].
void finishProcedureAugmentation(Procedure origin, Procedure augmentation) {
  origin.fileUri = augmentation.fileUri;
  origin.fileStartOffset = augmentation.fileStartOffset;
  origin.fileOffset = augmentation.fileOffset;
  origin.fileEndOffset = augmentation.fileEndOffset;

  origin.isAbstract = augmentation.isAbstract;
  origin.isExternal = augmentation.isExternal;
  origin.function = augmentation.function;
  origin.function.parent = origin;
}
