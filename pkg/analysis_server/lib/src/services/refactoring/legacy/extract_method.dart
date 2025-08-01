// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/protocol_server.dart' hide Element;
import 'package:analysis_server/src/services/correction/name_suggestion.dart';
import 'package:analysis_server/src/services/correction/selection_analyzer.dart';
import 'package:analysis_server/src/services/correction/statement_analyzer.dart';
import 'package:analysis_server/src/services/correction/status.dart';
import 'package:analysis_server/src/services/correction/util.dart';
import 'package:analysis_server/src/services/refactoring/legacy/naming_conventions.dart';
import 'package:analysis_server/src/services/refactoring/legacy/refactoring.dart';
import 'package:analysis_server/src/services/refactoring/legacy/refactoring_internal.dart';
import 'package:analysis_server/src/services/refactoring/legacy/rename_class_member.dart';
import 'package:analysis_server/src/services/refactoring/legacy/rename_unit_member.dart';
import 'package:analysis_server/src/services/refactoring/legacy/visible_ranges_computer.dart';
import 'package:analysis_server/src/services/search/search_engine.dart';
import 'package:analysis_server_plugin/edit/correction_utils.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/src/dart/analysis/session_helper.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/ast/extensions.dart';
import 'package:analyzer/src/dart/resolver/exit_detector.dart';
import 'package:analyzer/src/generated/java_core.dart';
import 'package:analyzer/src/utilities/extensions/ast.dart';
import 'package:analyzer/src/utilities/extensions/string.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:meta/meta.dart';

const String _tokenSeparator = '\uFFFF';

/// Adds edits to the given [change] that ensure that all the [libraries] are
/// imported into the given [targetLibrary2].
@visibleForTesting
Future<void> addLibraryImports(
  AnalysisSession session,
  SourceChange change,
  LibraryElement targetLibrary2,
  Set<Source> libraries,
) async {
  var libraryPath = targetLibrary2.firstFragment.source.fullName;

  var resolveResult = await session.getResolvedUnit(libraryPath);
  if (resolveResult is! ResolvedUnitResult) {
    return;
  }

  var libUtils = CorrectionUtils(resolveResult);
  var eol = libUtils.endOfLine;
  // Prepare information about existing imports.
  var directives = resolveResult.unit.directives;
  var libraryDirective = directives.whereType<LibraryDirective>().firstOrNull;
  var importDirectives = [
    for (var directive in directives)
      if (directive case ImportDirective(uri: StringLiteral(:var stringValue?)))
        _ImportDirectiveInfo(stringValue, directive.offset, directive.end),
  ];

  // Prepare all URIs to import.
  var uriList =
      libraries
          .map(
            (library) => getLibrarySourceUri(
              session.resourceProvider.pathContext,
              targetLibrary2,
              library.uri,
            ),
          )
          .toList()
        ..sort((a, b) => a.compareTo(b));

  var analysisOptions = session.analysisContext.getAnalysisOptionsForFile(
    resolveResult.file,
  );
  var quote = analysisOptions.codeStyleOptions.preferredQuoteForUris(
    directives.whereType<NamespaceDirective>(),
  );

  // Insert imports: between existing imports.
  if (importDirectives.isNotEmpty) {
    var isFirstPackage = true;
    for (var importUri in uriList) {
      var inserted = false;
      var isPackage = importUri.startsWith('package:');
      var isAfterDart = false;
      for (var existingImport in importDirectives) {
        if (existingImport.uri.startsWith('dart:')) {
          isAfterDart = true;
        }
        if (existingImport.uri.startsWith('package:')) {
          isFirstPackage = false;
        }
        if (importUri.compareTo(existingImport.uri) < 0) {
          var importCode = 'import $quote$importUri$quote;$eol';
          doSourceChange_addFragmentEdit(
            change,
            targetLibrary2.firstFragment,
            SourceEdit(existingImport.offset, 0, importCode),
          );
          inserted = true;
          break;
        }
      }
      if (!inserted) {
        var importCode = '${eol}import $quote$importUri$quote;';
        if (isPackage && isFirstPackage && isAfterDart) {
          importCode = eol + importCode;
        }
        doSourceChange_addFragmentEdit(
          change,
          targetLibrary2.firstFragment,
          SourceEdit(importDirectives.last.end, 0, importCode),
        );
      }
      if (isPackage) {
        isFirstPackage = false;
      }
    }
    return;
  }

  // Insert imports: after the library directive.
  if (libraryDirective != null) {
    var prefix = eol + eol;
    for (var importUri in uriList) {
      var importCode = '${prefix}import $quote$importUri$quote;';
      prefix = eol;
      doSourceChange_addFragmentEdit(
        change,
        targetLibrary2.firstFragment,
        SourceEdit(libraryDirective.end, 0, importCode),
      );
    }
    return;
  }

  // If still at the beginning of the file, skip hash-bang and line comments.
  {
    // Skip leading line comments.
    var offset = 0;
    var insertEmptyLineBefore = false;
    var insertEmptyLineAfter = false;
    var source = resolveResult.content;
    // Skip hash-bang.
    if (offset < source.length - 2) {
      var linePrefix = libUtils.getText(offset, 2);
      if (linePrefix == '#!') {
        insertEmptyLineBefore = true;
        offset = libUtils.getLineNext(offset);
        // Skip empty lines to first line comment.
        var emptyOffset = offset;
        while (emptyOffset < source.length - 2) {
          var nextLineOffset = libUtils.getLineNext(emptyOffset);
          var line = source.substring(emptyOffset, nextLineOffset);
          if (line.trim().isEmpty) {
            emptyOffset = nextLineOffset;
            continue;
          } else if (line.startsWith('//')) {
            offset = emptyOffset;
            break;
          } else {
            break;
          }
        }
      }
    }
    // Skip line comments.
    while (offset < source.length - 2) {
      var linePrefix = libUtils.getText(offset, 2);
      if (linePrefix == '//') {
        insertEmptyLineBefore = true;
        offset = libUtils.getLineNext(offset);
      } else {
        break;
      }
    }
    // Determine if empty line is required after.
    var nextLineOffset = libUtils.getLineNext(offset);
    var insertLine = source.substring(offset, nextLineOffset);
    if (insertLine.trim().isNotEmpty) {
      insertEmptyLineAfter = true;
    }

    for (var i = 0; i < uriList.length; i++) {
      var importUri = uriList[i];
      var importCode = 'import $quote$importUri$quote;$eol';
      if (i == 0 && insertEmptyLineBefore) {
        importCode = '$eol$importCode';
      }
      if (i == uriList.length - 1 && insertEmptyLineAfter) {
        importCode = '$importCode$eol';
      }
      doSourceChange_addFragmentEdit(
        change,
        targetLibrary2.firstFragment,
        SourceEdit(offset, 0, importCode),
      );
    }
  }
}

bool isLocalElement(Element? element) {
  return element is LocalVariableElement ||
      element is FormalParameterElement ||
      element is LocalFunctionElement;
}

