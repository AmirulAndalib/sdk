// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:_js_interop_checks/src/transformations/static_interop_class_eraser.dart'
    show eraseStaticInteropTypesForJSCompilers;
import 'package:js_shared/synced/recipe_syntax.dart' show Recipe;
import 'package:js_shared/variance.dart' as shared_variance;
import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:path/path.dart' as p;

import '../compiler/js_names.dart';
import 'future_or_normalizer.dart';
import 'js_interop.dart';
import 'kernel_helpers.dart';
import 'type_environment.dart';

/// Generates type recipe `String`s that can be used to produce Rti objects
/// in the dart:_rti library.
///
/// This class is intended to be instantiated once and reused by the
/// `ProgramCompiler`. It provides the API to interact with the DartType visitor
/// that generates the type recipes.
class TypeRecipeGenerator {
  final CoreTypes _coreTypes;
  final ClassHierarchy _hierarchy;
  final _TypeRecipeVisitor _recipeVisitor;
  final FutureOrNormalizer _futureOrNormalizer;

  TypeRecipeGenerator(CoreTypes coreTypes, this._hierarchy)
    : _coreTypes = coreTypes,
      _recipeVisitor = _TypeRecipeVisitor(
        const EmptyTypeEnvironment(),
        coreTypes,
      ),
      _futureOrNormalizer = FutureOrNormalizer(coreTypes);

  /// Returns a recipe for the provided [type] packaged with an environment with
  /// which to evaluate the recipe in.
  ///
  /// The returned environment will be a subset of the provided [environment]
  /// that includes only the necessary types to evaluate the recipe.
  GeneratedRecipe recipeInEnvironment(
    DartType type,
    DDCTypeEnvironment environment, {
    bool emitJSInteropGenericClassTypeParametersAsAny = true,
  }) {
    // Reduce the provided environment down to the parameters that are present.
    var parametersInType = TypeParameterFinder.instance().find(type);
    var minimalEnvironment = environment.prune(parametersInType);
    // Set the visitor state, generate the recipe, and package it with the
    // environment required to evaluate it.
    _recipeVisitor.setState(
      environment: minimalEnvironment,
      addLiveInterfaceTypes: true,
      emitJSInteropGenericClassTypeParametersAsAny:
          emitJSInteropGenericClassTypeParametersAsAny,
    );
    var recipe = type.accept(_recipeVisitor);
    return GeneratedRecipe(recipe, minimalEnvironment);
  }

  /// Manually mark [type] as being live in this compilation.
  ///
  /// When values of a class are constructed that type becomes live in the
  /// module even though the type itself might not appear. This method provides
  /// a way to add it to ensure the type hierarchy rules will be generated for
  /// it.
  ///
  /// See [_TypeRecipeVisitor.addLiveType] for more information.
  void addLiveTypeAncestries(InterfaceType type) =>
      _recipeVisitor.addLiveTypeAncestries(type);

  /// Returns all recipes for [InterfaceType]s that have appeared in type
  /// recipes.
  List<String> get visitedInterfaceTypeRecipes => [
    for (var type in _recipeVisitor.visitedInterfaceTypes)
      interfaceTypeRecipe(type.classNode),
  ];

