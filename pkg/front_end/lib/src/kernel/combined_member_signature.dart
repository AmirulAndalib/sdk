// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';
import 'package:kernel/clone.dart' show CloneVisitorNotMembers;
import 'package:kernel/core_types.dart' show CoreTypes;
import 'package:kernel/reference_from_index.dart';
import 'package:kernel/src/nnbd_top_merge.dart';
import 'package:kernel/src/norm.dart';
import 'package:kernel/src/types.dart' show Types;
import 'package:kernel/type_algebra.dart';

import '../base/problems.dart' show unhandled;
import '../builder/declaration_builders.dart';
import '../source/source_class_builder.dart';
import 'hierarchy/class_member.dart';
import 'hierarchy/hierarchy_builder.dart';
import 'hierarchy/members_builder.dart';
import 'member_covariance.dart';

/// Class used for computing and inspecting the combined member signature for
/// a set of overridden/inherited [ClassMember]s.
abstract class CombinedMemberSignatureBase {
  /// The class members builder used for building this class.
  final ClassMembersBuilder membersBuilder;

  /// The list of the members inherited into or overridden in
  /// [extensionTypeDeclarationBuilder].
  final List<ClassMember> members;

  /// The target declaration for the combined member signature.
  ///
  /// The [_memberTypes] are computed in terms of each member is inherited into
  /// [declarationBuilder].
  ///
  /// [declarationBuilder] is also used for determining whether the combined
  /// member signature should be computed using nnbd or legacy semantics.
  DeclarationBuilder get declarationBuilder;

  /// If `true` the combined member signature is for the setter aspect of the
  /// members. Otherwise it is for the getter/method aspect of the members.
  final bool forSetter;

  /// The index within [members] for the member whose type is the most specific
  /// among [members]. If `null`, the combined member signature is not defined
  /// for [members] in [extensionTypeDeclarationBuilder].
  ///
  /// For the legacy computation, the type of this member defines the combined
  /// member signature.
  ///
  /// For the nnbd computation, this is one of the members whose type define
  /// the combined member signature, and the indices of the remaining members
  /// are stored in [_mutualSubtypes].
  int? _canonicalMemberIndex;

  /// For the nnbd computation, this maps each distinct but most specific member
  /// type to the index of one of the [members] with that type.
  ///
  /// If there is only one most specific member type, this is `null`.
  Map<DartType, int>? _mutualSubtypes;

  /// Cache for the types of [members] as inherited into
  /// [extensionTypeDeclarationBuilder].
  List<DartType?>? _memberTypes;

  /// If `true` the combined member signature type has been computed.
  ///
  /// Note that the combined member signature type might be undefined in which
  /// case [_combinedMemberSignatureType] is `null`.
  bool _isCombinedMemberSignatureTypeComputed = false;

  /// Cache the computed combined member signature type.
  ///
  /// If the combined member signature type is undefined this is set to `null`.
  DartType? _combinedMemberSignatureType;

  /// The indices for the members whose type needed legacy erasure.
  ///
  /// This is fully computed when [combinedMemberSignatureType] has been
  /// computed.
  Set<int>? _neededLegacyErasureIndices;

  bool _neededNnbdTopMerge = false;

  bool _needsCovarianceMerging = false;

  bool _isCombinedMemberSignatureCovarianceComputed = false;

  Covariance? _combinedMemberSignatureCovariance;

  /// Creates a [CombinedMemberSignatureBase] whose canonical member is already
  /// defined.
  CombinedMemberSignatureBase.internal(
      this.membersBuilder, this._canonicalMemberIndex, this.members,
      {required this.forSetter});

