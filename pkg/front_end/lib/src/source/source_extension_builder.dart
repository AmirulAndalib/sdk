// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';

import '../base/modifiers.dart';
import '../base/name_space.dart';
import '../base/problems.dart';
import '../base/scope.dart';
import '../builder/builder.dart';
import '../builder/declaration_builders.dart';
import '../builder/library_builder.dart';
import '../builder/metadata_builder.dart';
import '../builder/type_builder.dart';
import '../codes/cfe_codes.dart'
    show
        messagePatchDeclarationMismatch,
        messagePatchDeclarationOrigin,
        messagePatchExtensionOrigin,
        messagePatchExtensionTypeParametersMismatch,
        noLength;
import '../fragment/fragment.dart';
import '../kernel/body_builder_context.dart';
import '../kernel/kernel_helper.dart';
import 'name_scheme.dart';
import 'source_builder_mixins.dart';
import 'source_library_builder.dart';
import 'source_member_builder.dart';
import 'type_parameter_scope_builder.dart';

class SourceExtensionBuilder extends ExtensionBuilderImpl
    with SourceDeclarationBuilderMixin {
  @override
  final SourceLibraryBuilder parent;

  final int _nameOffset;

  @override
  final Uri fileUri;

  final Modifiers _modifiers;

  late final Extension _extension;

  SourceExtensionBuilder? _origin;
  SourceExtensionBuilder? _augmentation;

  MergedClassMemberScope? _mergedScope;

  final DeclarationNameSpaceBuilder _nameSpaceBuilder;

  late final DeclarationNameSpace _nameSpace;

  @override
  final List<NominalParameterBuilder>? typeParameters;

  @override
  final LookupScope typeParameterScope;

  @override
  final TypeBuilder onType;

  final ExtensionName extensionName;

  final Reference _reference;

  /// The `extension` declaration that introduces this extension. Subsequent
  /// extensions of the same name must be augmentations.
  // TODO(johnniwinther): Add [_augmentations] field.
  final ExtensionFragment _introductory;

  SourceExtensionBuilder(
      {required SourceLibraryBuilder enclosingLibraryBuilder,
      required this.fileUri,
      required int startOffset,
      required int nameOffset,
      required int endOffset,
      required ExtensionFragment fragment,
      required Reference? reference})
      : _introductory = fragment,
        _reference = reference ?? new Reference(),
        _nameOffset = nameOffset,
        parent = enclosingLibraryBuilder,
        _modifiers = fragment.modifiers,
        extensionName = fragment.extensionName,
        typeParameters = fragment.typeParameters?.builders,
        typeParameterScope = fragment.typeParameterScope,
        onType = fragment.onType,
        _nameSpaceBuilder = fragment.toDeclarationNameSpaceBuilder() {
    _introductory.builder = this;
    _introductory.bodyScope.declarationBuilder = this;

    // TODO(johnniwinther): Move this to the [build] once augmentations are
    // handled through fragments.
    _extension = new Extension(
        name: extensionName.name,
        fileUri: fileUri,
        typeParameters:
            NominalParameterBuilder.typeParametersFromBuilders(typeParameters),
        reference: _reference)
      ..isUnnamedExtension = extensionName.isUnnamedExtension
      ..fileOffset = _nameOffset;
    extensionName.attachExtension(_extension);
  }

  // Coverage-ignore(suite): Not run.
  // TODO(johnniwinther): Avoid exposing this. Annotations for macros and
  //  patches should be computing from within the builder.
  Iterable<MetadataBuilder>? get metadata => _introductory.metadata;

  @override
  int get fileOffset => _nameOffset;

  @override
  String get name => extensionName.name;

  @override
  DeclarationNameSpace get nameSpace => _nameSpace;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isConst => _modifiers.isConst;

  @override
  // Coverage-ignore(suite): Not run.
  bool get isStatic => _modifiers.isStatic;

  @override
  bool get isAugment => _modifiers.isAugment;

  // Coverage-ignore(suite): Not run.
  SourceExtensionBuilder? get augmentationForTesting => _augmentation;

  @override
  void buildScopes(LibraryBuilder coreLibrary) {
    SourceExtensionBuilder? augmentation = _augmentation;
    if (augmentation != null) {
      _nameSpaceBuilder.includeBuilders(augmentation._nameSpaceBuilder);
    }
    _nameSpace = _nameSpaceBuilder.buildNameSpace(
        loader: libraryBuilder.loader,
        problemReporting: libraryBuilder,
        enclosingLibraryBuilder: libraryBuilder,
        declarationBuilder: this,
        indexedLibrary: libraryBuilder.indexedLibrary,
        // Extensions do not have a corresponding [IndexedContainer] since their
        // members are stored in the enclosing library.
        indexedContainer: null,
        containerType: ContainerType.Extension,
        containerName: extensionName,
        includeConstructors: false);
    if (augmentation != null) {
      augmentation.buildScopes(coreLibrary);
      _applyAugmentation(augmentation);
    }
  }

  @override
  SourceLibraryBuilder get libraryBuilder =>
      super.libraryBuilder as SourceLibraryBuilder;

  bool get isUnnamedExtension => extensionName.isUnnamedExtension;

  @override
  SourceExtensionBuilder get origin => _origin ?? this;

  // Coverage-ignore(suite): Not run.
  // TODO(johnniwinther): Add merged scope for extensions.
  MergedClassMemberScope get mergedScope => _mergedScope ??= isAugmenting
      ? origin.mergedScope
      : throw new UnimplementedError("SourceExtensionBuilder.mergedScope");

  @override
  Reference get reference => _reference;

  @override
  Extension get extension {
    return isAugmenting ? origin.extension : _extension;
  }

  @override
  BodyBuilderContext createBodyBuilderContext() {
    return new ExtensionBodyBuilderContext(this);
  }

  @override
  Annotatable get annotatable => extension;

  /// Builds the [Extension] for this extension build and inserts the members
  /// into the [Library] of [libraryBuilder].
  ///
  /// [addMembersToLibrary] is `true` if the extension members should be added
  /// to the library. This is `false` if the extension is in conflict with
  /// another library member. In this case, the extension member should not be
  /// added to the library to avoid name clashes with other members in the
  /// library.
  Extension build(LibraryBuilder coreLibrary,
      {required bool addMembersToLibrary}) {
    _extension.onType = onType.build(libraryBuilder, TypeUse.extensionOnType);

    buildInternal(coreLibrary, addMembersToLibrary: addMembersToLibrary);
    return _extension;
  }

  @override
  void buildOutlineExpressions(ClassHierarchy classHierarchy,
      List<DelayedDefaultValueCloner> delayedDefaultValueCloners) {
    MetadataBuilder.buildAnnotations(
        annotatable,
        _introductory.metadata,
        createBodyBuilderContext(),
        libraryBuilder,
        _introductory.fileUri,
        _introductory.enclosingScope);

    super.buildOutlineExpressions(classHierarchy, delayedDefaultValueCloners);

    SourceExtensionBuilder? augmentation = _augmentation;
    if (augmentation != null) {
      augmentation.buildOutlineExpressions(
          classHierarchy, delayedDefaultValueCloners);
    }
  }

  @override
  // Coverage-ignore(suite): Not run.
  void addMemberInternal(SourceMemberBuilder memberBuilder,
      BuiltMemberKind memberKind, Member member, Member? tearOff) {
    unhandled("${memberBuilder.runtimeType}:${memberKind}", "addMemberInternal",
        memberBuilder.fileOffset, memberBuilder.fileUri);
  }

  @override
  void addMemberDescriptorInternal(
      SourceMemberBuilder memberBuilder,
      BuiltMemberKind memberKind,
      Reference memberReference,
      Reference? tearOffReference) {
    String name = memberBuilder.name;
    ExtensionMemberKind kind;
    switch (memberKind) {
      case BuiltMemberKind.Constructor:
      case BuiltMemberKind.RedirectingFactory:
      case BuiltMemberKind.Factory:
      case BuiltMemberKind.Field:
      case BuiltMemberKind.Method:
      case BuiltMemberKind.ExtensionTypeConstructor:
      case BuiltMemberKind.ExtensionTypeMethod:
      case BuiltMemberKind.ExtensionTypeGetter:
      case BuiltMemberKind.ExtensionTypeSetter:
      case BuiltMemberKind.ExtensionTypeOperator:
      case BuiltMemberKind.ExtensionTypeFactory:
      case BuiltMemberKind.ExtensionTypeRedirectingFactory:
      case BuiltMemberKind.ExtensionTypeRepresentationField:
        // Coverage-ignore(suite): Not run.
        unhandled(
            "$memberBuilder(${memberBuilder.runtimeType}):${memberKind}",
            "addMemberDescriptorInternal",
            memberBuilder.fileOffset,
            memberBuilder.fileUri);
      case BuiltMemberKind.ExtensionField:
      case BuiltMemberKind.LateIsSetField:
        kind = ExtensionMemberKind.Field;
        break;
      case BuiltMemberKind.ExtensionMethod:
        kind = ExtensionMemberKind.Method;
        break;
      case BuiltMemberKind.ExtensionGetter:
      case BuiltMemberKind.LateGetter:
        kind = ExtensionMemberKind.Getter;
        break;
      case BuiltMemberKind.ExtensionSetter:
      case BuiltMemberKind.LateSetter:
        kind = ExtensionMemberKind.Setter;
        break;
      case BuiltMemberKind.ExtensionOperator:
        kind = ExtensionMemberKind.Operator;
        break;
    }
    extension.memberDescriptors.add(new ExtensionMemberDescriptor(
        name: new Name(name, libraryBuilder.library),
        memberReference: memberReference,
        tearOffReference: tearOffReference,
        isStatic: memberBuilder.isStatic,
        kind: kind));
  }

  @override
  void addAugmentation(Builder augmentation) {
    _addAugmentation(augmentation);
  }

  SourceExtensionBuilder? _addAugmentation(Builder augmentation) {
    if (augmentation is SourceExtensionBuilder) {
      augmentation._origin = this;
      _augmentation = augmentation;
      return augmentation;
    } else {
      // Coverage-ignore-block(suite): Not run.
      libraryBuilder.addProblem(messagePatchDeclarationMismatch,
          augmentation.fileOffset, noLength, augmentation.fileUri, context: [
        messagePatchDeclarationOrigin.withLocation(
            fileUri, fileOffset, noLength)
      ]);
      return null;
    }
  }

  void _applyAugmentation(SourceExtensionBuilder augmentation) {
    // TODO(johnniwinther): Check that on-type match with origin declaration.

    int originLength = typeParameters?.length ?? 0;
    int augmentationLength = augmentation.typeParameters?.length ?? 0;
    if (originLength != augmentationLength) {
      // Coverage-ignore-block(suite): Not run.
      augmentation.addProblem(messagePatchExtensionTypeParametersMismatch,
          augmentation.fileOffset, noLength, context: [
        messagePatchExtensionOrigin.withLocation(fileUri, fileOffset, noLength)
      ]);
    } else if (typeParameters != null) {
      int count = 0;
      for (NominalParameterBuilder t in augmentation.typeParameters!) {
        typeParameters![count++].applyAugmentation(t);
      }
    }
    nameSpace.forEachLocalMember((String name, Builder member) {
      Builder? memberAugmentation =
          augmentation.nameSpace.lookupLocalMember(name, setter: false);
      if (memberAugmentation != null) {
        // Coverage-ignore-block(suite): Not run.
        member.applyAugmentation(memberAugmentation);
      }
    });
    nameSpace.forEachLocalSetter((String name, Builder member) {
      Builder? memberAugmentation =
          augmentation.nameSpace.lookupLocalMember(name, setter: true);
      if (memberAugmentation != null) {
        // Coverage-ignore-block(suite): Not run.
        member.applyAugmentation(memberAugmentation);
      }
    });
  }

  @override
  // Coverage-ignore(suite): Not run.
  void applyAugmentation(Builder augmentation) {
    SourceExtensionBuilder? extensionBuilder = _addAugmentation(augmentation);
    if (extensionBuilder != null) {
      _applyAugmentation(extensionBuilder);
    }
  }
}