  /// Returns a mapping of type hierarchies for all [InterfaceType]s that have
  /// appeared in type recipes.
  ///
  /// While the value of the returned map is typed as `Object` it is always
  /// either a `String` or a `Map<String, List<String>>`.
  ///
  /// This mapping is intended to satisfy the requirements for the
  /// `_Universe.addRules()` static method in the runtime rti library.
  ///
  /// The format is compatible to directly encode as the JSON string expected
  /// by the runtime library:
  ///
  /// ```
  /// '{"type 0": {"supertype 0": ["type argument 0"... "type argument n"],
  ///                 ...
  ///                "supertype n": ["type argument 0"... "type argument n"]},
  ///    ...
  ///   "type n": {...}}'
  /// ```
  ///
  /// Additionally, the runtime rti library supports a special forwarding rule
  /// for non-static JavaScript interop types. With this format every interop
  /// type simply forwards to `LegacyJavaScriptObject` where they all share
  /// a single type rule
  ///
  /// ```
  /// '{"interop type 0": "LegacyJavaScriptObject",
  ///    ...
  ///   "interop type n": "LegacyJavaScriptObject"}'
  /// ```
  ///
  /// It is expected that this method is called at the end of a compilation
  /// after all types used in the module have already been visited. Otherwise
  /// the results will be incomplete.
  Map<String, Object> get liveInterfaceTypeRules {
    // All non-static JavaScript interop classes should be mutual subtypes with
    // 'LegacyJavaScriptObject`. To achieve this the rules are manually
    // added here. There is special redirecting rule logic in the dart:_rti
    // library for interop types because otherwise they would duplicate
    // a lot of supertype information.
    var legacyJavaScriptObjectRecipe = interfaceTypeRecipe(
      _coreTypes.index.getClass('dart:_interceptors', 'LegacyJavaScriptObject'),
    );
    var rules = <String, Object>{
      for (var recipe in visitedJsInteropTypeRecipes)
        recipe: legacyJavaScriptObjectRecipe,
    };

    // All Dart types hierarchy rules are generated by exploring their class
    // hierarchy.
    for (var type in _recipeVisitor.visitedInterfaceTypes) {
      var recipe = interfaceTypeRecipe(type.classNode);
      var cls = type.classNode;
      // Create a class type environment for calculating type argument indices.
      // Avoid recording the types while iterating the visited types.
      _recipeVisitor.setState(
        environment: ClassTypeEnvironment(cls.typeParameters),
        // No need to add any more live types at this time. Any "new" types
        // seen in this process are not live.
        addLiveInterfaceTypes: false,
        emitClassTypeParametersAsIndices: true,
      );
      var supertypeEntries = <String, Object>{};
      // Encode the type argument mapping portion of this type rule.
      for (var i = 0; i < cls.typeParameters.length; i++) {
        var paramRecipe = '${cls.name}.${cls.typeParameters[i].name!}';
        var argumentRecipe = _futureOrNormalizer
            .normalize(type.typeArguments[i].extensionTypeErasure)
            .accept(_recipeVisitor);
        supertypeEntries[paramRecipe] = argumentRecipe;
      }
      // Encode type rules for all supers.
      var toVisit = ListQueue<Supertype>.from(cls.supers);
      var visited = <Supertype>{};
      while (toVisit.isNotEmpty) {
        var currentClass = toVisit.removeFirst().classNode;
        if (currentClass == _coreTypes.objectClass) continue;
        var currentType = _hierarchy.getClassAsInstanceOf(cls, currentClass)!;
        if (visited.contains(currentType)) continue;
        // Add all supers to the visit queue.
        toVisit.addAll(currentClass.supers);
        // Skip encoding the synthetic classes in the type rules because they
        // will never be instantiated or appear in type tests.
        if (currentClass.isAnonymousMixin) continue;
        // Encode the supertype portion of this type rule.
        var recipe = interfaceTypeRecipe(currentClass);
        var typeArgumentRecipes = [
          for (var typeArgument in currentType.typeArguments)
            _futureOrNormalizer
                .normalize(typeArgument.extensionTypeErasure)
                .accept(_recipeVisitor),
        ];
        // Encode the type argument mapping portion of this type rule.
        for (var i = 0; i < currentClass.typeParameters.length; i++) {
          var paramRecipe =
              '${currentClass.name}.${currentClass.typeParameters[i].name!}';
          var argumentRecipe = _futureOrNormalizer
              .normalize(currentType.typeArguments[i].extensionTypeErasure)
              .accept(_recipeVisitor);
          supertypeEntries[paramRecipe] = argumentRecipe;
        }
        supertypeEntries[recipe] = typeArgumentRecipes;
        visited.add(currentType);
      }
      if (supertypeEntries.isNotEmpty) rules[recipe] = supertypeEntries;
    }
    return rules;
  }

  /// A mapping of type parameter variances for every [InterfaceType] that's
  /// appeared in type recipes.
  Map<String, Iterable<int>> get variances {
    return {
      for (var type in _recipeVisitor.visitedInterfaceTypes)
        if (type.classNode case var cls && Class(:var typeParameters)
            // Only emit type parameter variances for the interface if there
            // exists at least one type parameter that doesn't have legacy
            // covariance to avoid encoding extra information.
            when typeParameters.any((element) => !element.isLegacyCovariant))
          interfaceTypeRecipe(cls): [
            for (var typeParameter in typeParameters)
              _convertVariance(typeParameter),
          ],
    };
  }