  /// Creates a [CombinedMemberSignatureBase] for [members] inherited into
  /// [extensionTypeDeclarationBuilder].
  ///
  /// If [forSetter] is `true`, contravariance of the setter types is used to
  /// compute the most specific member type. Otherwise covariance of the getter
  /// types or function types is used.
  CombinedMemberSignatureBase(this.membersBuilder, this.members,
      {required this.forSetter}) {
    int? bestSoFarIndex;
    if (members.length == 1) {
      bestSoFarIndex = 0;
    } else {
      DartType? bestTypeSoFar;
      for (int candidateIndex = members.length - 1;
          candidateIndex >= 0;
          candidateIndex--) {
        DartType candidateType = getMemberType(candidateIndex);
        if (bestSoFarIndex == null) {
          bestTypeSoFar = candidateType;
          bestSoFarIndex = candidateIndex;
        } else {
          if (_isMoreSpecific(candidateType, bestTypeSoFar!, forSetter)) {
            if (_isMoreSpecific(bestTypeSoFar, candidateType, forSetter)) {
              if (_mutualSubtypes == null) {
                _mutualSubtypes = {
                  bestTypeSoFar: bestSoFarIndex,
                  candidateType: candidateIndex
                };
              } else {
                _mutualSubtypes![candidateType] = candidateIndex;
              }
            } else {
              _mutualSubtypes = null;
            }
            bestSoFarIndex = candidateIndex;
            bestTypeSoFar = candidateType;
          }
        }
      }
      if (_mutualSubtypes?.length == 1) {
        /// If all mutual subtypes have the same type, the type should not
        /// be normalized.
        _mutualSubtypes = null;
      }
      if (bestSoFarIndex != null) {
        for (int candidateIndex = 0;
            candidateIndex < members.length;
            candidateIndex++) {
          DartType candidateType = getMemberType(candidateIndex);
          if (!_isMoreSpecific(bestTypeSoFar!, candidateType, forSetter)) {
            int? favoredIndex =
                getOverlookedOverrideProblemChoice(declarationBuilder);
            bestSoFarIndex = favoredIndex;
            _mutualSubtypes = null;
            break;
          }
        }
      }
    }

    _canonicalMemberIndex = bestSoFarIndex;
  }

  /// The member within [members] type is the most specific among [members].
  /// If `null`, the combined member signature is not defined for [members] in
  /// [extensionTypeDeclarationBuilder].
  ///
  /// For the legacy computation, the type of this member defines the combined
  /// member signature.
  ///
  /// For the nnbd computation, this is one of the members whose type define
  /// the combined member signature, and the indices of the all members whose
  /// type define the combined member signature are in [mutualSubtypeIndices].
  ClassMember? get canonicalMember =>
      _canonicalMemberIndex != null ? members[_canonicalMemberIndex!] : null;

  /// The index within [members] for the member whose type is the most specific
  /// among [members]. If `null`, the combined member signature is not defined
  /// for [members] in [extensionTypeDeclarationBuilder].
  ///
  /// For the legacy computation, the type of this member defines the combined
  /// member signature.
  ///
  /// For the nnbd computation, this is one of the members whose type define
  /// the combined member signature, and the indices of the all members whose
  /// type define the combined member signature are in [mutualSubtypeIndices].
  int? get canonicalMemberIndex => _canonicalMemberIndex;

  ClassHierarchyBuilder get hierarchy => membersBuilder.hierarchyBuilder;

  CoreTypes get _coreTypes => hierarchy.coreTypes;

  Types get _types => hierarchy.types;

  Member _getMember(int index) {
    ClassMember candidate = members[index];
    return candidate.getMember(membersBuilder);
  }

  /// Returns `true` if legacy erasure was needed to compute the combined
  /// member signature type.
  ///
  /// Legacy erasure is considered need of if the used of it resulted in a
  /// different type.
  bool get neededLegacyErasure {
    _ensureCombinedMemberSignatureType();
    return _neededLegacyErasureIndices
            // Coverage-ignore(suite): Not run.
            ?.contains(canonicalMemberIndex) ??
        false;
  }

  /// Returns `true` if nnbd top merge and normalization was needed to compute
  /// the combined member signature type.
  bool get neededNnbdTopMerge {
    _ensureCombinedMemberSignatureType();
    return _neededNnbdTopMerge;
  }

