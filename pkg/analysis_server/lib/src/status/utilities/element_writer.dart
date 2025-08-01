// Copyright (c) 2015, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:analysis_server/src/status/utilities/tree_writer.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/element/element.dart';

/// A visitor that will produce an HTML representation of an element structure.
class ElementWriter with TreeWriter {
  @override
  final StringBuffer buffer;

  /// Initialize a newly created element writer to write the HTML representation
  /// of visited elements on the given [buffer].
  ElementWriter(this.buffer);

  void write(Element element) {
    _writeElement(element);
    writeProperties(_computeProperties(element));
    _writeFragments(element);
    indentLevel++;
    try {
      for (var child in element.children) {
        write(child);
      }
    } finally {
      indentLevel--;
    }
  }

  /// Writes a representation of the properties of the given [element] to the
  /// buffer.
  Map<String, Object?> _computeProperties(Element element) {
    var properties = <String, Object?>{};

    properties['annotations'] = element.metadata.annotations;
    if (element is InterfaceElement) {
      properties['interfaces'] = element.interfaces;
      properties['isEnum'] = element is EnumElement;
      properties['mixins'] = element.mixins;
      properties['supertype'] = element.supertype;
      if (element is ClassElement) {
        properties['hasNonFinalField'] = element.hasNonFinalField;
        properties['isAbstract'] = element.isAbstract;
        properties['isMixinApplication'] = element.isMixinApplication;
        properties['isValidMixin'] = element.isValidMixin;
      }
    }
    if (element is FieldElementImpl) {
      properties['evaluationResult'] = element.evaluationResult;
    }
    if (element is LocalVariableElementImpl &&
        element.constantInitializer != null) {
      properties['evaluationResult'] = element.evaluationResult;
    }
    if (element is TopLevelVariableElementImpl) {
      properties['evaluationResult'] = element.evaluationResult;
    }
    if (element is ConstructorElement) {
      properties['isConst'] = element.isConst;
      properties['isDefaultConstructor'] = element.isDefaultConstructor;
      properties['isFactory'] = element.isFactory;
      properties['redirectedConstructor'] = element.redirectedConstructor;
    }
    if (element is ExecutableElement) {
      properties['hasImplicitReturnType'] = element.hasImplicitReturnType;
      properties['isAbstract'] = element.isAbstract;
      properties['isExternal'] = element.isExternal;
      if (element is MethodElement) {
        properties['isOperator'] = element.isOperator;
      }
      properties['isStatic'] = element.isStatic;
      properties['returnType'] = element.returnType;
      properties['type'] = element.type;
    }
    if (element is FieldElement) {
      properties['isEnumConstant'] = element.isEnumConstant;
    }
    if (element is FieldFormalParameterElement) {
      properties['field'] = element.field;
    }
    if (element is TopLevelFunctionElement) {
      properties['isEntryPoint'] = element.isEntryPoint;
    }
    if (element is FunctionTypedElement) {
      properties['returnType'] = element.returnType;
      properties['type'] = element.type;
    }
    if (element is LibraryElement) {
      properties['entryPoint'] = element.entryPoint;
      properties['isDartAsync'] = element.isDartAsync;
      properties['isDartCore'] = element.isDartCore;
      properties['isInSdk'] = element.isInSdk;
    }
    if (element is FormalParameterElement) {
      properties['defaultValueCode'] = element.defaultValueCode;
      properties['isInitializingFormal'] = element.isInitializingFormal;
      if (element.isRequiredPositional) {
        properties['parameterKind'] = 'required-positional';
      } else if (element.isRequiredNamed) {
        properties['parameterKind'] = 'required-named';
      } else if (element.isOptionalPositional) {
        properties['parameterKind'] = 'optional-positional';
      } else if (element.isOptionalNamed) {
        properties['parameterKind'] = 'optional-named';
      } else {
        properties['parameterKind'] = 'unknown kind';
      }
    }
    if (element is PropertyInducingElement) {
      properties['isStatic'] = element.isStatic;
    }
    if (element is TypeParameterElement) {
      properties['bound'] = element.bound;
    }
    if (element is TypeParameterizedElement) {
      properties['typeParameters'] = element.typeParameters;
    }
    if (element is VariableElement) {
      properties['hasImplicitType'] = element.hasImplicitType;
      properties['isConst'] = element.isConst;
      properties['isFinal'] = element.isFinal;
      properties['isStatic'] = element.isStatic;
      properties['type'] = element.type;
    }

    return properties;
  }

  /// Write a representation of the given [element] to the buffer.
  void _writeElement(Element element) {
    indent();
    if (element.isSynthetic) {
      buffer.write('<i>');
    }
    buffer.write(htmlEscape.convert(element.toString()));
    if (element.isSynthetic) {
      buffer.write('</i>');
    }
    buffer.write(' <span style="color:gray">(');
    buffer.write(element.runtimeType);
    buffer.write(')</span>');
    buffer.write('<br>');
  }

  /// Write a representation of the given [fragment] to the buffer.
  void _writeFragment(Fragment fragment, int index) {
    indent();
    buffer.write('fragments[$index]: ');
    buffer.write(fragment.name);
    buffer.write(' <span style="color:gray">(');
    buffer.write(fragment.runtimeType);
    buffer.write(')</span>');
    buffer.write('<br>');
    var properties = <String, Object?>{};
    if (fragment is LibraryFragment) {
      properties['source'] = fragment.source;
      properties['imports'] = {
        for (var import in fragment.libraryImports)
          {
            'combinators': import.combinators,
            if (import.prefix != null) 'prefix': import.prefix?.name,
            'isDeferred': import.prefix?.isDeferred ?? false,
            'library': import.importedLibrary,
          },
      };
      properties['imports'] = {
        for (var export in fragment.libraryExports)
          {
            'combinators': export.combinators,
            'library': export.exportedLibrary,
          },
      };
    }
    properties['nameOffset'] = fragment.nameOffset;
    if (fragment is ExecutableFragment) {
      properties['isAsynchronous'] = fragment.isAsynchronous;
      properties['isGenerator'] = fragment.isGenerator;
      properties['isSynchronous'] = fragment.isSynchronous;
    }
    writeProperties(properties);
  }

  void _writeFragments(Element element) {
    indentLevel++;
    try {
      var index = 0;
      Fragment? fragment = element.firstFragment;
      while (fragment != null) {
        _writeFragment(fragment, index++);
        fragment = fragment.nextFragment;
      }
    } finally {
      indentLevel--;
    }
  }
}