  /// Returns a mapping of type hierarchies for all [InterfaceType]s that have
  /// appeared in type recipes.
  Map<String, Object> get updateLegacyJavaScriptObjectRules {
    var recipes = visitedJsInteropTypeRecipes;
    return {
      if (recipes.isNotEmpty)
        interfaceTypeRecipe(
          _coreTypes.index.getClass(
            'dart:_interceptors',
            'LegacyJavaScriptObject',
          ),
        ):
        // Update type rules for `LegacyJavaScriptObject` to add all interop
        // types in this module as a supertype.
        {
          for (var interopType in _recipeVisitor._visitedJsInteropTypes)
            interfaceTypeRecipe(interopType.classNode): _recipeVisitor
                ._listOfJSAnyType(interopType.typeArguments.length),
        },
    };
  }

  String interfaceTypeRecipe(Class node) =>
      _recipeVisitor.interfaceTypeRecipe(node);

  Iterable<String> get visitedJsInteropTypeRecipes => _recipeVisitor
      .visitedJsInteropTypes
      .map((type) => interfaceTypeRecipe(type.classNode));

  /// Converts the AST variance of the [typeParameter] to one that can be used
  /// at runtime.
  int _convertVariance(TypeParameter typeParameter) {
    if (typeParameter.isLegacyCovariant) {
      return shared_variance.Variance.legacyCovariant.index;
    }
    return switch (typeParameter.variance) {
      Variance.covariant => shared_variance.Variance.covariant.index,
      Variance.contravariant => shared_variance.Variance.contravariant.index,
      Variance.invariant => shared_variance.Variance.invariant.index,
      var variance => throw UnsupportedError(
        'Variance $variance is not supported.',
      ),
    };
  }
}

/// A visitor to generate type recipe strings from a [DartType].
///
/// The recipes are used by the 'dart:_rti' library while running the compiled
/// application.
///
/// This visitor should be considered an implementation detail of
/// [TypeRecipeGenerator] and all interactions with it should be through that
/// class. It contains state that needs to be correctly set before visiting a
/// type to produce valid recipes in a given type environment context.
class _TypeRecipeVisitor extends DartTypeVisitor<String> {
  /// The type environment to evaluate recipes in.
  ///
  /// Part of the state that should be set before visiting a type.
  /// Used to determine the indices for type variables.
  DDCTypeEnvironment _typeEnvironment;

  /// Type parameters introduced to the environment while visiting generic
  /// function types nested within other types.
  var _unboundTypeParameters = <String>[];

  /// When `true` this visitor will record all of the [InterfaceType]s it
  /// visits.
  ///
  /// Part of the state that should be set before visiting a type.
  /// These types can be used later to produce runtime type hierarchy rules for
  /// all of the visited interface types.
  bool _addLiveInterfaceTypes = true;

  /// When `true`, references generic class type parameters via their de Bruijn
  /// indices.
  ///
  /// DDC defaults to using generic parameter names instead of de Bruijn
  /// indices because the latter aren't stable across subtype environments.
  ///
  /// This is only used when generating type rules for the type universe
  /// (i.e., in `liveInterfaceTypeRules`).
  bool _emitClassTypeParametersAsIndices = false;

  /// Emits JS interop generic arguments as `Any` when true and their 'real'
  /// type when false.
  ///
  /// We usually convert type arguments to `Any` to allow type checks and casts
  /// to succeed for JS interop objects. However, their 'real' types are used
  /// for checks in non-external constructors and factories.
  bool _emitJSInteropGenericClassTypeParametersAsAny = true;

  /// All of the [InterfaceType]s visited.
  final _visitedInterfaceTypes = <InterfaceType>{};
  final _visitedJsInteropTypes = <InterfaceType>{};
  final CoreTypes _coreTypes;

  _TypeRecipeVisitor(this._typeEnvironment, this._coreTypes);

  /// Set the state of this visitor.
  ///
  /// Generally this should be called before visiting a type, but the visitor
  /// does not modify the state so if many types need to be evaluated in the
  /// same state it can be set once before visiting all of them.
  void setState({
    DDCTypeEnvironment? environment,
    bool? addLiveInterfaceTypes,
    bool? emitClassTypeParametersAsIndices,
    bool? emitJSInteropGenericClassTypeParametersAsAny,
  }) {
    if (environment != null) _typeEnvironment = environment;
    if (addLiveInterfaceTypes != null) {
      _addLiveInterfaceTypes = addLiveInterfaceTypes;
    }
    if (emitClassTypeParametersAsIndices != null) {
      _emitClassTypeParametersAsIndices = emitClassTypeParametersAsIndices;
    }
    if (emitJSInteropGenericClassTypeParametersAsAny != null) {
      _emitJSInteropGenericClassTypeParametersAsAny =
          emitJSInteropGenericClassTypeParametersAsAny;
    }
  }