  /// Returns the this type of the [declarationBuilder].
  TypeDeclarationType get thisType;

  /// Returns `true` if the canonical member is declared in
  /// [declarationBuilder].
  bool get isCanonicalMemberDeclared;

  /// Returns `true` if the canonical member is the 0th.
  // TODO(johnniwinther): This is currently used under the assumption that the
  // 0th member is either from the superclass or the one found if looked up
  // the class hierarchy. This is a very brittle assumption.
  bool get isCanonicalMemberFirst => _canonicalMemberIndex == 0;

  /// Returns type of the [index]th member in [members] as inherited in
  /// [extensionTypeDeclarationBuilder].
  DartType getMemberType(int index) {
    _memberTypes ??= new List<DartType?>.filled(members.length, null);
    DartType? candidateType = _memberTypes![index];
    if (candidateType == null) {
      Member target = _getMember(index);
      candidateType = _computeMemberType(target);
      _memberTypes![index] = candidateType;
    }
    return candidateType;
  }

  DartType getMemberTypeForTarget(Member target) {
    return _computeMemberType(target);
  }

  void _ensureCombinedMemberSignatureType() {
    if (!_isCombinedMemberSignatureTypeComputed) {
      _isCombinedMemberSignatureTypeComputed = true;
      if (_canonicalMemberIndex == null) {
        return null;
      }
      DartType canonicalMemberType =
          _combinedMemberSignatureType = getMemberType(_canonicalMemberIndex!);
      if (_mutualSubtypes != null) {
        _combinedMemberSignatureType =
            norm(_coreTypes, _combinedMemberSignatureType!);
        for (int index in _mutualSubtypes!.values) {
          if (_canonicalMemberIndex != index) {
            _combinedMemberSignatureType = nnbdTopMerge(
                _coreTypes,
                _combinedMemberSignatureType!,
                norm(_coreTypes, getMemberType(index)));
            assert(
                _combinedMemberSignatureType != null,
                "No combined member signature found for "
                "${_mutualSubtypes!.values.map((int i) => getMemberType(i))} "
                "for members ${members}");
          }
        }
        _neededNnbdTopMerge =
            canonicalMemberType != _combinedMemberSignatureType;
      }
    }
  }

  /// Returns the type of the combined member signature, if defined.
  DartType? get combinedMemberSignatureType {
    _ensureCombinedMemberSignatureType();
    return _combinedMemberSignatureType;
  }

  Covariance _getMemberCovariance(int index) {
    ClassMember candidate = members[index];
    return candidate.getCovariance(membersBuilder);
  }

  void _ensureCombinedMemberSignatureCovariance() {
    if (!_isCombinedMemberSignatureCovarianceComputed) {
      _isCombinedMemberSignatureCovarianceComputed = true;
      if (canonicalMemberIndex == null) {
        return;
      }
      Covariance canonicalMemberCovariance =
          _combinedMemberSignatureCovariance =
              _getMemberCovariance(canonicalMemberIndex!);
      if (members.length == 1) {
        return;
      }
      for (int index = 0; index < members.length; index++) {
        if (index != canonicalMemberIndex) {
          _combinedMemberSignatureCovariance =
              _combinedMemberSignatureCovariance!
                  .merge(_getMemberCovariance(index));
        }
      }
      _needsCovarianceMerging =
          canonicalMemberCovariance != _combinedMemberSignatureCovariance;
    }
  }

  // Returns `true` if the covariance of [members] needs to be merged into
  // the combined member signature.
  bool get needsCovarianceMerging {
    if (members.length != 1) {
      _ensureCombinedMemberSignatureCovariance();
    }
    return _needsCovarianceMerging;
  }

  /// Returns [Covariance] for the combined member signature.
  Covariance? get combinedMemberSignatureCovariance {
    _ensureCombinedMemberSignatureCovariance();
    return _combinedMemberSignatureCovariance;
  }

