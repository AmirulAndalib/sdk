// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart' as analyzer;
import 'package:analyzer/diagnostic/diagnostic.dart' as analyzer;
import 'package:analyzer/error/error.dart' as analyzer;
import 'package:analyzer/source/error_processor.dart' as analyzer;
import 'package:analyzer/source/line_info.dart' as analyzer;
import 'package:analyzer/src/dart/analysis/analysis_options.dart' as analyzer;
import 'package:analyzer/src/dart/element/element.dart' as analyzer;
import 'package:analyzer/src/diagnostic/diagnostic.dart' as analyzer;
import 'package:analyzer/src/error/codes.dart' as analyzer;
import 'package:analyzer_plugin/protocol/protocol_common.dart' as plugin;
import 'package:analyzer_plugin/utilities/analyzer_converter.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/abstract_single_unit.dart';

void main() {
  defineReflectiveTests(AnalyzerConverterTest);
}

@reflectiveTest
class AnalyzerConverterTest extends AbstractSingleUnitTest {
  AnalyzerConverter converter = AnalyzerConverter();

  /// Asserts that the given [pluginError] matches the given
  /// [analyzerDiagnostic].
  void assertError(
      plugin.AnalysisError pluginError, analyzer.Diagnostic analyzerDiagnostic,
      {analyzer.DiagnosticSeverity? severity,
      int startColumn = -1,
      int startLine = -1}) {
    var diagnosticCode = analyzerDiagnostic.diagnosticCode;
    expect(pluginError, isNotNull);
    var location = pluginError.location;
    expect(pluginError.code, diagnosticCode.name.toLowerCase());
    expect(pluginError.correction, diagnosticCode.correctionMessage);
    expect(location, isNotNull);
    expect(location.file, analyzerDiagnostic.source.fullName);
    expect(location.length, analyzerDiagnostic.length);
    expect(location.offset, analyzerDiagnostic.offset);
    expect(location.startColumn, startColumn);
    expect(location.startLine, startLine);
    expect(pluginError.message, diagnosticCode.problemMessage);
    expect(pluginError.severity,
        converter.convertErrorSeverity(severity ?? diagnosticCode.severity));
    expect(pluginError.type, converter.convertErrorType(diagnosticCode.type));
  }

  Future<analyzer.Diagnostic> createError(
    int offset, {
    String? contextMessage,
  }) async {
    var contextMessages = <analyzer.DiagnosticMessageImpl>[];

    await resolveTestCode('');
    var testSource = result.unit.declaredFragment!.source;

    if (contextMessage != null) {
      contextMessages.add(
        analyzer.DiagnosticMessageImpl(
          filePath: testSource.fullName,
          offset: 53,
          length: 7,
          message: contextMessage,
          url: null,
        ),
      );
    }
    return analyzer.Diagnostic.tmp(
      source: testSource,
      offset: offset,
      length: 5,
      diagnosticCode: analyzer.CompileTimeErrorCode.AWAIT_IN_WRONG_CONTEXT,
      contextMessages: contextMessages,
    );
  }

  Future<void> test_convertAnalysisError_contextMessages() async {
    var analyzerError = await createError(13, contextMessage: 'here');
    var lineInfo = analyzer.LineInfo([0, 10, 20]);
    var severity = analyzer.DiagnosticSeverity.WARNING;

    var pluginError = converter.convertAnalysisError(analyzerError,
        lineInfo: lineInfo, severity: severity);
    assertError(pluginError, analyzerError,
        startColumn: 4, startLine: 2, severity: severity);
    expect(pluginError.contextMessages, hasLength(1));
    var message = pluginError.contextMessages![0];
    expect(message.message, 'here');
    expect(message.location.offset, 53);
    expect(message.location.length, 7);
  }

  Future<void> test_convertAnalysisError_lineInfo_noSeverity() async {
    var analyzerError = await createError(13);
    var lineInfo = analyzer.LineInfo([0, 10, 20]);

    assertError(
        converter.convertAnalysisError(analyzerError, lineInfo: lineInfo),
        analyzerError,
        startColumn: 4,
        startLine: 2);
  }