  /// The [InterfaceType]s that have been visited.
  Iterable<InterfaceType> get visitedInterfaceTypes =>
      Set.unmodifiable(_visitedInterfaceTypes);

  /// The JavaScript interop types that have been visited.
  Iterable<InterfaceType> get visitedJsInteropTypes =>
      Set.unmodifiable(_visitedJsInteropTypes);

  @override
  String visitAuxiliaryType(AuxiliaryType node) =>
      throwUnsupportedAuxiliaryType(node);

  @override
  String visitInvalidType(InvalidType node) =>
      throwUnsupportedInvalidType(node);

  @override
  String visitDynamicType(DynamicType node) => Recipe.pushDynamicString;

  @override
  String visitVoidType(VoidType node) => Recipe.pushVoidString;

  @override
  String visitInterfaceType(InterfaceType node) {
    var cls = node.classNode;
    if (isStaticInteropType(cls)) {
      return eraseStaticInteropTypesForJSCompilers(
        _coreTypes,
        node,
      ).accept(this);
    }
    addLiveTypeAncestries(node);
    // Generate the interface type recipe.
    var recipeBuffer = StringBuffer(interfaceTypeRecipe(cls));
    // Generate the recipes for all type arguments.
    if (node.typeArguments.isNotEmpty) {
      var argumentRecipes =
          _emitJSInteropGenericClassTypeParametersAsAny &&
              hasJSInteropAnnotation(cls)
          ? _listOfJSAnyType(node.typeArguments.length)
          : node.typeArguments.map((typeArgument) => typeArgument.accept(this));
      recipeBuffer.write(Recipe.startTypeArgumentsString);
      recipeBuffer.writeAll(argumentRecipes, Recipe.separatorString);
      recipeBuffer.write(Recipe.endTypeArgumentsString);
    }
    // Add nullability.
    recipeBuffer.write(_nullabilityRecipe(node));
    return recipeBuffer.toString();
  }

  @override
  String visitFutureOrType(FutureOrType node) =>
      '${node.typeArgument.accept(this)}'
      '${Recipe.wrapFutureOrString}'
      '${_nullabilityRecipe(node)}';

  @override
  String visitFunctionType(FunctionType node) {
    var savedUnboundTypeParameters = _unboundTypeParameters;
    // Collect the type parameters introduced by this function type because they
    // might be used later in its definition.
    //
    // For example, the function type `T Function<T, S>(S)` introduces new type
    // parameter types and uses them in the parameter and return types.
    _unboundTypeParameters = [
      for (var parameter in node.typeParameters) parameter.name!,
      ..._unboundTypeParameters,
    ];
    // Generate the return type recipe.
    var recipeBuffer = StringBuffer(node.returnType.accept(this));
    // Generate the method parameter recipes.
    recipeBuffer.write(Recipe.startFunctionArgumentsString);
    // Required positional parameters.
    var requiredParameterCount = node.requiredParameterCount;
    var positionalParameters = node.positionalParameters;
    for (var i = 0; i < requiredParameterCount; i++) {
      recipeBuffer.write(positionalParameters[i].accept(this));
      if (i < requiredParameterCount - 1) {
        recipeBuffer.write(Recipe.separatorString);
      }
    }
    var positionalCount = positionalParameters.length;
    // Optional positional parameters.
    if (positionalCount > requiredParameterCount) {
      recipeBuffer.write(Recipe.startOptionalGroupString);
      for (var i = requiredParameterCount; i < positionalCount; i++) {
        recipeBuffer.write(positionalParameters[i].accept(this));
        if (i < positionalCount - 1) {
          recipeBuffer.write(Recipe.separatorString);
        }
      }
      recipeBuffer.write(Recipe.endOptionalGroupString);
    }
    // Named parameters.
    var namedParameters = node.namedParameters;
    var namedCount = namedParameters.length;
    if (namedParameters.isNotEmpty) {
      recipeBuffer.write(Recipe.startNamedGroupString);
      for (var i = 0; i < namedCount; i++) {
        var named = namedParameters[i];
        recipeBuffer.write(named.name);
        recipeBuffer.write(
          named.isRequired
              ? Recipe.requiredNameSeparatorString
              : Recipe.nameSeparatorString,
        );
        recipeBuffer.write(named.type.accept(this));
        if (i < namedCount - 1) {
          recipeBuffer.write(Recipe.separatorString);
        }
      }
      recipeBuffer.write(Recipe.endNamedGroupString);
    }
    recipeBuffer.write(Recipe.endFunctionArgumentsString);
    // Generate type parameter recipes.
    var typeParameters = node.typeParameters;
    if (typeParameters.isNotEmpty) {
      recipeBuffer.write(Recipe.startTypeArgumentsString);
      recipeBuffer.writeAll(
        typeParameters.map((parameter) => parameter.bound.accept(this)),
        Recipe.separatorString,
      );
      recipeBuffer.write(Recipe.endTypeArgumentsString);
    }
    _unboundTypeParameters = savedUnboundTypeParameters;
    // Add the function type nullability.
    recipeBuffer.write(_nullabilityRecipe(node));
    return recipeBuffer.toString();
  }

