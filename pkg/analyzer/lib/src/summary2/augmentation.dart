// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: analyzer_use_new_elements

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_algebra.dart';
import 'package:analyzer/src/utilities/extensions/element.dart';
import 'package:analyzer/src/utilities/extensions/string.dart';

class ClassElementBuilder
    extends InstanceElementBuilder<ClassElementImpl2, ClassElementImpl> {
  ClassElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(ClassElementImpl fragment) {
    addFields(fragment.fields);
    addConstructors(fragment.constructors);
    addAccessors(fragment.accessors);
    addMethods(fragment.methods);

    if (identical(fragment, firstFragment)) {
      _addFirstFragment();
    } else {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;

      fragment.augmentedInternal = element;
      _updatedAugmented(fragment);
    }
  }
}

class EnumElementBuilder
    extends InstanceElementBuilder<EnumElementImpl2, EnumElementImpl> {
  EnumElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(EnumElementImpl fragment) {
    addFields(fragment.fields);
    addConstructors(fragment.constructors);
    addAccessors(fragment.accessors);
    addMethods(fragment.methods);

    if (identical(fragment, firstFragment)) {
      _addFirstFragment();
    } else {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;

      fragment.augmentedInternal = element;
      _updatedAugmented(fragment);
    }
  }
}

class ExtensionElementBuilder extends InstanceElementBuilder<
    ExtensionElementImpl2, ExtensionElementImpl> {
  ExtensionElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(ExtensionElementImpl fragment) {
    addFields(fragment.fields);
    addAccessors(fragment.accessors);
    addMethods(fragment.methods);

    if (identical(fragment, firstFragment)) {
      _addFirstFragment();
    } else {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;

      fragment.augmentedInternal = element;
      _updatedAugmented(fragment);
    }
  }
}

class ExtensionTypeElementBuilder extends InstanceElementBuilder<
    ExtensionTypeElementImpl2, ExtensionTypeElementImpl> {
  ExtensionTypeElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(ExtensionTypeElementImpl fragment) {
    addFields(fragment.fields);
    addConstructors(fragment.constructors);
    addAccessors(fragment.accessors);
    addMethods(fragment.methods);

    if (identical(fragment, firstFragment)) {
      _addFirstFragment();
    } else {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;

      fragment.augmentedInternal = element;
      _updatedAugmented(fragment);
    }
  }
}

/// A builder for top-level fragmented elements, e.g. classes.
class FragmentedElementBuilder<E extends Element2, F extends Fragment> {
  final E element;
  final F firstFragment;
  F lastFragment;

  FragmentedElementBuilder({
    required this.element,
    required this.firstFragment,
  }) : lastFragment = firstFragment;

  /// If [fragment] is an augmentation, set its previous fragment to
  /// [lastFragment].
  ///
  /// We invoke this method on any [FragmentedElementBuilder] associated with
  /// the name of [fragment], even if it is not a correct builder for this
  /// [fragment]. So, the [lastFragment] might have a wrong type, but we still
  /// want to remember it for generating the corresponding diagnostic.
  void setPreviousFor(AugmentableElement fragment) {
    if (fragment.isAugmentation) {
      // TODO(scheglov): hopefully the type check can be removed in the future.
      if (lastFragment case ElementImpl lastFragment) {
        fragment.augmentationTargetAny = lastFragment;
      }
    }
  }
}

class GetterElementBuilder
    extends FragmentedElementBuilder<GetterElementImpl, GetterFragmentImpl> {
  GetterElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(GetterFragmentImpl fragment) {
    if (!identical(fragment, firstFragment)) {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;
      fragment.element = element;
    }
  }
}