Element? _getLocalElement(SimpleIdentifier node) {
  var element = node.writeOrReadElement;
  if (isLocalElement(element)) {
    return element;
  }
  return null;
}

/// Returns the "normalized" version of the given source, which is reconstructed
/// from tokens, so ignores all the comments and spaces.
String _getNormalizedSource(String src, FeatureSet featureSet) {
  var selectionTokens = TokenUtils.getTokens(src, featureSet);
  return selectionTokens.join(_tokenSeparator);
}

/// Returns the [Map] which maps [map] values to their keys.
Map<String, String> _inverseMap(Map<String, String> map) {
  var result = <String, String>{};
  map.forEach((String key, String value) {
    result[value] = key;
  });
  return result;
}

/// [ExtractMethodRefactoring] implementation.
final class ExtractMethodRefactoringImpl extends RefactoringImpl
    implements ExtractMethodRefactoring {
  static const errorExits =
      'Selected statements contain a return statement, but not all possible '
      'execution flows exit. Semantics may not be preserved.';

  final SearchEngine _searchEngine;
  final ResolvedUnitResult _resolveResult;
  final int _selectionOffset;
  final int _selectionLength;
  SourceRange _selectionRange;
  final CorrectionUtils _utils;
  final Set<Source> _librariesToImport = <Source>{};

  @override
  String returnType = '';
  String? _variableType;
  late String name;
  bool extractAll = true;
  @override
  bool canCreateGetter = false;
  bool createGetter = false;
  @override
  final List<String> names = <String>[];
  @override
  final List<int> offsets = <int>[];
  @override
  final List<int> lengths = <int>[];

  /// The map of local elements to their visibility ranges.
  late Map<LocalElement, SourceRange> _visibleRangeMap;

  /// The map of local names to their visibility ranges.
  final Map<String, List<SourceRange>> _localNames =
      <String, List<SourceRange>>{};

  /// The set of names that are referenced without any qualifier.
  final Set<String> _unqualifiedNames = <String>{};

  final Set<String> _excludedNames = <String>{};
  List<RefactoringMethodParameter> _parameters = <RefactoringMethodParameter>[];
  final Map<String, RefactoringMethodParameter> _parametersMap =
      <String, RefactoringMethodParameter>{};
  final Map<String, List<SourceRange>> _parameterReferencesMap =
      <String, List<SourceRange>>{};
  bool _hasAwait = false;
  DartType? _returnType;
  String? _returnVariableName;
  AstNode? _parentMember;
  Expression? _selectionExpression;
  FunctionExpression? _selectionFunctionExpression;
  List<Statement>? _selectionStatements;
  final List<_Occurrence> _occurrences = [];
  bool _staticContext = false;

  ExtractMethodRefactoringImpl(
    this._searchEngine,
    this._resolveResult,
    this._selectionOffset,
    this._selectionLength,
  ) : _selectionRange = SourceRange(_selectionOffset, _selectionLength),
      _utils = CorrectionUtils(_resolveResult);

  @override
  List<RefactoringMethodParameter> get parameters => _parameters;

  @override
  set parameters(List<RefactoringMethodParameter> parameters) {
    _parameters = parameters.toList();
  }

  @override
  String get refactoringName {
    var node = _resolveResult.unit.nodeCovering(offset: _selectionOffset);
    if (node != null && node.thisOrAncestorOfType<ClassDeclaration>() != null) {
      return 'Extract Method';
    }
    return 'Extract Function';
  }

  String get signature {
    var sb = StringBuffer();
    if (createGetter) {
      sb.write('get ');
      sb.write(name);
    } else {
      sb.write(name);
      sb.write('(');
      // add all parameters
      var firstParameter = true;
      for (var parameter in _parameters) {
        // may be comma
        if (firstParameter) {
          firstParameter = false;
        } else {
          sb.write(', ');
        }
        // type
        {
          var typeSource = parameter.type;
          if ('dynamic' != typeSource && '' != typeSource) {
            sb.write(typeSource);
            sb.write(' ');
          }
        }
        // optional function-typed parameter parameters
        if (parameter.parameters != null) {
          sb.write('Function');
          sb.write(parameter.parameters);
          sb.write(' ');
        }
        // name
        sb.write(parameter.name);
      }
      sb.write(')');
    }
    // done
    return sb.toString();
  }

  @override
  Future<RefactoringStatus> checkFinalConditions() async {
    var result = RefactoringStatus();
    result.addStatus(validateMethodName(name));
    result.addStatus(_checkParameterNames());
    var status = await _checkPossibleConflicts();
    result.addStatus(status);
    return result;
  }

  @override
  Future<RefactoringStatus> checkInitialConditions() async {
    var result = RefactoringStatus();
    // selection
    result.addStatus(_checkSelection());
    if (result.hasFatalError) {
      return result;
    }
    // prepare parts
    var status = await _initializeParameters();
    result.addStatus(status);
    _initializeHasAwait();
    await _initializeReturnType();
    // occurrences
    _initializeOccurrences();
    _prepareOffsetsLengths();
    // getter
    canCreateGetter = _computeCanCreateGetter();
    createGetter =
        canCreateGetter && _isExpressionForGetter(_selectionExpression);
    // names
    _prepareExcludedNames();
    _prepareNames();
    // Closure cannot have parameters.
    if (_selectionFunctionExpression != null && _parameters.isNotEmpty) {
      // All referenced external variables are stored in this list of named
      // variables.
      var variables = _parameters.map((parameter) => parameter.name).toList();
      var count = variables.length;
      var result = variables.quotedAndCommaSeparatedWithAnd;
      var message =
          'Cannot extract the closure as a method,'
          'it references the external ${'variable'.pluralized(count)} $result.';
      return RefactoringStatus.fatal(message);
    }
    return result;
  }

  @override
  RefactoringStatus checkName() {
    return validateMethodName(name);
  }

  @override
  Future<SourceChange> createChange() async {
    var change = SourceChange(refactoringName);
    // replace occurrences with method invocation
    for (var occurrence in _occurrences) {
      var range = occurrence.range;
      // may be replacement of duplicates disabled
      if (!extractAll && !occurrence.isSelection) {
        continue;
      }
      // prepare invocation source
      String invocationSource;
      if (_selectionFunctionExpression != null) {
        invocationSource = name;
      } else {
        var sb = StringBuffer();
        // may be returns value
        if (_selectionStatements != null && _variableType != null) {
          // single variable assignment / return statement
          if (_returnVariableName != null) {
            var occurrenceName =
                occurrence._parameterOldToOccurrenceName[_returnVariableName];
            // may be declare variable
            if (!_parametersMap.containsKey(_returnVariableName)) {
              if (_variableType!.isEmpty) {
                sb.write('var ');
              } else {
                sb.write(_variableType);
                sb.write(' ');
              }
            }
            // assign the return value
            sb.write(occurrenceName);
            sb.write(' = ');
          } else {
            sb.write('return ');
          }
        }
        // await
        if (_hasAwait) {
          sb.write('await ');
        }
        // invocation itself
        sb.write(name);
        if (!createGetter) {
          sb.write('(');
          var firstParameter = true;
          for (var parameter in _parameters) {
            // may be comma
            if (firstParameter) {
              firstParameter = false;
            } else {
              sb.write(', ');
            }
            // argument name
            {
              var argumentName =
                  occurrence._parameterOldToOccurrenceName[parameter.id];
              sb.write(argumentName);
            }
          }
          sb.write(')');
        }
        invocationSource = sb.toString();
        // statements as extracted with their ";", so add new after invocation
        if (_selectionStatements != null) {
          invocationSource += ';';
        }
      }
      // add replace edit
      var edit = newSourceEdit_range(range, invocationSource);
      doSourceChange_addFragmentEdit(
        change,
        _resolveResult.unit.declaredFragment!,
        edit,
      );
    }
    // add method declaration
    {
      // prepare environment
      var prefix = _utils.getNodePrefix(_parentMember!);
      var eol = _utils.endOfLine;
      // prepare annotations
      var annotations = '';
      {
        // may be "static"
        if (_staticContext) {
          annotations = 'static ';
        }
      }
      // prepare declaration source
      String? declarationSource;
      {
        var returnExpressionSource = _getMethodBodySource();
        // closure
        var selectionFunctionExpression = _selectionFunctionExpression;
        if (selectionFunctionExpression != null) {
          var returnTypeCode = _getExpectedClosureReturnTypeCode();
          declarationSource =
              '$annotations$returnTypeCode$name$returnExpressionSource';
          if (selectionFunctionExpression.body is ExpressionFunctionBody) {
            declarationSource += ';';
          }
        }
        // optional 'async' body modifier
        var asyncKeyword = _hasAwait ? ' async' : '';
        // expression
        if (_selectionExpression != null) {
          var isMultiLine = returnExpressionSource.contains(eol);

          // We generate the method body using the shorthand syntax if it fits
          // into a single line and use the regular method syntax otherwise.
          if (!isMultiLine) {
            // add return type
            if (returnType.isNotEmpty) {
              annotations += '$returnType ';
            }
            // just return expression
            declarationSource = '$annotations$signature$asyncKeyword => ';
            declarationSource += '$returnExpressionSource;';
          } else {
            // Left indent once; returnExpressionSource was indented for method
            // shorthands.
            returnExpressionSource =
                _utils
                    .indentSourceLeftRight('${returnExpressionSource.trim()};')
                    .trim();

            // add return type
            if (returnType.isNotEmpty) {
              annotations += '$returnType ';
            }
            declarationSource = '$annotations$signature$asyncKeyword {$eol';
            declarationSource += '$prefix  ';
            if (returnType.isNotEmpty) {
              declarationSource += 'return ';
            }
            declarationSource += '$returnExpressionSource$eol$prefix}';
          }
        }
        // statements
        if (_selectionStatements != null) {
          if (returnType.isNotEmpty) {
            annotations += '$returnType ';
          }
          declarationSource = '$annotations$signature$asyncKeyword {$eol';
          declarationSource += returnExpressionSource;
          if (_returnVariableName != null) {
            declarationSource += '$prefix  return $_returnVariableName;$eol';
          }
          declarationSource += '$prefix}';
        }
      }
      // insert declaration
      if (declarationSource != null) {
        var offset = _parentMember!.end;
        var edit = SourceEdit(offset, 0, '$eol$eol$prefix$declarationSource');
        doSourceChange_addFragmentEdit(
          change,
          _resolveResult.unit.declaredFragment!,
          edit,
        );
      }
    }
    // done
    await addLibraryImports(
      _resolveResult.session,
      change,
      _resolveResult.libraryElement,
      _librariesToImport,
    );
    return change;
  }

  @override
  bool isAvailable() {
    return !_checkSelection().hasFatalError;
  }

  /// Adds a new reference to the parameter with the given name.
  void _addParameterReference(String name, SourceRange range) {
    var references = _parameterReferencesMap[name];
    if (references == null) {
      references = [];
      _parameterReferencesMap[name] = references;
    }
    references.add(range);
  }

  RefactoringStatus _checkParameterNames() {
    var result = RefactoringStatus();
    for (var parameter in _parameters) {
      result.addStatus(validateParameterName(parameter.name));
      for (var other in _parameters) {
        if (!identical(parameter, other) && other.name == parameter.name) {
          result.addError(
            formatList("Parameter '{0}' already exists", [parameter.name]),
          );
          return result;
        }
      }
      if (_isParameterNameConflictWithBody(parameter)) {
        result.addError(
          formatList("'{0}' is already used as a name in the selected code", [
            parameter.name,
          ]),
        );
        return result;
      }
    }
    return result;
  }

  /// Checks if created method will shadow or will be shadowed by other
  /// elements.
  Future<RefactoringStatus> _checkPossibleConflicts() async {
    var result = RefactoringStatus();
    var parent = _parentMember!.parent;
    // top-level function
    if (parent is CompilationUnit) {
      var libraryElement = parent.declaredFragment!.element;
      return validateCreateFunction(_searchEngine, libraryElement, name);
    }
    // method of class
    InterfaceElement? interfaceElement;
    if (parent is ClassDeclaration) {
      interfaceElement = parent.declaredFragment?.element;
    } else if (parent is EnumDeclaration) {
      interfaceElement = parent.declaredFragment?.element;
    } else if (parent is ExtensionTypeDeclaration) {
      interfaceElement = parent.declaredFragment?.element;
    } else if (parent is MixinDeclaration) {
      interfaceElement = parent.declaredFragment?.element;
    }
    if (interfaceElement != null) {
      return validateCreateMethod(
        _searchEngine,
        AnalysisSessionHelper(_resolveResult.session),
        interfaceElement,
        name,
      );
    }
    // OK
    return result;
  }

  /// Checks if [_selectionRange] selects [Expression] which can be extracted,
  /// and location of this [Expression] in AST allows extracting.
  RefactoringStatus _checkSelection() {
    if (_selectionOffset <= 0) {
      return RefactoringStatus.fatal(
        'The selection offset must be greater than zero.',
      );
    }
    if (_selectionOffset + _selectionLength >= _resolveResult.content.length) {
      return RefactoringStatus.fatal(
        'The selection end offset must be less than the length of the file.',
      );
    }

    // Check for implicitly selected closure.
    {
      var function = _findFunctionExpression();
      if (function != null) {
        _selectionFunctionExpression = function;
        _selectionRange = range.node(function);
        _parentMember = getEnclosingClassOrUnitMember(function);
        return RefactoringStatus();
      }
    }

    var analyzer = _ExtractMethodAnalyzer(_resolveResult, _selectionRange);
    analyzer.analyze();
    // May be a fatal error.
    {
      if (analyzer.status.hasFatalError) {
        return analyzer.status;
      }
    }

    var selectedNodes = analyzer.selectedNodes;

    // If no selected nodes, extract the smallest covering expression.
    if (selectedNodes.isEmpty) {
      for (var node = analyzer.coveringNode; node != null; node = node.parent) {
        if (node is Statement) {
          break;
        }
        if (node is Expression && _isExtractable(range.node(node))) {
          selectedNodes.add(node);
          _selectionRange = range.node(node);
          break;
        }
      }
    }

    // Check selected nodes.
    if (selectedNodes.isNotEmpty) {
      var selectedNode = selectedNodes.first;
      _parentMember = getEnclosingClassOrUnitMember(selectedNode);
      // single expression selected
      if (selectedNodes.length == 1) {
        if (!_selectionIncludesNonWhitespaceOutsideNode(
          _selectionRange,
          selectedNode,
        )) {
          if (selectedNode is Expression) {
            _selectionExpression = selectedNode;
            // additional check for closure
            if (_selectionExpression is FunctionExpression) {
              _selectionFunctionExpression =
                  _selectionExpression as FunctionExpression;
              _selectionExpression = null;
            }
            // OK
            return RefactoringStatus();
          }
        }
      }
      // statements selected
      {
        var selectedStatements = <Statement>[];
        for (var selectedNode in selectedNodes) {
          if (selectedNode is Statement) {
            selectedStatements.add(selectedNode);
          }
        }
        if (selectedStatements.length == selectedNodes.length) {
          _selectionStatements = selectedStatements;
          return RefactoringStatus();
        }
      }
    }
    // invalid selection
    return RefactoringStatus.fatal(
      'Can only extract a single expression or a set of statements.',
    );
  }

  /// Initializes [canCreateGetter] flag.
  bool _computeCanCreateGetter() {
    // is a function expression
    if (_selectionFunctionExpression != null) {
      return false;
    }
    // has parameters
    if (parameters.isNotEmpty) {
      return false;
    }
    // is assignment
    if (_selectionExpression != null) {
      if (_selectionExpression is AssignmentExpression) {
        return false;
      }
    }
    // doesn't return a value
    if (_selectionStatements != null) {
      return returnType != 'void';
    }
    // OK
    return true;
  }

  /// If the [_selectionRange] is associated with a [FunctionExpression], return
  /// this [FunctionExpression].
  FunctionExpression? _findFunctionExpression() {
    if (_selectionRange.length != 0) {
      return null;
    }
    var offset = _selectionRange.offset;
    var node = _resolveResult.unit.nodeCovering(offset: offset);

    // Check for the parameter list of a FunctionExpression.
    {
      var function = node?.thisOrAncestorOfType<FunctionExpression>();
      if (function != null) {
        var parameters = function.parameters;
        if (parameters != null &&
            range.node(parameters).contains(offset) &&
            // Don't include function declarations, only closures.
            function.parent is! FunctionDeclaration) {
          return function;
        }
      }
    }

    // Check for the name of the named argument with the closure expression.
    if (node is SimpleIdentifier) {
      var label = node.parent;
      if (label is Label) {
        var namedExpression = label.parent;
        if (namedExpression is NamedExpression) {
          var expression = namedExpression.expression;
          if (expression is FunctionExpression) {
            return expression;
          }
        }
      }
    }

    return null;
  }

  /// If the selected closure (i.e. [_selectionFunctionExpression]) is an
  /// argument for a function typed parameter (as it should be), and the
  /// function type has the return type specified, return this return type's
  /// code. Otherwise return the empty string.
  String _getExpectedClosureReturnTypeCode() {
    Expression argument = _selectionFunctionExpression!;
    if (argument.parent is NamedExpression) {
      argument = argument.parent as NamedExpression;
    }
    var parameter = argument.correspondingParameter;
    if (parameter != null) {
      var parameterType = parameter.type;
      if (parameterType is FunctionType) {
        var typeCode = _getTypeCode(parameterType.returnType);
        if (typeCode != 'dynamic') {
          return '$typeCode ';
        }
      }
    }
    return '';
  }

  /// Returns the selected [Expression] source, with applying new parameter
  /// names.
  String _getMethodBodySource() {
    var source = _utils.getRangeText(_selectionRange);
    // prepare operations to replace variables with parameters
    var replaceEdits = <SourceEdit>[];
    for (var parameter in _parameters) {
      var ranges = _parameterReferencesMap[parameter.id];
      if (ranges != null) {
        for (var range in ranges) {
          replaceEdits.add(
            SourceEdit(
              range.offset - _selectionRange.offset,
              range.length,
              parameter.name,
            ),
          );
        }
      }
    }
    replaceEdits.sort((a, b) => b.offset - a.offset);
    // apply replacements
    source = SourceEdit.applySequence(source, replaceEdits);
    // change indentation
    var selectionFunctionExpression = _selectionFunctionExpression;
    if (selectionFunctionExpression != null) {
      var baseNode =
          selectionFunctionExpression.thisOrAncestorOfType<Statement>();
      if (baseNode != null) {
        var baseIndent = _utils.getNodePrefix(baseNode);
        var targetIndent = _utils.getNodePrefix(_parentMember!);
        source = _utils.replaceSourceIndent(source, baseIndent, targetIndent);
        source = source.trim();
      }
    }
    var selectionStatements = _selectionStatements;
    if (selectionStatements != null) {
      var selectionIndent = _utils.getNodePrefix(selectionStatements[0]);
      var targetIndent = '${_utils.getNodePrefix(_parentMember!)}  ';
      source = _utils.replaceSourceIndent(
        source,
        selectionIndent,
        targetIndent,
        includeLeading: true,
        ensureTrailingNewline: true,
      );
    }
    // done
    return source;
  }

  _SourcePattern _getSourcePattern(SourceRange range) {
    var originalSource = _utils.getText(range.offset, range.length);
    var pattern = _SourcePattern();
    var replaceEdits = <SourceEdit>[];
    _resolveResult.unit.accept(
      _GetSourcePatternVisitor(range, pattern, replaceEdits),
    );
    replaceEdits = replaceEdits.reversed.toList();
    var source = SourceEdit.applySequence(originalSource, replaceEdits);
    pattern.normalizedSource = _getNormalizedSource(
      source,
      _resolveResult.unit.featureSet,
    );
    return pattern;
  }

  String _getTypeCode(DartType type) =>
      _resolveResult.libraryElement.getTypeSource(type, _librariesToImport)!;

  void _initializeHasAwait() {
    var visitor = _HasAwaitVisitor();
    if (_selectionExpression != null) {
      _selectionExpression!.accept(visitor);
    } else if (_selectionStatements != null) {
      for (var statement in _selectionStatements!) {
        statement.accept(visitor);
      }
    }
    _hasAwait = visitor.result;
  }

  /// Fills [_occurrences] field.
  void _initializeOccurrences() {
    _occurrences.clear();
    // prepare selection
    var selectionPattern = _getSourcePattern(_selectionRange);
    var patternToSelectionName = _inverseMap(
      selectionPattern.originalToPatternNames,
    );
    // prepare an enclosing parent - class or unit
    var enclosingMemberParent = _parentMember!.parent!;
    // visit nodes which will able to access extracted method
    enclosingMemberParent.accept(
      _InitializeOccurrencesVisitor(
        this,
        selectionPattern,
        patternToSelectionName,
      ),
    );
  }

  /// Prepares information about used variables, which should be turned into
  /// parameters.
  Future<RefactoringStatus> _initializeParameters() async {
    _parameters.clear();
    _parametersMap.clear();
    _parameterReferencesMap.clear();
    var result = RefactoringStatus();
    var assignedUsedVariables = <VariableElement>[];

    var unit = _resolveResult.unit;
    _visibleRangeMap = VisibleRangesComputer.forNode(unit);
    unit.accept(_InitializeParametersVisitor(this, assignedUsedVariables));

    // single expression
    var selectionExpression = _selectionExpression;
    if (selectionExpression != null) {
      _returnType = selectionExpression.typeOrThrow;
    }
    // verify that none or all execution flows end with a "return"
    var selectionStatements = _selectionStatements;
    if (selectionStatements != null) {
      var hasReturn = selectionStatements.any(_mayEndWithReturnStatement);
      if (hasReturn && !ExitDetector.exits(selectionStatements.last)) {
        result.addError(errorExits);
      }
    }
    // Maybe ends with a "return" statement.
    if (selectionStatements != null) {
      var returnTypeComputer = ReturnTypeComputer(_resolveResult.typeSystem);
      for (var statement in selectionStatements) {
        statement.accept(returnTypeComputer);
      }
      _returnType = returnTypeComputer.returnType;
    }
    // maybe single variable to return
    if (assignedUsedVariables.length == 1) {
      // we cannot both return variable and have explicit return statement
      if (_returnType != null) {
        result.addFatalError(
          'Ambiguous return value: Selected block contains assignment(s) to '
          'local variables and return statement.',
        );
        return result;
      }
      // prepare to return an assigned variable
      var returnVariable = assignedUsedVariables[0];
      _returnType = returnVariable.type;
      _returnVariableName = returnVariable.displayName;
    }
    // fatal, if multiple variables assigned and used after selection
    if (assignedUsedVariables.length > 1) {
      var sb = StringBuffer();
      for (var variable in assignedUsedVariables) {
        sb.write(variable.displayName);
        sb.write('\n');
      }
      result.addFatalError(
        formatList(
          'Ambiguous return value: Selected block contains more than one '
          'assignment to local variables. Affected variables are:\n\n{0}',
          [sb.toString().trim()],
        ),
      );
    }
    // done
    return result;
  }

  Future<void> _initializeReturnType() async {
    var typeProvider = _resolveResult.typeProvider;
    var returnTypeObj = _returnType;
    if (_selectionFunctionExpression != null) {
      _variableType = '';
      returnType = '';
    } else if (returnTypeObj == null) {
      _variableType = null;
      if (_hasAwait) {
        var futureVoid = typeProvider.futureType(typeProvider.voidType);
        returnType = _getTypeCode(futureVoid);
      } else {
        returnType = 'void';
      }
    } else if (returnTypeObj is DynamicType) {
      _variableType = '';
      if (_hasAwait) {
        returnType = _getTypeCode(typeProvider.futureDynamicType);
      } else {
        returnType = '';
      }
    } else {
      _variableType = _getTypeCode(returnTypeObj);
      if (_hasAwait) {
        if (returnTypeObj is InterfaceType &&
            returnTypeObj.element != typeProvider.futureElement) {
          returnType = _getTypeCode(typeProvider.futureType(returnTypeObj));
        }
      } else {
        returnType = _variableType!;
      }
    }
  }

  /// Checks if the given [element] is declared in [_selectionRange].
  bool _isDeclaredInSelection(Element element) {
    return _selectionRange.contains(element.firstFragment.nameOffset!);
  }

  /// Checks if it is OK to extract the node with the given [SourceRange].
  bool _isExtractable(SourceRange range) {
    var analyzer = _ExtractMethodAnalyzer(_resolveResult, range);
    analyzer.analyze();
    return analyzer.status.isOK;
  }

  /// Returns whether [range] contains only whitespace or comments.
  bool _isJustWhitespaceOrComment(SourceRange range) {
    var trimmedText = _utils.getRangeText(range).trim();
    // May be whitespace.
    if (trimmedText.isEmpty) {
      return true;
    }
    // May be comment.
    return TokenUtils.getTokens(
      trimmedText,
      _resolveResult.unit.featureSet,
    ).isEmpty;
  }

  bool _isParameterNameConflictWithBody(RefactoringMethodParameter parameter) {
    var id = parameter.id;
    var name = parameter.name;
    var parameterRanges = _parameterReferencesMap[id];
    var otherRanges = _localNames[name];
    for (var parameterRange in parameterRanges!) {
      if (otherRanges != null) {
        for (var otherRange in otherRanges) {
          if (parameterRange.intersects(otherRange)) {
            return true;
          }
        }
      }
    }
    if (_unqualifiedNames.contains(name)) {
      return true;
    }
    return false;
  }

  /// Checks if [element] is referenced after [_selectionRange].
  bool _isUsedAfterSelection(Element element) {
    var visitor = _IsUsedAfterSelectionVisitor(this, element);
    _parentMember!.accept(visitor);
    return visitor.result;
  }

  /// Prepare names that are used in the enclosing function, so should not be
  /// proposed as names of the extracted method.
  void _prepareExcludedNames() {
    _excludedNames.clear();
    var localElements = getDefinedLocalElements(_parentMember!);
    _excludedNames.addAll(localElements.map((e) => e.name!));
  }

  void _prepareNames() {
    names.clear();
    var selectionExpression = _selectionExpression;
    if (selectionExpression != null) {
      names.addAll(
        getVariableNameSuggestionsForExpression(
          selectionExpression.typeOrThrow,
          selectionExpression,
          _excludedNames,
          isMethod: true,
        ),
      );
    }
  }

  void _prepareOffsetsLengths() {
    offsets.clear();
    lengths.clear();
    for (var occurrence in _occurrences) {
      offsets.add(occurrence.range.offset);
      lengths.add(occurrence.range.length);
    }
  }

  /// Returns whether [selection] covers [node] and there are any
  /// non-whitespace tokens between [selection] and [node]'s `offset` and `end`
  /// respectively.
  bool _selectionIncludesNonWhitespaceOutsideNode(
    SourceRange selection,
    AstNode node,
  ) {
    var sourceRange = range.node(node);

    // Selection should cover range.
    if (!selection.covers(sourceRange)) {
      return false;
    }
    // Non-whitespace between selection start and range start.
    if (!_isJustWhitespaceOrComment(
      range.startOffsetEndOffset(selection.offset, sourceRange.offset),
    )) {
      return true;
    }
    // Non-whitespace after range.
    if (!_isJustWhitespaceOrComment(
      range.startOffsetEndOffset(sourceRange.end, selection.end),
    )) {
      return true;
    }
    // Only whitespace in selection around range.
    return false;
  }

  /// Checks if the given [expression] is reasonable to extract as a getter.
  static bool _isExpressionForGetter(Expression? expression) {
    if (expression is BinaryExpression) {
      return _isExpressionForGetter(expression.leftOperand) &&
          _isExpressionForGetter(expression.rightOperand);
    }
    if (expression is Literal) {
      return true;
    }
    if (expression is PrefixExpression) {
      return _isExpressionForGetter(expression.operand);
    }
    if (expression is PrefixedIdentifier) {
      return _isExpressionForGetter(expression.prefix);
    }
    if (expression is PropertyAccess) {
      return _isExpressionForGetter(expression.target);
    }
    if (expression is SimpleIdentifier) {
      return true;
    }
    return false;
  }

  /// Returns `true` if the given [statement] may end with a [ReturnStatement].
  static bool _mayEndWithReturnStatement(Statement statement) {
    var visitor = _HasReturnStatementVisitor();
    statement.accept(visitor);
    return visitor.hasReturn;
  }
}