  @override
  String visitExtensionType(ExtensionType node) =>
      node.extensionTypeErasure.accept(this);

  @override
  String visitRecordType(RecordType node) {
    var recipeBuffer = StringBuffer(Recipe.startRecordString);
    // Add the names of the named elements.
    recipeBuffer.writeAll(
      node.named.map((element) => element.name),
      Recipe.separatorString,
    );
    // Add all element types.
    recipeBuffer.write(Recipe.startFunctionArgumentsString);
    var elementTypes = [
      ...node.positional,
      ...node.named.map((element) => element.type),
    ];
    recipeBuffer.writeAll(
      elementTypes.map((element) => element.accept(this)),
      Recipe.separatorString,
    );
    recipeBuffer.write(Recipe.endFunctionArgumentsString);
    // Add the records nullability.
    recipeBuffer.write(_nullabilityRecipe(node));
    return recipeBuffer.toString();
  }

  @override
  String visitTypeParameterType(TypeParameterType node) {
    var i = _unboundTypeParameters.indexOf(node.parameter.name!);
    if (i >= 0) {
      return '$i'
          '${Recipe.genericFunctionTypeParameterIndexString}'
          '${_nullabilityRecipe(node)}';
    }
    var parameterDeclaration = node.parameter.declaration;
    if (!_emitClassTypeParametersAsIndices && parameterDeclaration is Class) {
      // Generic type parameters in binding positions will still be emitted
      // with indices.
      var typeParamInBindingPosition =
          _typeEnvironment is BindingTypeEnvironment ||
          (_typeEnvironment is ExtendedTypeEnvironment &&
              _typeEnvironment.functionTypeParameters.contains(node.parameter));
      if (!typeParamInBindingPosition) {
        // We don't emit RTI rules for anonymous mixins since 1) their
        // generated names are very large and 2) they aren't declared in user
        // code. However, type parameters that reference them may still appear
        // (such as for covariant mixin stubs), so we reference them via their
        // mixin application's subclass.
        var classNameToEmit = parameterDeclaration.isAnonymousMixin
            ? parameterDeclaration.nameAsMixinApplicationSubclass
            : parameterDeclaration.name;
        return '$classNameToEmit.${node.parameter.name}${_nullabilityRecipe(node)}';
      }
    }
    i = _typeEnvironment.recipeIndexOf(node.parameter);
    if (i < 0) {
      throw UnsupportedError(
        'Type parameter $node was not found in the environment '
        '$_typeEnvironment or in the unbound parameters '
        '$_unboundTypeParameters.',
      );
    }
    return '$i${_nullabilityRecipe(node)}';
  }

  @override
  String visitTypedefType(TypedefType node) =>
      throw UnimplementedError('Unknown DartType: $node');

  @override
  String visitStructuralParameterType(StructuralParameterType node) {
    var i = _unboundTypeParameters.indexOf(node.parameter.name!);
    if (i >= 0) {
      return '$i'
          '${Recipe.genericFunctionTypeParameterIndexString}'
          '${_nullabilityRecipe(node)}';
    } else {
      throw UnsupportedError(
        'Type parameter $node was not found in the unbound parameters '
        '$_unboundTypeParameters.',
      );
    }
  }

  @override
  String visitNeverType(NeverType node) =>
      // Normalize Never? -> Null
      node.nullability == Nullability.nullable
      ? visitNullType(const NullType())
      : '${Recipe.pushNeverExtensionString}'
            '${Recipe.extensionOpString}'
            '${_nullabilityRecipe(node)}';

  @override
  String visitNullType(NullType node) =>
      interfaceTypeRecipe(_coreTypes.deprecatedNullClass);

  @override
  String visitIntersectionType(IntersectionType node) =>
      visitTypeParameterType(node.left);