abstract class InstanceElementBuilder<E extends InstanceElementImpl2,
    F extends InstanceElementImpl> extends FragmentedElementBuilder<E, F> {
  final Map<String, FieldElementImpl> fields = {};
  final Map<String, ConstructorElementImpl> constructors = {};
  final Map<String, GetterFragmentImpl> getters = {};
  final Map<String, SetterFragmentImpl> setters = {};
  final Map<String, MethodElementImpl> methods = {};

  final Map<String, ElementImpl> fragmentGetters = {};
  final Map<String, ElementImpl> fragmentSetters = {};
  final List<MethodElementImpl2> methods2 = [];

  InstanceElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addAccessors(List<PropertyAccessorElementImpl> fragments) {
    for (var fragment in fragments) {
      var name = fragment.name;
      switch (fragment) {
        case GetterFragmentImpl():
          if (fragment.isAugmentation) {
            if (getters[name] case var target?) {
              target.augmentation = fragment;
              fragment.augmentationTargetAny = target;
            } else {
              var target = _recoveryAugmentationTarget(name);
              fragment.augmentationTargetAny = target;
            }
          }
          getters[name] = fragment;
        case SetterFragmentImpl():
          if (fragment.isAugmentation) {
            if (setters[name] case var target?) {
              target.augmentation = fragment;
              fragment.augmentationTargetAny = target;
            } else {
              var target = _recoveryAugmentationTarget(name);
              fragment.augmentationTargetAny = target;
            }
          }
          setters[name] = fragment;
      }
    }
  }

  void addConstructors(List<ConstructorElementImpl> fragments) {
    for (var fragment in fragments) {
      var name = fragment.name;
      if (fragment.isAugmentation) {
        if (constructors[name] case var target?) {
          target.augmentation = fragment;
          fragment.augmentationTargetAny = target;
        } else {
          var target = _recoveryAugmentationTarget(name);
          fragment.augmentationTargetAny = target;
        }
      }
      constructors[name] = fragment;
    }
  }

  void addFields(List<FieldElementImpl> fragments) {
    for (var fragment in fragments) {
      var name = fragment.name;
      if (fragment.isAugmentation) {
        if (fields[name] case var target?) {
          target.augmentation = fragment;
          fragment.augmentationTargetAny = target;
        } else {
          var target = _recoveryAugmentationTarget(name);
          fragment.augmentationTargetAny = target;
        }
      }
      fields[name] = fragment;
    }
  }

  void addMethods(List<MethodElementImpl> fragments) {
    for (var fragment in fragments) {
      var name = fragment.name;
      if (fragment.isAugmentation) {
        if (methods[name] case var target?) {
          target.augmentation = fragment;
          fragment.augmentationTargetAny = target;
        } else {
          var target = _recoveryAugmentationTarget(name);
          fragment.augmentationTargetAny = target;
        }
      }
      methods[name] = fragment;
    }
  }

  ElementImpl? replaceGetter<T extends ElementImpl>(T fragment) {
    var name = (fragment as Fragment).name2;
    if (name == null) {
      return null;
    }

    var lastFragment = fragmentGetters[name];
    lastFragment ??= fragmentSetters[name];

    fragmentGetters[name] = fragment;
    fragmentSetters.remove(name);

    return lastFragment;
  }

  void _addFirstFragment() {
    var firstFragment = this.firstFragment;
    var element = firstFragment.element;

    element.fields.addAll(firstFragment.fields);
    element.accessors.addAll(firstFragment.accessors);

    if (element is MixinElementImpl2) {
      if (firstFragment is MixinElementImpl) {
        element.superclassConstraints.addAll(
          firstFragment.superclassConstraints,
        );
      }
    }
  }

  ElementImpl? _recoveryAugmentationTarget(String name) {
    name = name.removeSuffix('=') ?? name;

    ElementImpl? target;
    target ??= getters[name];
    target ??= setters['$name='];
    target ??= constructors[name];
    target ??= methods[name];
    return target;
  }

  void _updatedAugmented(InstanceElementImpl augmentation) {
    var element = this.element;
    var firstTypeParameters = element.typeParameters2;

    MapSubstitution toFirstFragment;
    var augmentationTypeParameters = [
      for (var tp in augmentation.typeParameters)
        TypeParameterElementImpl2(
          firstFragment: tp,
          name3: tp.name.nullIfEmpty,
        ),
    ];
    if (augmentationTypeParameters.length == firstTypeParameters.length) {
      toFirstFragment = Substitution.fromPairs2(
        augmentationTypeParameters,
        firstTypeParameters.instantiateNone(),
      );
    } else {
      toFirstFragment = Substitution.fromPairs2(
        augmentationTypeParameters,
        List.filled(
          augmentationTypeParameters.length,
          InvalidTypeImpl.instance,
        ),
      );
    }

    element.fields = [
      ...element.fields.notAugmented,
      ...augmentation.fields.notAugmented.map((element) {
        if (toFirstFragment.map.isEmpty) {
          return element;
        }
        return FieldMember(element, toFirstFragment, Substitution.empty);
      }),
    ];

    element.accessors = [
      ...element.accessors.notAugmented,
      ...augmentation.accessors.notAugmented.map((element) {
        if (toFirstFragment.map.isEmpty) {
          return element;
        }
        return PropertyAccessorMember(
            element, toFirstFragment, Substitution.empty);
      }),
    ];
  }
}

class MixinElementBuilder
    extends InstanceElementBuilder<MixinElementImpl2, MixinElementImpl> {
  MixinElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(MixinElementImpl fragment) {
    addFields(fragment.fields);
    addAccessors(fragment.accessors);
    addMethods(fragment.methods);

    if (identical(fragment, firstFragment)) {
      _addFirstFragment();
    } else {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;

      fragment.augmentedInternal = element;
      _updatedAugmented(fragment);
    }
  }
}

class SetterElementBuilder
    extends FragmentedElementBuilder<SetterElementImpl, SetterFragmentImpl> {
  SetterElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(SetterFragmentImpl fragment) {
    if (!identical(fragment, firstFragment)) {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;
      fragment.element = element;
    }
  }
}

class TopLevelFunctionElementBuilder extends FragmentedElementBuilder<
    TopLevelFunctionElementImpl, TopLevelFunctionFragmentImpl> {
  TopLevelFunctionElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(TopLevelFunctionFragmentImpl fragment) {
    if (!identical(fragment, firstFragment)) {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;
      fragment.element = element;
    }
  }
}

class TopLevelVariableElementBuilder extends FragmentedElementBuilder<
    TopLevelVariableElementImpl2, TopLevelVariableElementImpl> {
  TopLevelVariableElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(TopLevelVariableElementImpl fragment) {
    if (!identical(fragment, firstFragment)) {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;
      fragment.element = element;
    }
  }
}

class TypeAliasElementBuilder extends FragmentedElementBuilder<
    TypeAliasElementImpl2, TypeAliasElementImpl> {
  TypeAliasElementBuilder({
    required super.element,
    required super.firstFragment,
  });

  void addFragment(TypeAliasElementImpl fragment) {
    if (!identical(fragment, firstFragment)) {
      lastFragment.augmentation = fragment;
      lastFragment = fragment;
      fragment.element = element;
    }
  }
}

extension<T extends ExecutableElement> on List<T> {
  Iterable<T> get notAugmented {
    return where((e) => e.augmentation == null);
  }
}

extension<T extends PropertyInducingElement> on List<T> {
  Iterable<T> get notAugmented {
    return where((e) => e.augmentation == null);
  }
}