  /// Returns the type of the combined member signature, if defined, with
  /// all method type parameters substituted with [typeParameters].
  ///
  /// This is used for inferring types on a declared member from the type of the
  /// combined member signature.
  DartType? getCombinedSignatureTypeInContext(
      List<TypeParameter> typeParameters) {
    DartType? type = combinedMemberSignatureType;
    if (type == null) {
      return null;
    }
    int typeParameterCount = typeParameters.length;
    if (type is FunctionType) {
      List<StructuralParameter> signatureTypeParameters = type.typeParameters;
      if (typeParameterCount != signatureTypeParameters.length) {
        return null;
      }
      if (typeParameterCount == 0) {
        return type;
      }
      List<DartType> types = [
        for (TypeParameter parameter in typeParameters)
          new TypeParameterType.withDefaultNullability(parameter)
      ];
      FunctionTypeInstantiator instantiator =
          new FunctionTypeInstantiator.fromIterables(
              signatureTypeParameters, types);
      for (int i = 0; i < typeParameterCount; i++) {
        DartType typeParameterBound = typeParameters[i].bound;
        DartType signatureTypeParameterBound =
            instantiator.substitute(signatureTypeParameters[i].bound);
        if (!_types
            .performMutualSubtypesCheck(
                typeParameterBound, signatureTypeParameterBound)
            .isSuccess()) {
          return null;
        }
      }
      return instantiator.substitute(type.withoutTypeParameters);
    }
    // Coverage-ignore(suite): Not run.
    else if (typeParameterCount != 0) {
      return null;
    }
    return type;
  }

  /// Create a member signature with the [combinedMemberSignatureType] using the
  /// [canonicalMember] as member signature origin.
  Procedure? createMemberFromSignature(
      FileUriNode declarationNode, IndexedContainer? indexedContainer,
      {bool copyLocation = true}) {
    if (canonicalMemberIndex == null) {
      return null;
    }
    Member member = _getMember(canonicalMemberIndex!);
    Procedure combinedMemberSignature;
    if (member is Procedure) {
      switch (member.kind) {
        case ProcedureKind.Getter:
          combinedMemberSignature = _createGetterMemberSignature(
              declarationNode,
              indexedContainer,
              member,
              combinedMemberSignatureType!,
              copyLocation: copyLocation);
          break;
        case ProcedureKind.Setter:
          VariableDeclaration parameter =
              member.function.positionalParameters.first;
          combinedMemberSignature = _createSetterMemberSignature(
              declarationNode,
              indexedContainer,
              member,
              combinedMemberSignatureType!,
              isCovariantByClass: parameter.isCovariantByClass,
              isCovariantByDeclaration: parameter.isCovariantByDeclaration,
              parameter: parameter,
              copyLocation: copyLocation);
          break;
        case ProcedureKind.Method:
        case ProcedureKind.Operator:
          combinedMemberSignature = _createMethodSignature(
              declarationNode,
              indexedContainer,
              member,
              combinedMemberSignatureType as FunctionType,
              copyLocation: copyLocation);
          break;
        // Coverage-ignore(suite): Not run.
        case ProcedureKind.Factory:
          throw new UnsupportedError(
              'Unexpected canonical member kind ${member.kind} for $member');
      }
    } else if (member is Field) {
      if (forSetter) {
        combinedMemberSignature = _createSetterMemberSignature(declarationNode,
            indexedContainer, member, combinedMemberSignatureType!,
            isCovariantByClass: member.isCovariantByClass,
            isCovariantByDeclaration: member.isCovariantByDeclaration,
            copyLocation: copyLocation);
      } else {
        combinedMemberSignature = _createGetterMemberSignature(declarationNode,
            indexedContainer, member, combinedMemberSignatureType!,
            copyLocation: copyLocation);
      }
    } else {
      throw new UnsupportedError(
          'Unexpected canonical member $member (${member.runtimeType})');
    }
    combinedMemberSignatureCovariance!.applyCovariance(combinedMemberSignature);
    return combinedMemberSignature;
  }