  /// Returns the recipe for the interface type introduced by [cls].
  String interfaceTypeRecipe(Class cls) {
    var path = p.withoutExtension(cls.enclosingLibrary.importUri.path);
    var library = pathToJSIdentifier(path);
    return '$library${Recipe.librarySeparatorString}${cls.name}';
  }

  /// Returns the recipe representation of [nullability].
  String _nullabilityRecipe(DartType type) {
    switch (type.declaredNullability) {
      case Nullability.undetermined:
        if (type is TypeParameterType || type is StructuralParameterType) {
          // Type parameters are expected to appear with undetermined
          // nullability since they could be instantiated with nullable type.
          // In this case we allow the type to flow without adding any
          // nullability information.
          return '';
        }
        throw UnsupportedError('Undetermined nullability.');
      case Nullability.nullable:
        return Recipe.wrapQuestionString;
      case Nullability.nonNullable:
        return '';
    }
  }

  /// Returns a list containing [n] copies of the "any" type recipe.
  ///
  /// Used exclusively for the type arguments of the older package:js style
  /// JavaScript interop types when they are defined with generic type
  /// parameters. These are not used to support the newer static JavaScript
  /// interop.
  List<String> _listOfJSAnyType(int n) => n == 0
      ? const []
      : List.filled(
          n,
          '${Recipe.pushAnyExtensionString}${Recipe.extensionOpString}',
        );

  /// Manually record the transitive type ancestries of [type], and any other
  /// interface types that appear as instantiated type arguments within as being
  /// "live".
  ///
  /// "Live" types here refer to the interface types that could potentially flow
  /// into a type operation; meaning the type of the value appearing on the LHS
  /// and the type appearing on the RHS. Those operations require a type rule
  /// gets encoded for use at runtime by the dart:_rti library.
  ///
  /// All interface types are automatically marked as "live" when a type recipe
  /// is generated for them. Manually adding a "live" type allows a way to
  /// guarantee the type rules will be encoded for the type even if a recipe was
  ///  never compiled.
  ///
  /// For example, if an instance of class `C` was constructed but `C` was never
  /// used as a _type_ in the compilation, a recipe hasn't been generated and
  /// the type will not be automatically recorded as "live". The type should be
  /// manually added in case an instance of `C` appears in a type test like
  /// `myCInstance is SomeTypeNotC` where the rule for `C` will be needed.
  void addLiveTypeAncestries(InterfaceType type) {
    if (_addLiveInterfaceTypes) {
      var toVisit = ListQueue<InterfaceType>()..add(type);
      while (toVisit.isNotEmpty) {
        var currentClass = toVisit.removeFirst().classNode;
        // Avoid duplicates of an interface that differ only in nullability by
        // always working with the non-nullable version.
        var currentType = currentClass.getThisType(
          _coreTypes,
          Nullability.nonNullable,
        );
        if (_visitedInterfaceTypes.contains(currentType) ||
            _visitedJsInteropTypes.contains(currentType) ||
            currentClass == _coreTypes.objectClass) {
          continue;
        }
        for (var supertype in currentClass.supers) {
          // Enqueue all supertypes of the current type.
          toVisit.add(supertype.asInterfaceType);
          for (var typeArgument in supertype.typeArguments) {
            if (typeArgument is TypeParameterType) continue;
            // Enqueue all interface types embedded within the type arguments of
            // the supertypes.
            toVisit.addAll(InterfaceTypeExtractor().extract(typeArgument));
          }
        }
        // No need to mark an anonymous mixin application as live since these
        // classes are synthetic and their type will never appear in any type
        // test.
        if (currentClass.isAnonymousMixin) continue;
        hasJSInteropAnnotation(currentClass)
            ? _visitedJsInteropTypes.add(currentType)
            : _visitedInterfaceTypes.add(currentType);
      }
    }
  }
}

/// Packages the type recipe and the environment needed to evaluate it at
/// runtime.
///
/// Returned from [TypeRecipeGenerator.recipeInEnvironment].
class GeneratedRecipe {
  /// A type recipe that can be used to evaluate a type at runtime in the
  /// [requiredEnvironment].
  ///
  /// For use with the dart:_rti library.
  final String recipe;

  /// The environment required to properly evaluate [recipe] within.
  ///
  /// This environment has been reduced down to be represented compactly with
  /// only the necessary type parameters.
  final DDCTypeEnvironment requiredEnvironment;

  GeneratedRecipe(this.recipe, this.requiredEnvironment);
}