/// [SelectionAnalyzer] for [ExtractMethodRefactoringImpl].
class _ExtractMethodAnalyzer extends StatementAnalyzer {
  _ExtractMethodAnalyzer(super.resolveResult, super.selection);

  @override
  void handleNextSelectedNode(AstNode node) {
    super.handleNextSelectedNode(node);
    _checkParent(node);
  }

  @override
  void handleSelectionEndsIn(AstNode node) {
    super.handleSelectionEndsIn(node);
    invalidSelection(
      'The selection does not cover a set of statements or an expression. '
      'Extend selection to a valid range.',
    );
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    super.visitAssignmentExpression(node);
    var lhs = node.leftHandSide;
    if (_isFirstSelectedNode(lhs)) {
      invalidSelection(
        'Cannot extract the left-hand side of an assignment.',
        newLocation_fromNode(lhs),
      );
    }
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    super.visitCatchClauseParameter(node);
    if (_isFirstSelectedNode(node)) {
      invalidSelection('Cannot extract the name part of a declaration.');
    }
  }

  @override
  void visitConstructorInitializer(ConstructorInitializer node) {
    super.visitConstructorInitializer(node);
    if (_isFirstSelectedNode(node)) {
      invalidSelection(
        'Cannot extract a constructor initializer. '
        'Select expression part of initializer.',
        newLocation_fromNode(node),
      );
    }
  }

