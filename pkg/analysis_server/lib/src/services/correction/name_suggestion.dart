// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/utilities/strings.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/utilities/extensions/string.dart';
import 'package:analyzer_plugin/src/utilities/string_utilities.dart';

/// Returns all variants of names by removing leading words one by one.
List<String> getCamelWordCombinations(String name) {
  var result = <String>[];
  var parts = getCamelWords(name);
  for (var i = 0; i < parts.length; i++) {
    var s1 = parts[i].toLowerCase();
    var s2 = parts.skip(i + 1).join();
    var suggestion = '$s1$s2';
    result.add(suggestion);
  }
  return result;
}

/// Returns possible names for a variable with the given expected type and
/// expression assigned.
List<String> getVariableNameSuggestionsForExpression(
  DartType? expectedType,
  Expression? assignedExpression,
  Set<String> excluded, {
  bool isMethod = false,
}) {
  String? prefix;

  if (isMethod) {
    // If we're in a build() method, use 'build' as the name prefix.
    var method = assignedExpression?.thisOrAncestorOfType<MethodDeclaration>();
    if (method != null) {
      var enclosingName = method.name.lexeme;
      if (enclosingName.startsWith('build')) {
        prefix = 'build';
      }
    }
  }

  var res = <String>{};
  // use expression
  if (assignedExpression != null) {
    var nameFromExpression = _getBaseNameFromExpression(assignedExpression);
    if (nameFromExpression != null) {
      if (nameFromExpression.startsWith('_')) {
        nameFromExpression = nameFromExpression.substring(1);
      }
      _addAll(
        excluded,
        res,
        getCamelWordCombinations(nameFromExpression),
        prefix: prefix,
      );
    }
    var nameFromParent = _getBaseNameFromLocationInParent(assignedExpression);
    if (nameFromParent != null) {
      _addAll(excluded, res, getCamelWordCombinations(nameFromParent));
    }
  }
  // use type
  if (expectedType != null && expectedType is! DynamicType) {
    if (expectedType.isDartCoreInt) {
      _addSingleCharacterName(excluded, res, 0x69);
    } else if (expectedType.isDartCoreDouble) {
      _addSingleCharacterName(excluded, res, 0x64);
    } else if (expectedType.isDartCoreString) {
      _addSingleCharacterName(excluded, res, 0x73);
    } else if (expectedType is InterfaceType) {
      var className = expectedType.element.name;
      if (className != null) {
        _addAll(excluded, res, getCamelWordCombinations(className));
      }
    }
  }
  // done
  return List.from(res);
}

/// Returns possible names for a [String] variable with [text] value.
List<String> getVariableNameSuggestionsForText(
  String text,
  Set<String> excluded,
) {
  // filter out everything except of letters and white spaces
  {
    var sb = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      var c = text.codeUnitAt(i);
      if (c.isLetter || c.isWhitespace) {
        sb.writeCharCode(c);
      }
    }
    text = sb.toString();
  }
  // make single camel-case text
  {
    var words = text.split(' ');
    var sb = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      var word = words[i];
      if (i > 0) {
        // `capitalize` won't return `null` unless `null` is passed in.
        word = capitalize(word)!;
      }
      sb.write(word);
    }
    text = sb.toString();
  }
  // split camel-case into separate suggested names
  var res = <String>{};
  _addAll(excluded, res, getCamelWordCombinations(text));
  return List.from(res);
}

/// Adds [toAdd] items which are not excluded.
void _addAll(
  Set<String> excluded,
  Set<String> result,
  Iterable<String> toAdd, {
  String? prefix,
}) {
  for (var item in toAdd) {
    // add name based on "item", but not "excluded"
    for (var suffix = 1; ; suffix++) {
      // prepare name, just "item" or "item2", "item3", etc
      var name = item;
      if (suffix > 1) {
        name += suffix.toString();
      }
      // add once found not excluded
      if (!excluded.contains(name)) {
        result.add(prefix == null ? name : '$prefix${capitalize(name)}');
        break;
      }
    }
  }
}

/// Adds to [result] either [c] or the first ASCII character after it.
void _addSingleCharacterName(Set<String> excluded, Set<String> result, int c) {
  while (c < 0x7A) {
    var name = String.fromCharCode(c);
    // may be done
    if (!excluded.contains(name)) {
      result.add(name);
      break;
    }
    // next character
    c = c + 1;
  }
}

String? _getBaseNameFromExpression(Expression expression) {
  if (expression is AsExpression) {
    return _getBaseNameFromExpression(expression.expression);
  } else if (expression is ParenthesizedExpression) {
    return _getBaseNameFromExpression(expression.expression);
  }
  return _getBaseNameFromUnwrappedExpression(expression);
}

String? _getBaseNameFromLocationInParent(Expression expression) {
  // value in named expression
  if (expression.parent is NamedExpression) {
    var namedExpression = expression.parent as NamedExpression;
    if (namedExpression.expression == expression) {
      return namedExpression.name.label.name;
    }
  }
  // positional argument
  var parameter = expression.correspondingParameter;
  if (parameter != null) {
    return parameter.displayName;
  }
  // unknown
  return null;
}

String? _getBaseNameFromUnwrappedExpression(Expression expression) {
  String? name;
  // analyze expressions
  if (expression is SimpleIdentifier) {
    return expression.name;
  } else if (expression is PrefixedIdentifier) {
    return expression.identifier.name;
  } else if (expression is PropertyAccess) {
    return expression.propertyName.name;
  } else if (expression is MethodInvocation) {
    name = expression.methodName.name;
  } else if (expression is InstanceCreationExpression) {
    var constructorName = expression.constructorName;
    var namedType = constructorName.type;
    var importPrefix = namedType.importPrefix;
    // new ClassName()
    if (importPrefix == null) {
      return namedType.name.lexeme;
    }
    // new prefix.ClassName()
    if (importPrefix.element is PrefixElement) {
      return namedType.name.lexeme;
    }
    // new ClassName.constructorName()
    return importPrefix.name.lexeme;
  } else if (expression is IndexExpression) {
    name = _getBaseNameFromExpression(expression.realTarget);
    if (name != null && name.endsWith('s')) {
      name = name.substring(0, name.length - 1);
    }
  }
  // Strip known prefixes.
  if (name != null) {
    const knownMethodNamePrefixes = ['get', 'is', 'to'];
    for (var knownPrefix in knownMethodNamePrefixes) {
      if (name.startsWith(knownPrefix)) {
        if (name == knownPrefix) {
          return null;
        } else if (isUpperCase(name.codeUnitAt(knownPrefix.length))) {
          return name.substring(knownPrefix.length);
        }
      }
    }
  }
  // done
  return name;
}