  /// Creates a getter member signature for [member] with the given
  /// [type].
  Procedure _createGetterMemberSignature(FileUriNode declarationNode,
      IndexedContainer? indexedContainer, Member member, DartType type,
      {required bool copyLocation}) {
    Reference? reference = indexedContainer?.lookupGetterReference(member.name);

    Uri fileUri;
    int startFileOffset;
    int fileOffset;
    if (copyLocation) {
      // Coverage-ignore-block(suite): Not run.
      fileUri = member.fileUri;
      startFileOffset =
          member is Procedure ? member.fileStartOffset : member.fileOffset;
      fileOffset = member.fileOffset;
    } else {
      fileUri = declarationNode.fileUri;
      fileOffset = startFileOffset = declarationNode.fileOffset;
    }
    return new Procedure(
      member.name,
      ProcedureKind.Getter,
      new FunctionNode(null, returnType: type),
      isAbstract: true,
      fileUri: fileUri,
      reference: reference,
      isSynthetic: true,
      stubKind: ProcedureStubKind.MemberSignature,
      stubTarget: member.memberSignatureOrigin ?? member,
    )
      ..fileStartOffset = startFileOffset
      ..fileOffset = fileOffset
      ..parent = declarationNode;
  }

  /// Creates a setter member signature for [member] with the given
  /// [type]. The flags of parameter is set according to
  /// [isCovariantByDeclaration] and [isCovariantByClass] and the name of the
  /// [parameter] is used, if provided.
  Procedure _createSetterMemberSignature(FileUriNode declarationNode,
      IndexedContainer? indexedContainer, Member member, DartType type,
      {required bool isCovariantByDeclaration,
      required bool isCovariantByClass,
      VariableDeclaration? parameter,
      required bool copyLocation}) {
    Reference? reference = indexedContainer?.lookupSetterReference(member.name);
    Uri fileUri;
    int startFileOffset;
    int fileOffset;
    if (copyLocation) {
      // Coverage-ignore-block(suite): Not run.
      fileUri = member.fileUri;
      startFileOffset =
          member is Procedure ? member.fileStartOffset : member.fileOffset;
      fileOffset = member.fileOffset;
    } else {
      fileUri = declarationNode.fileUri;
      fileOffset = startFileOffset = declarationNode.fileOffset;
    }
    return new Procedure(
      member.name,
      ProcedureKind.Setter,
      new FunctionNode(null,
          returnType: const VoidType(),
          positionalParameters: [
            new VariableDeclaration(parameter?.name ?? 'value',
                type: type, isCovariantByDeclaration: isCovariantByDeclaration)
              ..isCovariantByClass = isCovariantByClass
              ..fileOffset = copyLocation
                  ?
                  // Coverage-ignore(suite): Not run.
                  parameter?.fileOffset ?? fileOffset
                  : fileOffset
          ]),
      isAbstract: true,
      fileUri: fileUri,
      reference: reference,
      isSynthetic: true,
      stubKind: ProcedureStubKind.MemberSignature,
      stubTarget: member.memberSignatureOrigin ?? member,
    )
      ..fileStartOffset = startFileOffset
      ..fileOffset = fileOffset
      ..parent = declarationNode;
  }