  @override
  void visitDirective(Directive node) {
    if (selection.intersects(SourceRange(node.offset, node.length))) {
      invalidSelection(
        'Cannot extract a directive.',
        newLocation_fromNode(node),
      );
      return;
    }

    super.visitDirective(node);
  }

  @override
  void visitFormalParameterList(FormalParameterList node) {
    super.visitFormalParameterList(node);
    if (_isFirstSelectedNode(node)) {
      invalidSelection(
        'Cannot extract a parameter list.',
        newLocation_fromNode(node),
      );
    }
  }

  @override
  void visitForParts(ForParts node) {
    node.visitChildren(this);
  }

  @override
  void visitForStatement(ForStatement node) {
    super.visitForStatement(node);
    var forLoopParts = node.forLoopParts;
    if (forLoopParts is ForParts) {
      if (forLoopParts is ForPartsWithDeclarations &&
          identical(forLoopParts.variables, firstSelectedNode)) {
        invalidSelection(
          "Cannot extract initialization part of a 'for' statement.",
        );
      } else if (forLoopParts.updaters.contains(lastSelectedNode)) {
        invalidSelection("Cannot extract increment part of a 'for' statement.");
      }
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    super.visitFunctionDeclaration(node);
    if (_isFirstSelectedNode(node)) {
      invalidSelection(
        'Cannot extract a function declaration.',
        newLocation_fromNode(node),
      );
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    super.visitFunctionExpression(node);
    // Disallow function expressions that are part of function declarations.
    if (_isFirstSelectedNode(node) && node.parent is FunctionDeclaration) {
      invalidSelection(
        'Cannot extract a function declaration.',
        newLocation_fromNode(node),
      );
    }
  }

  @override
  void visitGenericFunctionType(GenericFunctionType node) {
    super.visitGenericFunctionType(node);
    if (_isFirstSelectedNode(node)) {
      invalidSelection('Cannot extract a single type reference.');
    }
  }

  @override
  void visitImportPrefixReference(ImportPrefixReference node) {
    invalidSelection('Cannot extract an import prefix.');
  }

  @override
  void visitNamedType(NamedType node) {
    super.visitNamedType(node);
    if (_isFirstSelectedNode(node) ||
        node == coveringNode && selection.length != 0) {
      invalidSelection('Cannot extract a single type reference.');
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (_isFirstSelectedNode(node)) {
      // name of declaration
      if (node.inDeclarationContext()) {
        invalidSelection('Cannot extract the name part of a declaration.');
      }
      // method name
      var element = node.writeOrReadElement;
      if (element is LocalFunctionElement ||
          element is MethodElement ||
          element is TopLevelFunctionElement) {
        invalidSelection('Cannot extract a single method name.');
      }
      if (element is PrefixElement) {
        invalidSelection('Cannot extract an import prefix.');
      }
      var parent = node.parent;
      if (parent is PrefixedIdentifier) {
        if (parent.identifier == node) {
          // name in property access
          invalidSelection('Cannot extract name part of a property access.');
        }
      }
      // part of a named type (for example `int` in `int?`)
      if (node.parent is NamedType) {
        invalidSelection('Cannot extract a single type reference.');
      }
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    super.visitVariableDeclaration(node);
    if (_isFirstSelectedNode(node)) {
      invalidSelection(
        'Cannot extract a variable declaration fragment. '
        'Select whole declaration statement.',
        newLocation_fromNode(node),
      );
    }
  }

  void _checkParent(AstNode node) {
    var firstParent = firstSelectedNode!.parent;
    for (var parent in node.withAncestors) {
      if (identical(parent, firstParent)) {
        return;
      }
    }
    invalidSelection(
      'Not all selected statements are enclosed by the same parent statement.',
    );
  }

  bool _isFirstSelectedNode(AstNode node) => identical(firstSelectedNode, node);
}

class _GetSourcePatternVisitor extends GeneralizingAstVisitor<void> {
  final SourceRange partRange;
  final _SourcePattern pattern;
  final List<SourceEdit> replaceEdits;

  _GetSourcePatternVisitor(this.partRange, this.pattern, this.replaceEdits);

  @override
  void visitNamedExpression(NamedExpression node) {
    node.expression.accept(this);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _addPatterns(nameToken: node.token, element: node.element);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _addPatterns(nameToken: node.name, element: node.declaredFragment?.element);

    super.visitVariableDeclaration(node);
  }

  void _addPatterns({required Token nameToken, required Element? element}) {
    var nameRange = range.token(nameToken);
    if (partRange.covers(nameRange)) {
      if (element != null && isLocalElement(element)) {
        var originalName = element.displayName;
        var patternName = pattern.originalToPatternNames[originalName];
        if (patternName == null) {
          var parameterType = _getElementType(element);
          pattern.parameterTypes.add(parameterType);
          patternName = '__refVar${pattern.originalToPatternNames.length}';
          pattern.originalToPatternNames[originalName] = patternName;
        }
        replaceEdits.add(
          SourceEdit(
            nameRange.offset - partRange.offset,
            nameRange.length,
            patternName,
          ),
        );
      }
    }
  }

  DartType _getElementType(Element element) {
    if (element is VariableElement) {
      return element.type;
    }
    if (element is LocalFunctionElement) {
      return element.type;
    }
    throw StateError('Unknown element type: ${element.runtimeType}');
  }
}

class _HasAwaitVisitor extends GeneralizingAstVisitor<void> {
  bool result = false;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    result = true;
  }

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) {
      result = true;
    }
    super.visitForStatement(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Don't look inside function expressions as the presence of `await` inside
    // a function expression does not mean the overall function is async.
  }
}

class _HasReturnStatementVisitor extends RecursiveAstVisitor<void> {
  bool hasReturn = false;

  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {}

  @override
  void visitReturnStatement(ReturnStatement node) {
    hasReturn = true;
  }
}

class _ImportDirectiveInfo {
  final String uri;
  final int offset;
  final int end;

  _ImportDirectiveInfo(this.uri, this.offset, this.end);
}

class _InitializeOccurrencesVisitor extends GeneralizingAstVisitor<void> {
  final ExtractMethodRefactoringImpl ref;
  final _SourcePattern selectionPattern;
  final Map<String, String> patternToSelectionName;

  bool forceStatic = false;

  _InitializeOccurrencesVisitor(
    this.ref,
    this.selectionPattern,
    this.patternToSelectionName,
  );

  @override
  void visitBlock(Block node) {
    if (ref._selectionStatements != null) {
      _visitStatements(node.statements);
    }
    super.visitBlock(node);
  }

  @override
  void visitConstructorInitializer(ConstructorInitializer node) {
    forceStatic = true;
    try {
      super.visitConstructorInitializer(node);
    } finally {
      forceStatic = false;
    }
  }

  @override
  void visitExpression(Expression node) {
    if (ref._selectionFunctionExpression != null ||
        ref._selectionExpression != null &&
            node.runtimeType == ref._selectionExpression.runtimeType) {
      var nodeRange = range.node(node);
      _tryToFindOccurrence(nodeRange);
    }
    super.visitExpression(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    forceStatic = node.isStatic;
    try {
      super.visitFieldDeclaration(node);
    } finally {
      forceStatic = false;
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    forceStatic = node.isStatic;
    try {
      super.visitMethodDeclaration(node);
    } finally {
      forceStatic = false;
    }
  }

  @override
  void visitSwitchMember(SwitchMember node) {
    if (ref._selectionStatements != null) {
      _visitStatements(node.statements);
    }
    super.visitSwitchMember(node);
  }

  /// Checks if given [SourceRange] matched selection source and adds
  /// [_Occurrence].
  bool _tryToFindOccurrence(SourceRange nodeRange) {
    // check if can be extracted
    if (!ref._isExtractable(nodeRange)) {
      return false;
    }
    // prepare node source
    var nodePattern = ref._getSourcePattern(nodeRange);
    // if matches normalized node source, then add as occurrence
    if (selectionPattern.isCompatible(nodePattern)) {
      var occurrence = _Occurrence(
        nodeRange,
        ref._selectionRange.intersects(nodeRange),
      );
      ref._occurrences.add(occurrence);
      // prepare mapping of parameter names to the occurrence variables
      nodePattern.originalToPatternNames.forEach((
        String originalName,
        String patternName,
      ) {
        var selectionName = patternToSelectionName[patternName]!;
        occurrence._parameterOldToOccurrenceName[selectionName] = originalName;
      });
      // update static
      if (forceStatic) {
        ref._staticContext = true;
      }
      // we have match
      return true;
    }
    // no match
    return false;
  }

  void _visitStatements(List<Statement> statements) {
    var beginStatementIndex = 0;
    var selectionCount = ref._selectionStatements!.length;
    while (beginStatementIndex + selectionCount <= statements.length) {
      var nodeRange = range.startEnd(
        statements[beginStatementIndex],
        statements[beginStatementIndex + selectionCount - 1],
      );
      var found = _tryToFindOccurrence(nodeRange);
      // next statement
      if (found) {
        beginStatementIndex += selectionCount;
      } else {
        beginStatementIndex++;
      }
    }
  }
}

class _InitializeParametersVisitor extends GeneralizingAstVisitor<void> {
  final ExtractMethodRefactoringImpl ref;
  final List<VariableElement> assignedUsedVariables;

  _InitializeParametersVisitor(this.ref, this.assignedUsedVariables);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    var nodeRange = range.node(node);
    if (!ref._selectionRange.covers(nodeRange)) {
      return;
    }
    var name = node.name;
    // analyze local element
    var element = _getLocalElement(node);
    if (element != null) {
      // name of the named expression
      if (isNamedExpressionName(node)) {
        return;
      }
      // if declared outside, add parameter
      if (!ref._isDeclaredInSelection(element)) {
        // add parameter
        var parameter = ref._parametersMap[name];
        if (parameter == null) {
          var parameterType = node.writeOrReadType!;
          var parametersBuffer = StringBuffer();
          var parameterTypeCode = ref._resolveResult.libraryElement
              .getTypeSource(
                parameterType,
                ref._librariesToImport,
                parametersBuffer: parametersBuffer,
              );
          if (parameterTypeCode == null) {
            return;
          }
          var parametersCode =
              parametersBuffer.isNotEmpty ? parametersBuffer.toString() : null;
          parameter = RefactoringMethodParameter(
            RefactoringMethodParameterKind.REQUIRED,
            parameterTypeCode,
            name,
            parameters: parametersCode,
            id: name,
          );
          ref._parameters.add(parameter);
          ref._parametersMap[name] = parameter;
        }
        // add reference to parameter
        ref._addParameterReference(name, nodeRange);
      }
      // remember, if assigned and used after selection
      if (isLeftHandOfAssignment(node) && ref._isUsedAfterSelection(element)) {
        if (element is VariableElement &&
            !assignedUsedVariables.contains(element)) {
          assignedUsedVariables.add(element);
        }
      }
    }
    // remember information for conflicts checking
    if (element is LocalElement) {
      // declared local elements
      if (node.inDeclarationContext()) {
        var range = ref._visibleRangeMap[element];
        if (range != null) {
          var ranges = ref._localNames.putIfAbsent(name, () => <SourceRange>[]);
          ranges.add(range);
        }
      }
    } else {
      // unqualified non-local names
      if (!node.isQualified) {
        ref._unqualifiedNames.add(name);
      }
    }
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    var nodeRange = range.node(node);
    if (ref._selectionRange.covers(nodeRange)) {
      var element = node.declaredFragment!.element;

      // remember, if assigned and used after selection
      if (ref._isUsedAfterSelection(element)) {
        if (!assignedUsedVariables.contains(element)) {
          assignedUsedVariables.add(element);
        }
      }

      // remember information for conflicts checking
      if (element is LocalVariableElement) {
        // declared local elements
        var range = ref._visibleRangeMap[element];
        if (range != null) {
          var name = node.name.lexeme;
          var ranges = ref._localNames.putIfAbsent(name, () => <SourceRange>[]);
          ranges.add(range);
        }
      }
    }

    return super.visitVariableDeclaration(node);
  }
}

class _IsUsedAfterSelectionVisitor extends GeneralizingAstVisitor<void> {
  final ExtractMethodRefactoringImpl ref;
  final Element element;
  bool result = false;

  _IsUsedAfterSelectionVisitor(this.ref, this.element);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    var nodeElement = node.writeOrReadElement;
    if (identical(nodeElement, element)) {
      var nodeOffset = node.offset;
      if (nodeOffset > ref._selectionRange.end) {
        result = true;
      }
    }
  }
}

/// Description of a single occurrence of the selected expression or set of
/// statements.
class _Occurrence {
  final SourceRange range;
  final bool isSelection;

  final Map<String, String> _parameterOldToOccurrenceName = <String, String>{};

  _Occurrence(this.range, this.isSelection);
}

/// Generalized version of some source, in which references to the specific
/// variables are replaced with pattern variables, with back mapping from the
/// pattern to the original variable names.
class _SourcePattern {
  final List<DartType> parameterTypes = <DartType>[];
  late String normalizedSource;
  final Map<String, String> originalToPatternNames = {};

  bool isCompatible(_SourcePattern other) {
    if (other.normalizedSource != normalizedSource) {
      return false;
    }
    if (other.parameterTypes.length != parameterTypes.length) {
      return false;
    }
    for (var i = 0; i < parameterTypes.length; i++) {
      if (other.parameterTypes[i] != parameterTypes[i]) {
        return false;
      }
    }
    return true;
  }
}

extension on LibraryElement {
  /// Returns the source to reference [type] in this [CompilationUnit].
  ///
  /// Fills [librariesToImport] with library elements whose elements are
  /// used by the generated source, but not imported.
  String? getTypeSource(
    DartType type,
    Set<Source> librariesToImport, {
    StringBuffer? parametersBuffer,
  }) {
    var alias = type.alias;
    if (alias != null) {
      return _getTypeCodeElementArguments(
        librariesToImport: librariesToImport,
        element: alias.element,
        isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
        typeArguments: alias.typeArguments,
      );
    }

    if (type is DynamicType) {
      return 'dynamic';
    }

    if (type is FunctionType) {
      if (parametersBuffer == null) {
        return 'Function';
      }
      parametersBuffer.write('(');
      for (var parameter in type.formalParameters) {
        var parameterType = getTypeSource(parameter.type, librariesToImport);
        if (parametersBuffer.length != 1) {
          parametersBuffer.write(', ');
        }
        parametersBuffer.write(parameterType);
        var parameterName = parameter.name;
        if (parameterName != null && parameterName.isNotEmpty) {
          parametersBuffer.write(' ');
          parametersBuffer.write(parameterName);
        }
      }
      parametersBuffer.write(')');
      return getTypeSource(type.returnType, librariesToImport);
    }

    if (type is InterfaceType) {
      return _getTypeCodeElementArguments(
        librariesToImport: librariesToImport,
        element: type.element,
        isNullable: type.nullabilitySuffix == NullabilitySuffix.question,
        typeArguments: type.typeArguments,
      );
    }

    if (type is InvalidType) {
      return 'dynamic';
    }

    if (type is NeverType) {
      return 'Never';
    }

    if (type is RecordType) {
      return _getTypeCodeRecord(
        librariesToImport: librariesToImport,
        type: type,
      );
    }

    if (type is TypeParameterType) {
      // TODO(srawlins): Check whether the type parameter is visible. Return
      // `type.element.name` when it is.
      return 'dynamic';
    }

    if (type is VoidType) {
      return 'void';
    }

    throw UnimplementedError('(${type.runtimeType}) $type');
  }

  /// Returns the import element used to import given [element] into the
  /// library.
  ///
  /// Returns `null` if was not imported, i.e. declared in the same library.
  LibraryImport? _getImportElement(Element element) {
    for (var imp in firstFragment.libraryImports) {
      var definedNames = imp.namespace.definedNames2;
      if (definedNames.containsValue(element)) {
        return imp;
      }
    }
    return null;
  }

  String? _getTypeCodeElementArguments({
    required Set<Source> librariesToImport,
    required Element element,
    required bool isNullable,
    required List<DartType> typeArguments,
  }) {
    var sb = StringBuffer();

    // Check if imported.
    var library = element.library;
    if (library != null && library != this) {
      // No source, if private.
      if (element.isPrivate) {
        return null;
      }
      // Ensure import.
      var importElement = _getImportElement(element);
      if (importElement != null) {
        var prefix = importElement.prefix?.element;
        if (prefix != null) {
          sb.write(prefix.displayName);
          sb.write('.');
        }
      } else {
        librariesToImport.add(library.firstFragment.source);
      }
    }

    // Append simple name.
    var name = element.displayName;
    sb.write(name);

    // Append type arguments.
    if (typeArguments.isNotEmpty) {
      sb.write('<');
      for (var i = 0; i < typeArguments.length; i++) {
        var argument = typeArguments[i];
        if (i != 0) {
          sb.write(', ');
        }
        var argumentSrc = getTypeSource(argument, librariesToImport);
        if (argumentSrc != null) {
          sb.write(argumentSrc);
        } else {
          return null;
        }
      }
      sb.write('>');
    }

    // Append nullability.
    if (isNullable) {
      sb.write('?');
    }

    return sb.toString();
  }

  String _getTypeCodeRecord({
    required Set<Source> librariesToImport,
    required RecordType type,
  }) {
    var buffer = StringBuffer();

    var positionalFields = type.positionalFields;
    var namedFields = type.namedFields;
    var fieldCount = positionalFields.length + namedFields.length;
    buffer.write('(');

    var index = 0;
    for (var field in positionalFields) {
      buffer.write(getTypeSource(field.type, librariesToImport));
      if (index++ < fieldCount - 1) {
        buffer.write(', ');
      }
    }

    if (namedFields.isNotEmpty) {
      buffer.write('{');
      for (var field in namedFields) {
        buffer.write(getTypeSource(field.type, librariesToImport));
        buffer.write(' ');
        buffer.write(field.name);
        if (index++ < fieldCount - 1) {
          buffer.write(', ');
        }
      }
      buffer.write('}');
    }

    buffer.write(')');

    if (type.nullabilitySuffix == NullabilitySuffix.question) {
      buffer.write('?');
    }

    return buffer.toString();
  }
}