  Future<void> test_convertAnalysisError_lineInfo_severity() async {
    var analyzerError = await createError(13);
    var lineInfo = analyzer.LineInfo([0, 10, 20]);
    var severity = analyzer.DiagnosticSeverity.WARNING;

    assertError(
        converter.convertAnalysisError(analyzerError,
            lineInfo: lineInfo, severity: severity),
        analyzerError,
        startColumn: 4,
        startLine: 2,
        severity: severity);
  }

  Future<void> test_convertAnalysisError_noLineInfo_noSeverity() async {
    var analyzerError = await createError(11);

    assertError(converter.convertAnalysisError(analyzerError), analyzerError);
  }

  Future<void> test_convertAnalysisError_noLineInfo_severity() async {
    var analyzerError = await createError(11);
    var severity = analyzer.DiagnosticSeverity.WARNING;

    assertError(
        converter.convertAnalysisError(analyzerError, severity: severity),
        analyzerError,
        severity: severity);
  }

  Future<void> test_convertAnalysisErrors_lineInfo_noOptions() async {
    var analyzerErrors = [
      await createError(13),
      await createError(25),
    ];
    var lineInfo = analyzer.LineInfo([0, 10, 20]);

    var pluginErrors = converter.convertAnalysisErrors(
      analyzerErrors,
      lineInfo: lineInfo,
      options: analyzer.AnalysisOptionsImpl(),
    );
    expect(pluginErrors, hasLength(analyzerErrors.length));
    assertError(pluginErrors[0], analyzerErrors[0],
        startColumn: 4, startLine: 2);
    assertError(pluginErrors[1], analyzerErrors[1],
        startColumn: 6, startLine: 3);
  }

  Future<void> test_convertAnalysisErrors_lineInfo_options() async {
    var analyzerErrors = [
      await createError(13),
      await createError(25),
    ];
    var lineInfo = analyzer.LineInfo([0, 10, 20]);
    var severity = analyzer.DiagnosticSeverity.WARNING;
    var options = (analyzer.AnalysisOptionsBuilder()
          ..errorProcessors.add(analyzer.ErrorProcessor(
              analyzerErrors[0].diagnosticCode.name, severity)))
        .build();

    var pluginErrors = converter.convertAnalysisErrors(analyzerErrors,
        lineInfo: lineInfo, options: options);
    expect(pluginErrors, hasLength(analyzerErrors.length));
    assertError(pluginErrors[0], analyzerErrors[0],
        startColumn: 4, startLine: 2, severity: severity);
    assertError(pluginErrors[1], analyzerErrors[1],
        startColumn: 6, startLine: 3, severity: severity);
  }

  Future<void> test_convertAnalysisErrors_noLineInfo_noOptions() async {
    var analyzerErrors = [
      await createError(11),
      await createError(25),
    ];

    var pluginErrors = converter.convertAnalysisErrors(
      analyzerErrors,
      options: analyzer.AnalysisOptionsImpl(),
    );
    expect(pluginErrors, hasLength(analyzerErrors.length));
    assertError(pluginErrors[0], analyzerErrors[0]);
    assertError(pluginErrors[1], analyzerErrors[1]);
  }

  Future<void> test_convertAnalysisErrors_noLineInfo_options() async {
    var analyzerErrors = [
      await createError(13),
      await createError(25),
    ];
    var severity = analyzer.DiagnosticSeverity.WARNING;
    var options = (analyzer.AnalysisOptionsBuilder()
          ..errorProcessors.add(analyzer.ErrorProcessor(
              analyzerErrors[0].diagnosticCode.name, severity)))
        .build();

    var pluginErrors =
        converter.convertAnalysisErrors(analyzerErrors, options: options);
    expect(pluginErrors, hasLength(analyzerErrors.length));
    assertError(pluginErrors[0], analyzerErrors[0], severity: severity);
    assertError(pluginErrors[1], analyzerErrors[1], severity: severity);
  }

