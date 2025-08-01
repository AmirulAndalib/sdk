// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class CreateConstructor extends ResolvedCorrectionProducer {
  /// The name of the constructor being created.
  // TODO(migration): We set this node when we have the change.
  late String _constructorName;

  CreateConstructor({required super.context});

  @override
  CorrectionApplicability get applicability =>
      // TODO(applicability): comment on why.
      CorrectionApplicability.singleLocation;

  @override
  List<String> get fixArguments => [_constructorName];

  @override
  FixKind get fixKind => DartFixKind.CREATE_CONSTRUCTOR;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    var node = this.node;
    var argumentList = node.parent is ArgumentList ? node.parent : node;
    if (argumentList is ArgumentList) {
      var constructorInvocation = argumentList.parent;
      if (constructorInvocation is InstanceCreationExpression) {
        await _proposeFromConstructorInvocation(
          builder,
          constructorInvocation,
          constructorInvocation.constructorName.element,
          constructorInvocation.argumentList,
        );
      } else if (constructorInvocation is DotShorthandConstructorInvocation) {
        await _proposeFromConstructorInvocation(
          builder,
          constructorInvocation,
          constructorInvocation.element,
          constructorInvocation.argumentList,
        );
      }
    } else {
      if (node is SimpleIdentifier) {
        var parent = node.parent;
        if (parent is ConstructorName) {
          await _proposeFromConstructorName(builder, node.token, parent);
          return;
        } else if (parent is DotShorthandInvocation) {
          return await _proposeFromDotShorthandInvocation(
            builder,
            node.token,
            parent,
          );
        }
      }
      var parent = node.thisOrAncestorOfType<EnumConstantDeclaration>();
      if (parent != null) {
        await _proposeFromEnumConstantDeclaration(builder, parent.name, parent);
      }
    }
  }

  /// Common logic for building and writing a constructor from a
  /// [ConstructorName] or a [DotShorthandInvocation].
  Future<void> _finishCreatingConstructor(
    ChangeBuilder builder,
    InterfaceElement targetElement,
    Token name,
    ArgumentList? argumentList,
  ) async {
    var targetFragment = targetElement.firstFragment;
    var targetResult = await sessionHelper.getFragmentDeclaration(
      targetFragment,
    );
    if (targetResult == null) {
      return;
    }
    var targetNode = targetResult.node;
    if (targetNode is! ClassDeclaration) {
      return;
    }

    var resolvedUnit = targetResult.resolvedUnit;
    if (resolvedUnit == null) {
      return;
    }

    await _write(
      builder,
      resolvedUnit,
      name,
      targetNode,
      constructorName: name,
      argumentList: argumentList,
    );
  }

  Future<void> _proposeFromConstructorInvocation(
    ChangeBuilder builder,
    AstNode node,
    ConstructorElement? constructorElement,
    ArgumentList argumentList,
  ) async {
    _constructorName = node.toSource();
    // should be synthetic default constructor
    if (constructorElement == null ||
        !constructorElement.isDefaultConstructor ||
        !constructorElement.isSynthetic) {
      return;
    }

    var targetElement = constructorElement.enclosingElement;
    if (targetElement is! ClassElement) return;
    var targetFragment = targetElement.firstFragment;

    var targetElementName = targetElement.name;
    if (targetElementName == null) {
      return;
    }

    // prepare target ClassDeclaration
    var targetResult = await sessionHelper.getFragmentDeclaration(
      targetFragment,
    );
    if (targetResult == null) {
      return;
    }
    var targetNode = targetResult.node;
    if (targetNode is! ClassDeclaration) {
      return;
    }

    var resolvedUnit = targetResult.resolvedUnit;
    if (resolvedUnit == null) {
      return;
    }

    var targetSource = targetFragment.libraryFragment.source;
    var targetFile = targetSource.fullName;
    await builder.addDartFileEdit(targetFile, (builder) {
      builder.insertConstructor(targetNode, (builder) {
        builder.writeConstructorDeclaration(
          targetElementName,
          argumentList: argumentList,
        );
      });
    });
  }

  Future<void> _proposeFromConstructorName(
    ChangeBuilder builder,
    Token name,
    ConstructorName constructorName,
  ) async {
    InstanceCreationExpression? instanceCreation;
    _constructorName = constructorName.toSource();
    if (constructorName.name?.token == name) {
      var grandParent = constructorName.parent;
      // Type.name
      if (grandParent is InstanceCreationExpression) {
        instanceCreation = grandParent;
        // new Type.name()
        if (grandParent.constructorName != constructorName) {
          return;
        }
      }
    }

    // do we have enough information?
    if (instanceCreation == null) {
      return;
    }

    // prepare target interface type
    var targetType = constructorName.type.type;
    if (targetType is! InterfaceType) {
      return;
    }

    // prepare target ClassDeclaration
    var targetElement = targetType.element;
    await _finishCreatingConstructor(
      builder,
      targetElement,
      name,
      instanceCreation.argumentList,
    );
  }

  Future<void> _proposeFromDotShorthandInvocation(
    ChangeBuilder builder,
    Token name,
    DotShorthandInvocation node,
  ) async {
    _constructorName = node.toSource();
    var targetElement = computeDotShorthandContextTypeElement(
      node,
      unitResult.libraryElement,
    );
    if (targetElement == null) return;

    await _finishCreatingConstructor(
      builder,
      targetElement,
      name,
      node.argumentList,
    );
  }

  Future<void> _proposeFromEnumConstantDeclaration(
    ChangeBuilder builder,
    Token name,
    EnumConstantDeclaration parent,
  ) async {
    var grandParent = parent.parent;
    if (grandParent is! EnumDeclaration) {
      return;
    }
    var targetElement = grandParent.declaredFragment;
    if (targetElement == null) {
      return;
    }

    // prepare target interface type
    var targetResult = await sessionHelper.getFragmentDeclaration(
      targetElement,
    );
    if (targetResult == null) {
      return;
    }

    var targetNode = targetResult.node;
    if (targetNode is! EnumDeclaration) {
      return;
    }

    var resolvedUnit = targetResult.resolvedUnit;
    if (resolvedUnit == null) {
      return;
    }

    var arguments = parent.arguments;
    _constructorName =
        '${targetNode.name.lexeme}${arguments?.constructorSelector ?? ''}';

    await _write(
      builder,
      resolvedUnit,
      name,
      targetNode,
      isConst: true,
      constructorName: arguments?.constructorSelector?.name.token,
      argumentList: arguments?.argumentList,
    );
  }

  Future<void> _write(
    ChangeBuilder builder,
    ResolvedUnitResult resolvedUnit,
    Token name,
    NamedCompilationUnitMember unitMember, {
    Token? constructorName,
    bool isConst = false,
    ArgumentList? argumentList,
  }) async {
    var targetFile = resolvedUnit.file.path;
    await builder.addDartFileEdit(targetFile, (builder) {
      builder.insertConstructor(unitMember, (builder) {
        builder.writeConstructorDeclaration(
          unitMember.name.lexeme,
          isConst: isConst,
          argumentList: argumentList,
          constructorName: constructorName?.lexeme,
          constructorNameGroupName: 'NAME',
        );
      });
      if (targetFile == file) {
        builder.addLinkedPosition(range.token(name), 'NAME');
      }
    });
  }
}
