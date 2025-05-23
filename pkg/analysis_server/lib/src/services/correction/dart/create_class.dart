// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class CreateClass extends ResolvedCorrectionProducer {
  String className = '';

  CreateClass({required super.context});

  @override
  CorrectionApplicability get applicability =>
      // TODO(applicability): comment on why.
      CorrectionApplicability.singleLocation;

  @override
  List<String> get fixArguments => [className];

  @override
  FixKind get fixKind => DartFixKind.CREATE_CLASS;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    var targetNode = node;
    Element? prefixElement;
    ArgumentList? arguments;

    String? className;
    bool requiresConstConstructor = false;
    if (targetNode is Annotation) {
      var name = targetNode.name;
      arguments = targetNode.arguments;
      if (name.element != null || arguments == null) {
        // TODO(brianwilkerson): Consider supporting creating a class when the
        //  arguments are missing by also adding an empty argument list.
        return;
      }
      targetNode = name;
      requiresConstConstructor = true;
    }
    if (targetNode is NamedType) {
      var importPrefix = targetNode.importPrefix;
      if (importPrefix != null) {
        prefixElement = importPrefix.element2;
        if (prefixElement == null) {
          return;
        }
      }
      className = targetNode.name.lexeme;
      requiresConstConstructor |= _requiresConstConstructor(targetNode);
    } else if (targetNode case SimpleIdentifier(
      :var parent,
    ) when parent is! PropertyAccess && parent is! PrefixedIdentifier) {
      className = targetNode.nameOfType;
      requiresConstConstructor |= _requiresConstConstructor(targetNode);
    } else if (targetNode is PrefixedIdentifier) {
      prefixElement = targetNode.prefix.element;
      if (prefixElement == null) {
        return;
      }
      className = targetNode.identifier.nameOfType;
    } else {
      return;
    }

    if (className == null) {
      return;
    }
    this.className = className;

    // prepare environment
    LibraryFragment targetUnit;
    var prefix = '';
    var suffix = '';
    var offset = -1;
    String? filePath;
    if (prefixElement == null) {
      targetUnit = unit.declaredFragment!;
      var enclosingMember = targetNode.thisOrAncestorMatching(
        (node) =>
            node is CompilationUnitMember && node.parent is CompilationUnit,
      );
      if (enclosingMember == null) {
        return;
      }
      offset = enclosingMember.end;
      filePath = file;
      prefix = '$eol$eol';
    } else {
      for (var import in libraryElement2.firstFragment.libraryImports2) {
        if (prefixElement is PrefixElement &&
            import.prefix2?.element == prefixElement) {
          var library = import.importedLibrary2;
          if (library != null) {
            targetUnit = library.firstFragment;
            var targetSource = targetUnit.source;
            try {
              offset = targetSource.contents.data.length;
              filePath = targetSource.fullName;
              prefix = eol;
              suffix = eol;
            } on FileSystemException {
              // If we can't read the file to get the offset, then we can't
              // create a fix.
            }
            break;
          }
        }
      }
    }
    if (filePath == null || offset < 0) {
      return;
    }

    var className2 = className;
    await builder.addDartFileEdit(filePath, (builder) {
      builder.addInsertion(offset, (builder) {
        builder.write(prefix);
        if (arguments == null && !requiresConstConstructor) {
          builder.writeClassDeclaration(className2, nameGroupName: 'NAME');
        } else {
          builder.writeClassDeclaration(
            className2,
            nameGroupName: 'NAME',
            membersWriter: () {
              builder.write('  ');
              builder.writeConstructorDeclaration(
                className2,
                argumentList: arguments,
                classNameGroupName: 'NAME',
                isConst: requiresConstConstructor,
              );
              builder.writeln();
            },
          );
        }
        builder.write(suffix);
      });
      if (prefixElement == null) {
        builder.addLinkedPosition(range.node(targetNode), 'NAME');
      }
    });
  }

  static bool _requiresConstConstructor(AstNode node) {
    var parent = node.parent;
    // TODO(scheglov): remove after NamedType refactoring.
    if (node is SimpleIdentifier && parent is NamedType) {
      return _requiresConstConstructor(parent);
    }
    if (node is SimpleIdentifier && parent is MethodInvocation) {
      return parent.inConstantContext;
    }
    if (node is NamedType && parent is ConstructorName) {
      return _requiresConstConstructor(parent);
    }
    if (node is ConstructorName && parent is InstanceCreationExpression) {
      return parent.isConst;
    }
    return false;
  }
}

extension on AstNode {
  /// If this might be a type name, return its name.
  String? get nameOfType {
    var self = this;
    if (self is SimpleIdentifier) {
      var name = self.name;
      if (self.parent is NamedType || _isNameOfType(name)) {
        return name;
      }
    }
    return null;
  }

  /// Return `true` if the [name] is capitalized.
  static bool _isNameOfType(String name) {
    if (name.isEmpty) {
      return false;
    }
    var firstLetter = name.substring(0, 1);
    if (firstLetter.toUpperCase() != firstLetter) {
      return false;
    }
    return true;
  }
}