  Procedure _createMethodSignature(
      FileUriNode declarationNode,
      IndexedContainer? indexedContainer,
      Procedure procedure,
      FunctionType functionType,
      {required bool copyLocation}) {
    Reference? reference =
        indexedContainer?.lookupGetterReference(procedure.name);
    Uri fileUri;
    int startFileOffset;
    int fileOffset;
    if (copyLocation) {
      // Coverage-ignore-block(suite): Not run.
      fileUri = procedure.fileUri;
      startFileOffset = procedure.fileStartOffset;
      fileOffset = procedure.fileOffset;
    } else {
      fileUri = declarationNode.fileUri;
      fileOffset = startFileOffset = declarationNode.fileOffset;
    }
    FunctionNode function = procedure.function;
    List<VariableDeclaration> positionalParameters = [];
    FreshTypeParametersFromStructuralParameters freshTypeParameters =
        getFreshTypeParametersFromStructuralParameters(
            functionType.typeParameters);
    CloneVisitorNotMembers cloner = new CloneVisitorNotMembers();
    for (int i = 0; i < function.positionalParameters.length; i++) {
      VariableDeclaration parameter = function.positionalParameters[i];
      DartType parameterType =
          freshTypeParameters.substitute(functionType.positionalParameters[i]);
      positionalParameters.add(new VariableDeclaration(parameter.name,
          type: parameterType,
          isCovariantByDeclaration: parameter.isCovariantByDeclaration,
          initializer: cloner.cloneOptional(parameter.initializer))
        ..hasDeclaredInitializer = parameter.hasDeclaredInitializer
        ..isCovariantByClass = parameter.isCovariantByClass
        ..fileOffset = copyLocation
            ?
            // Coverage-ignore(suite): Not run.
            parameter.fileOffset
            : fileOffset);
    }
    List<VariableDeclaration> namedParameters = [];
    int namedParameterCount = function.namedParameters.length;
    if (namedParameterCount == 1) {
      NamedType namedType = functionType.namedParameters.first;
      VariableDeclaration parameter = function.namedParameters.first;
      namedParameters.add(new VariableDeclaration(parameter.name,
          type: freshTypeParameters.substitute(namedType.type),
          isRequired: namedType.isRequired,
          isCovariantByDeclaration: parameter.isCovariantByDeclaration,
          initializer: cloner.cloneOptional(parameter.initializer))
        ..hasDeclaredInitializer = parameter.hasDeclaredInitializer
        ..isCovariantByClass = parameter.isCovariantByClass
        ..fileOffset = copyLocation
            ?
            // Coverage-ignore(suite): Not run.
            parameter.fileOffset
            : fileOffset);
    } else if (namedParameterCount > 1) {
      Map<String, NamedType> namedTypes = {};
      for (NamedType namedType in functionType.namedParameters) {
        namedTypes[namedType.name] = namedType;
      }
      for (int i = 0; i < namedParameterCount; i++) {
        VariableDeclaration parameter = function.namedParameters[i];
        NamedType namedParameterType = namedTypes[parameter.name]!;
        namedParameters.add(new VariableDeclaration(parameter.name,
            type: freshTypeParameters.substitute(namedParameterType.type),
            isRequired: namedParameterType.isRequired,
            isCovariantByDeclaration: parameter.isCovariantByDeclaration,
            initializer: cloner.cloneOptional(parameter.initializer))
          ..hasDeclaredInitializer = parameter.hasDeclaredInitializer
          ..isCovariantByClass = parameter.isCovariantByClass
          ..fileOffset = copyLocation
              ?
              // Coverage-ignore(suite): Not run.
              parameter.fileOffset
              : fileOffset);
      }
    }
    return new Procedure(
      procedure.name,
      procedure.kind,
      new FunctionNode(null,
          typeParameters: freshTypeParameters.freshTypeParameters,
          returnType: freshTypeParameters.substitute(functionType.returnType),
          positionalParameters: positionalParameters,
          namedParameters: namedParameters,
          requiredParameterCount: function.requiredParameterCount),
      isAbstract: true,
      fileUri: fileUri,
      reference: reference,
      isSynthetic: true,
      stubKind: ProcedureStubKind.MemberSignature,
      stubTarget: procedure.memberSignatureOrigin ?? procedure,
    )
      ..fileStartOffset = startFileOffset
      ..fileOffset = fileOffset
      ..parent = declarationNode;
  }