  Future<void> test_convertElement_class() async {
    await resolveTestCode('''
@deprecated
abstract class _A {}
class B<K, V> {}''');
    {
      var engineElement = findElement2.class_('_A');
      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.CLASS);
      expect(element.name, '_A');
      expect(element.typeParameters, isNull);
      {
        var location = element.location!;
        expect(location.file, testFile);
        expect(location.offset, 27);
        expect(location.length, '_A'.length);
        expect(location.startLine, 2);
        expect(location.startColumn, 16);
      }
      expect(element.parameters, isNull);
      expect(
          element.flags,
          plugin.Element.FLAG_ABSTRACT |
              plugin.Element.FLAG_DEPRECATED |
              plugin.Element.FLAG_PRIVATE);
    }
    {
      var engineElement = findElement2.class_('B');
      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.CLASS);
      expect(element.name, 'B');
      expect(element.typeParameters, '<K, V>');
      expect(element.flags, 0);
    }
  }

  Future<void> test_convertElement_constructor() async {
    await resolveTestCode('''
class A {
  const A.myConstructor(int a, [String? b]);
}''');
    var engineElement = findElement2.constructor('myConstructor');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.CONSTRUCTOR);
    expect(element.name, 'A.myConstructor');
    expect(element.typeParameters, isNull);
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 20);
      expect(location.length, 'myConstructor'.length);
      expect(location.startLine, 2);
      expect(location.startColumn, 11);
    }
    expect(element.parameters, '(int a, [String? b])');
    expect(element.returnType, 'A');
    expect(element.flags, plugin.Element.FLAG_CONST);
  }

  void test_convertElement_dynamic() {
    var engineElement = analyzer.DynamicElementImpl.instance;
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.UNKNOWN);
    expect(element.name, 'dynamic');
    expect(element.location, isNull);
    expect(element.parameters, isNull);
    expect(element.returnType, isNull);
    expect(element.flags, 0);
  }

  Future<void> test_convertElement_enum() async {
    await resolveTestCode('''
@deprecated
enum _E1 { one, two }
enum E2 { three, four }''');
    {
      var engineElement = findElement2.enum_('_E1');
      expect(engineElement.metadata.hasDeprecated, isTrue);
      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.ENUM);
      expect(element.name, '_E1');
      expect(element.typeParameters, isNull);
      {
        var location = element.location!;
        expect(location.file, testFile);
        expect(location.offset, 17);
        expect(location.length, '_E1'.length);
        expect(location.startLine, 2);
        expect(location.startColumn, 6);
      }
      expect(element.parameters, isNull);
      expect(
          element.flags,
          (engineElement.metadata.hasDeprecated
                  ? plugin.Element.FLAG_DEPRECATED
                  : 0) |
              plugin.Element.FLAG_PRIVATE);
    }
    {
      var engineElement = findElement2.enum_('E2');
      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.ENUM);
      expect(element.name, 'E2');
      expect(element.typeParameters, isNull);
      expect(element.flags, 0);
    }
  }

  Future<void> test_convertElement_enumConstant() async {
    await resolveTestCode('''
@deprecated
enum _E1 { one, two }
enum E2 { three, four }''');
    {
      var engineElement = findElement2.field('one');
      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.ENUM_CONSTANT);
      expect(element.name, 'one');
      {
        var location = element.location!;
        expect(location.file, testFile);
        expect(location.offset, 23);
        expect(location.length, 'one'.length);
        expect(location.startLine, 2);
        expect(location.startColumn, 12);
      }
      expect(element.parameters, isNull);
      expect(element.returnType, '_E1');
      // TODO(danrubel): determine why enum constant is not marked as deprecated
      //analyzer.ClassElement classElement = engineElement.enclosingElement3;
      //expect(classElement.isDeprecated, isTrue);
      expect(
          element.flags,
          // Element.FLAG_DEPRECATED |
          plugin.Element.FLAG_CONST | plugin.Element.FLAG_STATIC);
    }
    {
      var engineElement = findElement2.field('three');
      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.ENUM_CONSTANT);
      expect(element.name, 'three');
      {
        var location = element.location!;
        expect(location.file, testFile);
        expect(location.offset, 44);
        expect(location.length, 'three'.length);
        expect(location.startLine, 3);
        expect(location.startColumn, 11);
      }
      expect(element.parameters, isNull);
      expect(element.returnType, 'E2');
      expect(element.flags,
          plugin.Element.FLAG_CONST | plugin.Element.FLAG_STATIC);
    }
    {
      var engineElement = findElement2.field('values', of: 'E2');

      // create notification Element
      var element = converter.convertElement(engineElement);
      expect(element.kind, plugin.ElementKind.FIELD);
      expect(element.name, 'values');
      {
        var location = element.location!;
        expect(location.file, testFile);
        expect(location.offset, -1);
        expect(location.length, 'values'.length);
        expect(location.startLine, 1);
        expect(location.startColumn, 0);
      }
      expect(element.parameters, isNull);
      expect(element.returnType, 'List<E2>');
      expect(element.flags,
          plugin.Element.FLAG_CONST | plugin.Element.FLAG_STATIC);
    }
  }

  Future<void> test_convertElement_field() async {
    await resolveTestCode('''
class A {
  static const myField = 42;
}''');
    var engineElement = findElement2.field('myField');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.FIELD);
    expect(element.name, 'myField');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 25);
      expect(location.length, 'myField'.length);
      expect(location.startLine, 2);
      expect(location.startColumn, 16);
    }
    expect(element.parameters, isNull);
    expect(element.returnType, 'int');
    expect(
        element.flags, plugin.Element.FLAG_CONST | plugin.Element.FLAG_STATIC);
  }

  Future<void> test_convertElement_functionTypeAlias() async {
    await resolveTestCode('''
typedef int F<T>(String x);
''');
    var engineElement = findElement2.typeAlias('F');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.TYPE_ALIAS);
    expect(element.name, 'F');
    expect(element.typeParameters, '<T>');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 12);
      expect(location.length, 'F'.length);
      expect(location.startLine, 1);
      expect(location.startColumn, 13);
    }
    expect(element.parameters, '(String x)');
    expect(element.returnType, 'int');
    expect(element.flags, 0);
  }

  Future<void> test_convertElement_getter() async {
    await resolveTestCode('''
class A {
  int get myGetter => 42;
}''');
    var engineElement = findElement2.getter('myGetter');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.GETTER);
    expect(element.name, 'myGetter');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 20);
      expect(location.length, 'myGetter'.length);
      expect(location.startLine, 2);
      expect(location.startColumn, 11);
    }
    expect(element.parameters, isNull);
    expect(element.returnType, 'int');
    expect(element.flags, 0);
  }

  Future<void> test_convertElement_LABEL() async {
    await resolveTestCode('''
main() {
myLabel:
  while (true) {
    break myLabel;
  }
}''');
    var engineElement = findElement2.label('myLabel');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.LABEL);
    expect(element.name, 'myLabel');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 9);
      expect(location.length, 'myLabel'.length);
      expect(location.startLine, 2);
      expect(location.startColumn, 1);
    }
    expect(element.parameters, isNull);
    expect(element.returnType, isNull);
    expect(element.flags, 0);
  }

  Future<void> test_convertElement_method() async {
    await resolveTestCode('''
class A {
  static List<String> myMethod(int a, {String? b, int? c}) {
    return [];
  }
}''');
    var engineElement = findElement2.method('myMethod');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.METHOD);
    expect(element.name, 'myMethod');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 32);
      expect(location.length, 'myGetter'.length);
      expect(location.startLine, 2);
      expect(location.startColumn, 23);
    }
    expect(element.parameters, '(int a, {String? b, int? c})');
    expect(element.returnType, 'List<String>');
    expect(element.flags, plugin.Element.FLAG_STATIC);
  }

  Future<void> test_convertElement_setter() async {
    await resolveTestCode('''
class A {
  set mySetter(String x) {}
}''');
    var engineElement = findElement2.setter('mySetter');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.SETTER);
    expect(element.name, 'mySetter');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 16);
      expect(location.length, 'mySetter'.length);
      expect(location.startLine, 2);
      expect(location.startColumn, 7);
    }
    expect(element.parameters, '(String x)');
    expect(element.returnType, isNull);
    expect(element.flags, 0);
  }

  Future<void> test_convertElement_typeAlias_functionType() async {
    await resolveTestCode('''
typedef F<T> = int Function(String x);
''');
    var engineElement = findElement2.typeAlias('F');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.TYPE_ALIAS);
    expect(element.name, 'F');
    expect(element.typeParameters, '<T>');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 8);
      expect(location.length, 'F'.length);
      expect(location.startLine, 1);
      expect(location.startColumn, 9);
    }
    expect(element.parameters, '(String x)');
    expect(element.returnType, 'int');
    expect(element.flags, 0);
  }

  Future<void> test_convertElement_typeAlias_interfaceType() async {
    await resolveTestCode('''
typedef A<T> = Map<int, T>;
''');
    var engineElement = findElement2.typeAlias('A');
    // create notification Element
    var element = converter.convertElement(engineElement);
    expect(element.kind, plugin.ElementKind.TYPE_ALIAS);
    expect(element.name, 'A');
    expect(element.typeParameters, '<out T>');
    {
      var location = element.location!;
      expect(location.file, testFile);
      expect(location.offset, 8);
      expect(location.length, 'A'.length);
      expect(location.startLine, 1);
      expect(location.startColumn, 9);
    }
    expect(element.aliasedType, 'Map<int, T>');
    expect(element.parameters, isNull);
    expect(element.returnType, isNull);
    expect(element.flags, 0);
  }

  void test_convertElementKind() {
    expect(converter.convertElementKind(analyzer.ElementKind.CLASS),
        plugin.ElementKind.CLASS);
    expect(converter.convertElementKind(analyzer.ElementKind.COMPILATION_UNIT),
        plugin.ElementKind.COMPILATION_UNIT);
    expect(converter.convertElementKind(analyzer.ElementKind.CONSTRUCTOR),
        plugin.ElementKind.CONSTRUCTOR);
    expect(converter.convertElementKind(analyzer.ElementKind.FIELD),
        plugin.ElementKind.FIELD);
    expect(converter.convertElementKind(analyzer.ElementKind.FUNCTION),
        plugin.ElementKind.FUNCTION);
    expect(
        converter.convertElementKind(analyzer.ElementKind.FUNCTION_TYPE_ALIAS),
        plugin.ElementKind.FUNCTION_TYPE_ALIAS);
    expect(converter.convertElementKind(analyzer.ElementKind.GETTER),
        plugin.ElementKind.GETTER);
    expect(converter.convertElementKind(analyzer.ElementKind.LABEL),
        plugin.ElementKind.LABEL);
    expect(converter.convertElementKind(analyzer.ElementKind.LIBRARY),
        plugin.ElementKind.LIBRARY);
    expect(converter.convertElementKind(analyzer.ElementKind.LOCAL_VARIABLE),
        plugin.ElementKind.LOCAL_VARIABLE);
    expect(converter.convertElementKind(analyzer.ElementKind.METHOD),
        plugin.ElementKind.METHOD);
    expect(converter.convertElementKind(analyzer.ElementKind.PARAMETER),
        plugin.ElementKind.PARAMETER);
    expect(converter.convertElementKind(analyzer.ElementKind.SETTER),
        plugin.ElementKind.SETTER);
    expect(
        converter.convertElementKind(analyzer.ElementKind.TOP_LEVEL_VARIABLE),
        plugin.ElementKind.TOP_LEVEL_VARIABLE);
    expect(converter.convertElementKind(analyzer.ElementKind.TYPE_ALIAS),
        plugin.ElementKind.TYPE_ALIAS);
    expect(converter.convertElementKind(analyzer.ElementKind.TYPE_PARAMETER),
        plugin.ElementKind.TYPE_PARAMETER);
  }

  void test_convertErrorSeverity() {
    for (var severity in analyzer.DiagnosticSeverity.values) {
      if (severity != analyzer.DiagnosticSeverity.NONE) {
        expect(converter.convertErrorSeverity(severity), isNotNull,
            reason: severity.name);
      }
    }
  }

  void test_convertErrorType() {
    for (var type in analyzer.DiagnosticType.values) {
      expect(converter.convertErrorType(type), isNotNull, reason: type.name);
    }
  }
}
