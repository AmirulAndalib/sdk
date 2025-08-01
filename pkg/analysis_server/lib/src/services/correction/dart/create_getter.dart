// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/utilities/extensions/ast.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:meta/meta.dart';

/// Shared implementation that identifies what getter should be added,
/// but delegates to the subtypes to produce the fix code.
abstract class CreateFieldOrGetter extends ResolvedCorrectionProducer {
  CreateFieldOrGetter({required super.context});

  /// Adds the declaration that makes a [fieldName] available.
  Future<void> addForObjectPattern({
    required ChangeBuilder builder,
    required InterfaceElement? targetElement,
    required String fieldName,
    required DartType? fieldType,
  });

  @protected
  Future<bool> compute0(ChangeBuilder builder) async {
    var node = this.node;

    if (node is DeclaredVariablePatternImpl) {
      var fieldName = node.fieldNameWithImplicitName;
      if (fieldName != null) {
        await _patternFieldName(builder: builder, fieldName: fieldName);
        return true;
      }
    }

    if (node is PatternFieldName) {
      await _patternFieldName(builder: builder, fieldName: node);
      return true;
    }

    return false;
  }

  Future<void> _patternFieldName({
    required ChangeBuilder builder,
    required PatternFieldName fieldName,
  }) async {
    var patternField = node.parent;
    if (patternField is! PatternField) {
      return;
    }

    var effectiveName = patternField.effectiveName;
    if (effectiveName == null) {
      return;
    }

    var objectPattern = patternField.parent;
    if (objectPattern is! ObjectPattern) {
      return;
    }

    var matchedType = objectPattern.type.typeOrThrow;
    if (matchedType is! InterfaceTypeImpl) {
      return;
    }

    var fieldType = patternField.pattern.requiredType;
    fieldType ??= typeProvider.objectQuestionType;

    await addForObjectPattern(
      builder: builder,
      targetElement: matchedType.element,
      fieldName: effectiveName,
      fieldType: fieldType,
    );
  }
}

class CreateGetter extends CreateFieldOrGetter {
  String _getterName = '';

  CreateGetter({required super.context});

  @override
  CorrectionApplicability get applicability =>
      // TODO(applicability): comment on why.
      CorrectionApplicability.singleLocation;

  @override
  List<String> get fixArguments => [_getterName];

  @override
  FixKind get fixKind => DartFixKind.CREATE_GETTER;

  @override
  Future<void> addForObjectPattern({
    required ChangeBuilder builder,
    required InterfaceElement? targetElement,
    required String fieldName,
    required DartType? fieldType,
  }) async {
    _getterName = fieldName;

    await _addDeclaration(
      builder: builder,
      staticModifier: false,
      targetElement: targetElement,
      fieldType: fieldType,
    );
  }

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (await compute0(builder)) {
      return;
    }
    var nameNode = node;
    if (nameNode is! SimpleIdentifier) {
      return;
    }
    _getterName = nameNode.name;
    if (!nameNode.inGetterContext()) {
      return;
    }
    // prepare target
    Expression? target;
    var nameParent = nameNode.parent;
    if (nameParent is PrefixedIdentifier) {
      target = nameParent.prefix;
    } else if (nameParent is PropertyAccess) {
      target = nameParent.realTarget;
    }

    // prepare target element
    var staticModifier = false;
    InstanceElement? targetElement;
    if (target is ExtensionOverride) {
      targetElement = target.element;
    } else if (target case Identifier(element: InstanceElement element)) {
      targetElement = element;
      staticModifier = true;
    } else if (target != null) {
      // prepare target interface type
      var targetType = target.staticType;
      if (targetType is! InterfaceType) {
        return;
      }
      targetElement = targetType.element;
      // maybe static
      if (target is Identifier) {
        var targetIdentifier = target;
        var targetElement = targetIdentifier.element;
        staticModifier = targetElement?.kind == ElementKind.CLASS;
      }
    } else if (nameParent is DotShorthandPropertyAccess) {
      staticModifier = true;
      targetElement = computeDotShorthandContextTypeElement(
        node,
        unitResult.libraryElement,
      );
    } else {
      staticModifier = inStaticContext;
      targetElement = nameNode.enclosingInstanceElement;
      if (targetElement is ExtensionElement) {
        if (staticModifier) {
          // This should be handled by create extension member fixes
          return;
        }
        targetElement = targetElement.extendedInterfaceElement;
      }
      if (targetElement == null) {
        return;
      }
    }

    var fieldTypeNode = climbPropertyAccess(nameNode);
    var fieldType = inferUndefinedExpressionType(fieldTypeNode);

    await _addDeclaration(
      builder: builder,
      staticModifier: staticModifier,
      targetElement: targetElement,
      fieldType: fieldType,
    );
  }

  Future<void> _addDeclaration({
    required ChangeBuilder builder,
    required bool staticModifier,
    required InstanceElement? targetElement,
    required DartType? fieldType,
  }) async {
    if (targetElement == null) {
      return;
    }

    var targetFragment = targetElement.firstFragment;
    var targetSource = targetFragment.libraryFragment.source;
    if (targetElement.library.isInSdk) {
      return;
    }
    // prepare target declaration
    var targetDeclarationResult = await sessionHelper.getFragmentDeclaration(
      targetFragment,
    );
    if (targetDeclarationResult == null) {
      return;
    }
    var targetNode = targetDeclarationResult.node;
    if (targetNode is CompilationUnitMember) {
      if (targetDeclarationResult.node is! ClassDeclaration &&
          targetDeclarationResult.node is! ExtensionDeclaration &&
          targetDeclarationResult.node is! ExtensionTypeDeclaration &&
          targetDeclarationResult.node is! MixinDeclaration) {
        return;
      }
    } else {
      return;
    }
    // Build method source.
    var targetFile = targetSource.fullName;
    await builder.addDartFileEdit(targetFile, (builder) {
      builder.insertGetter(targetNode, (builder) {
        builder.writeGetterDeclaration(
          _getterName,
          isStatic: staticModifier,
          nameGroupName: 'NAME',
          returnType: fieldType ?? typeProvider.dynamicType,
          returnTypeGroupName: 'TYPE',
        );
      });
    });
  }
}