  DartType _computeMemberType(Member member) {
    DartType type;
    if (member is Procedure) {
      if (member.isGetter) {
        type = member.getterType;
      } else if (member.isSetter) {
        type = member.setterType;
      } else {
        // TODO(johnniwinther): Why do we need the specific nullability here?
        type = member.getterType.withDeclaredNullability(
            declarationBuilder.libraryBuilder.library.nonNullable);
      }
    } else if (member is Field) {
      type = member.type;
    } else {
      unhandled("${member.runtimeType}", "$member",
          declarationBuilder.fileOffset, declarationBuilder.fileUri);
    }
    if (member.enclosingTypeDeclaration!.typeParameters.isEmpty) {
      return type;
    }
    TypeDeclarationType instance = hierarchy.getTypeAsInstanceOf(
        thisType, member.enclosingTypeDeclaration!)!;
    return Substitution.fromTypeDeclarationType(instance).substituteType(type);
  }

  bool _isMoreSpecific(DartType a, DartType b, bool forSetter) {
    if (forSetter) {
      return _types.isSubtypeOf(b, a);
    } else {
      return _types.isSubtypeOf(a, b);
    }
  }
}

class CombinedClassMemberSignature extends CombinedMemberSignatureBase {
  final ClassBuilder classBuilder;

  /// Cache for the this type of [classBuilder].
  InterfaceType? _thisType;

  /// Creates a [CombinedClassMemberSignature] whose canonical member is already
  /// defined.
  CombinedClassMemberSignature.internal(ClassMembersBuilder membersBuilder,
      this.classBuilder, int? canonicalMemberIndex, List<ClassMember> members,
      {required bool forSetter})
      : super.internal(membersBuilder, canonicalMemberIndex, members,
            forSetter: forSetter);

  /// Creates a [CombinedClassMemberSignature] for [members] inherited into
  /// [classBuilder].
  ///
  /// If [forSetter] is `true`, contravariance of the setter types is used to
  /// compute the most specific member type. Otherwise covariance of the getter
  /// types or function types is used.
  CombinedClassMemberSignature(ClassMembersBuilder membersBuilder,
      this.classBuilder, List<ClassMember> members,
      {required bool forSetter})
      : super(membersBuilder, members, forSetter: forSetter);

  @override
  DeclarationBuilder get declarationBuilder => classBuilder;

  /// The this type of [classBuilder].
  @override
  InterfaceType get thisType {
    return _thisType ??=
        _coreTypes.thisInterfaceType(classBuilder.cls, Nullability.nonNullable);
  }

  /// Returns `true` if the canonical member is declared in
  /// [declarationBuilder].
  @override
  bool get isCanonicalMemberDeclared {
    return _canonicalMemberIndex != null &&
        _getMember(_canonicalMemberIndex!).enclosingClass == classBuilder.cls;
  }
}

class CombinedExtensionTypeMemberSignature extends CombinedMemberSignatureBase {
  final ExtensionTypeDeclarationBuilder extensionTypeDeclarationBuilder;

  /// Cache for the this type of [extensionTypeDeclarationBuilder].
  ExtensionType? _thisType;

  /// Creates a [CombinedClassMemberSignature] for [members] inherited into
  /// [extensionTypeDeclarationBuilder].
  ///
  /// If [forSetter] is `true`, contravariance of the setter types is used to
  /// compute the most specific member type. Otherwise covariance of the getter
  /// types or function types is used.
  CombinedExtensionTypeMemberSignature(ClassMembersBuilder membersBuilder,
      this.extensionTypeDeclarationBuilder, List<ClassMember> members,
      {required bool forSetter})
      : super(membersBuilder, members, forSetter: forSetter);

  @override
  DeclarationBuilder get declarationBuilder => extensionTypeDeclarationBuilder;

  /// The this type of [extensionTypeDeclarationBuilder].
  @override
  ExtensionType get thisType {
    return _thisType ??= _coreTypes.thisExtensionType(
        extensionTypeDeclarationBuilder.extensionTypeDeclaration,
        Nullability.nonNullable);
  }

  @override
  bool get isCanonicalMemberDeclared => false;
}
