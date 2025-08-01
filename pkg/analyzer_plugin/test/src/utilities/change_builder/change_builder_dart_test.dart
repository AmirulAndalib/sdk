// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/src/test_utilities/find_node.dart';
import 'package:analyzer/utilities/package_config_file_builder.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart' hide Element;
import 'package:analyzer_plugin/src/utilities/change_builder/change_builder_dart.dart'
    show DartFileEditBuilderImpl, DartLinkedEditBuilderImpl;
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../support/abstract_context.dart';
import 'dart/dart_change_builder_mixin.dart';
import 'mocks.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DartEditBuilderImpl);
    defineReflectiveTests(DartFileEditBuilderImplTest);
    defineReflectiveTests(DartLinkedEditBuilderImplTest);
    defineReflectiveTests(ImportLibraryTest);
    defineReflectiveTests(ImportLibraryElementTest);
    defineReflectiveTests(WriteOverrideTest);
  });
}

@reflectiveTest
class DartEditBuilderImpl extends DartEditBuilderImplTest {
  Future<void> test_sourceEditDescriptions_delete() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');

    var builder = await newBuilder();
    builder.currentChangeDescription = 'Change Desc';
    await builder.addDartFileEdit(path, (builder) {
      builder.addDeletion(SourceRange(0, 1));
    });

    expect(builder.sourceChange.edits[0].edits[0].description, 'Change Desc');
  }

  Future<void> test_sourceEditDescriptions_insert() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');

    var builder = await newBuilder();
    builder.currentChangeDescription = 'Change Desc';
    await builder.addDartFileEdit(path, (builder) {
      builder.addSimpleInsertion(0, '_');
      builder.addInsertion(0, (builder) => builder.write('_'));
    });

    expect(builder.sourceChange.edits[0].edits[0].description, 'Change Desc');
    expect(builder.sourceChange.edits[0].edits[1].description, 'Change Desc');
  }

  Future<void> test_sourceEditDescriptions_replace() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');

    var builder = await newBuilder();
    builder.currentChangeDescription = 'Change Desc';
    await builder.addDartFileEdit(path, (builder) {
      builder.addSimpleReplacement(SourceRange(0, 1), '_');
      builder.addReplacement(
        SourceRange(10, 1),
        (builder) => builder.write('_'),
      );
    });

    expect(builder.sourceChange.edits[0].edits[0].description, 'Change Desc');
    expect(builder.sourceChange.edits[0].edits[1].description, 'Change Desc');
  }

  Future<void> test_writeParameter_covariantAndRequired() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a', isCovariant: true, isRequiredNamed: true);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(
        edits[0].replacement, equalsIgnoringWhitespace('covariant required a'));
  }

  Future<void> test_writeParameter_required_addImport() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a', isRequiredNamed: true);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement, equalsIgnoringWhitespace('required a'));
  }

  Future<void> test_writeParameter_required_existingImport() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');
    var content = '''
import 'package:meta/meta.dart';

class A {}
''';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a', isRequiredNamed: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('required a'));
  }

  Future<void> test_writeParameter_required_keyword() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a', isRequiredNamed: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('required a'));
  }

  Future<void> test_writeType_function_nullable() async {
    await _assertwriteType2('int Function(double a, String b)?');
  }

  Future<void> test_writeType_Never_none() async {
    await _assertwriteType2('Never');
  }

  Future<void> test_writeType_Never_question() async {
    await _assertwriteType2('Never?');
  }

  Future<void> test_writeType_recordType_mixed() async {
    await _assertwriteType2('(int, {int y})');
  }

  Future<void> test_writeType_recordType_named() async {
    await _assertwriteType2('({int x, int y})');
  }

  Future<void> test_writeType_recordType_nullable() async {
    await _assertwriteType2('(int, {int y})?');
  }

  Future<void> test_writeType_recordType_positional() async {
    await _assertwriteType2('(int, int)');
  }
}

class DartEditBuilderImplTest extends AbstractContextTest
    with DartChangeBuilderMixin {
  @override
  void setUp() {
    super.setUp();
    writeTestPackageConfig(
      config: PackageConfigFileBuilder(),
      meta: true,
    );
  }

  Future<void> test_writeClassDeclaration_interfaces() async {
    var path = convertPath('$testPackageRootPath/lib/test.dart');
    addSource(path, 'class A {}');
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C', interfaces: [typeA]);
      });
    });
    var edit = getEdit(builder);
    expect(
        edit.replacement, equalsIgnoringWhitespace('class C implements A { }'));
  }

  Future<void> test_writeClassDeclaration_isAbstract() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C', isAbstract: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('abstract class C { }'));
  }

  Future<void> test_writeClassDeclaration_memberWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C', membersWriter: () {
          builder.write('/**/');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('class C { /**/}'));
  }

  Future<void> test_writeClassDeclaration_mixins_noSuperclass() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class A {}');
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C', mixins: [typeA]);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('class C with A { }'));
  }

  Future<void> test_writeClassDeclaration_mixins_superclass() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class A {} class B {}');
    DartType typeA = await _getType(path, 'A');
    DartType typeB = await _getType(path, 'B');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C', mixins: [typeB], superclass: typeA);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement,
        equalsIgnoringWhitespace('class C extends A with B { }'));
  }

  Future<void> test_writeClassDeclaration_nameGroupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('class C { }'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
  }

  Future<void> test_writeClassDeclaration_superclass() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class B {}');
    DartType typeB = await _getType(path, 'B');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeClassDeclaration('C',
            superclass: typeB, superclassGroupName: 'superclass');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('class C extends B { }'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
  }

  Future<void> test_writeConstructorDeclaration_bodyWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class C {}');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(9, (builder) {
        builder.writeConstructorDeclaration('A', bodyWriter: () {
          builder.write(' { print(42); }');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A() { print(42); }'));
  }

  Future<void> test_writeConstructorDeclaration_fieldNames() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, r'''
class C {
  final int a;
  final bool bb;
}
''');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(42, (builder) {
        builder.writeConstructorDeclaration('A', fieldNames: ['a', 'bb']);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A(this.a, this.bb);'));
  }

  Future<void> test_writeConstructorDeclaration_initializerWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class C {}');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(9, (builder) {
        builder.writeConstructorDeclaration('A', initializerWriter: () {
          builder.write('super()');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A() : super();'));
  }

  Future<void> test_writeConstructorDeclaration_parameterWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class C {}');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(9, (builder) {
        builder.writeConstructorDeclaration('A', parameterWriter: () {
          builder.write('int a, {this.b}');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A(int a, {this.b});'));
  }

  Future<void> test_writeFieldDeclaration_initializerWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', initializerWriter: () {
          builder.write('e');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('var f = e;'));
  }

  Future<void> test_writeFieldDeclaration_isConst() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', isConst: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('const f;'));
  }

  Future<void> test_writeFieldDeclaration_isConst_isFinal() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', isConst: true, isFinal: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('const f;'));
  }

  Future<void> test_writeFieldDeclaration_isConst_type() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', isConst: true, type: typeA);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('const A f;'));
  }

  Future<void> test_writeFieldDeclaration_isFinal() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', isFinal: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('final f;'));
  }

  Future<void> test_writeFieldDeclaration_isFinal_type() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', isFinal: true, type: typeA);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('final A f;'));
  }

  Future<void> test_writeFieldDeclaration_isStatic() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', isStatic: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('static var f;'));
  }

  Future<void> test_writeFieldDeclaration_nameGroupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('var f;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
    var position = group.positions[0];
    expect(position.offset, equals(13));
  }

  Future<void> test_writeFieldDeclaration_type_typeGroupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFieldDeclaration('f', type: typeA, typeGroupName: 'type');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A f;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
    var position = group.positions[0];
    expect(position.offset, equals(20));
  }

  Future<void>
      test_writeFunctionDeclaration_noReturnType_noParams_body() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeFunctionDeclaration('fib', bodyWriter: () {
          builder.write('{ ... }');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('fib() { ... }'));
  }

  Future<void>
      test_writeFunctionDeclaration_noReturnType_noParams_noBody() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeFunctionDeclaration('fib', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('fib() {}'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 3);
    expect(group.positions, hasLength(1));
  }

  Future<void>
      test_writeFunctionDeclaration_noReturnType_params_noBody() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeFunctionDeclaration('fib', parameterWriter: () {
          builder.write('p, q, r');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('fib(p, q, r) {}'));
  }

  Future<void>
      test_writeFunctionDeclaration_returnType_noParams_noBody() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeFunctionDeclaration('fib',
            returnType: typeA, returnTypeGroupName: 'type');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A fib() => null;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
  }

  Future<void> test_writeGetterDeclaration_bodyWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeGetterDeclaration('g', bodyWriter: () {
          builder.write('{}');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('get g {}'));
  }

  Future<void> test_writeGetterDeclaration_isStatic() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeGetterDeclaration('g', isStatic: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('static get g => null;'));
  }

  Future<void> test_writeGetterDeclaration_nameGroupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeGetterDeclaration('g', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('get g => null;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
    var position = group.positions[0];
    expect(position.offset, equals(13));
  }

  Future<void> test_writeGetterDeclaration_returnType() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeGetterDeclaration('g',
            returnType: typeA, returnTypeGroupName: 'returnType');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A get g => null;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
    var position = group.positions[0];
    expect(position.offset, equals(20));
  }

  Future<void> test_writeImportedName_hasImport_first() async {
    // addSource(convertPath('/home/test/lib/foo.dart'), '');
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '''
import 'foo.dart';
''');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeImportedName([
          Uri.parse('package:test/foo.dart'),
          Uri.parse('package:test/bar.dart')
        ], 'Foo');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('Foo'));
  }

  Future<void> test_writeImportedName_hasImport_second() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '''
import 'bar.dart';
''');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeImportedName([
          Uri.parse('package:test/foo.dart'),
          Uri.parse('package:test/bar.dart')
        ], 'Foo');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('Foo'));
  }

  Future<void> test_writeImportedName_needsImport_insertion() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeImportedName([
          Uri.parse('package:test/foo.dart'),
          Uri.parse('package:test/bar.dart')
        ], 'Foo');
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    expect(edits[0].replacement, equalsIgnoringWhitespace('Foo'));
    expect(edits[1].replacement,
        equalsIgnoringWhitespace("import 'package:test/foo.dart';\n"));
    var result = SourceEdit.applySequence(content, edits);
    expect(result, '''
import 'package:test/foo.dart';

Foo''');
  }

  Future<void> test_writeImportedName_needsImport_replacement() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'test';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addReplacement(SourceRange(0, 4), (builder) {
        builder.writeImportedName([
          Uri.parse('package:test/foo.dart'),
          Uri.parse('package:test/bar.dart')
        ], 'Foo');
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    expect(edits[0].replacement, equalsIgnoringWhitespace('Foo'));
    expect(edits[1].replacement,
        equalsIgnoringWhitespace("import 'package:test/foo.dart';\n"));
    var result = SourceEdit.applySequence(content, edits);
    expect(result, '''
import 'package:test/foo.dart';

Foo''');
  }

  Future<void> test_writeLocalVariableDeclaration_noType_initializer() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}''';
    addSource(path, content);
    await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration('foo', initializerWriter: () {
          builder.write('null');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('var foo = null;'));
  }

  Future<void> test_writeLocalVariableDeclaration_noType_noInitializer() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}''';
    addSource(path, content);
    await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration('foo', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('var foo;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 3);
    expect(group.positions, hasLength(1));
  }

  Future<void>
      test_writeLocalVariableDeclaration_noType_noInitializer_const() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}''';
    addSource(path, content);
    await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration('foo', isConst: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('const foo;'));
  }

  Future<void>
      test_writeLocalVariableDeclaration_noType_noInitializer_final() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}''';
    addSource(path, content);
    await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration('foo', isFinal: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('final foo;'));
  }

  Future<void> test_writeLocalVariableDeclaration_type_initializer() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}
class MyClass {}''';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;

    var A = unit.declarations[1] as ClassDeclaration;

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration(
          'foo',
          initializerWriter: () {
            builder.write('null');
          },
          type: A.declaredFragment!.element.instantiate(
            typeArguments: [],
            nullabilitySuffix: NullabilitySuffix.none,
          ),
        );
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('MyClass foo = null;'));
  }

  Future<void> test_writeLocalVariableDeclaration_type_noInitializer() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}
class MyClass {}''';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;

    var A = unit.declarations[1] as ClassDeclaration;

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration(
          'foo',
          type: A.declaredFragment!.element.instantiate(
            typeArguments: [],
            nullabilitySuffix: NullabilitySuffix.none,
          ),
          typeGroupName: 'type',
        );
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('MyClass foo;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 7);
    expect(group.positions, hasLength(1));
  }

  Future<void>
      test_writeLocalVariableDeclaration_type_noInitializer_final() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
void f() {

}
class MyClass {}''';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;

    var A = unit.declarations[1] as ClassDeclaration;

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(11, (builder) {
        builder.writeLocalVariableDeclaration(
          'foo',
          isFinal: true,
          type: A.declaredFragment!.element.instantiate(
            typeArguments: [],
            nullabilitySuffix: NullabilitySuffix.none,
          ),
          typeGroupName: 'type',
        );
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('final MyClass foo;'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 7);
    expect(group.positions, hasLength(1));
  }

  Future<void> test_writeMixinDeclaration_interfaces() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class A {}');
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeMixinDeclaration('M', interfaces: [typeA]);
      });
    });
    var edit = getEdit(builder);
    expect(
        edit.replacement, equalsIgnoringWhitespace('mixin M implements A { }'));
  }

  Future<void>
      test_writeMixinDeclaration_interfacesAndSuperclassConstraints() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class A {} class B {}');
    DartType typeA = await _getType(path, 'A');
    DartType typeB = await _getType(path, 'B');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeMixinDeclaration('M',
            interfaces: [typeA], superclassConstraints: [typeB]);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement,
        equalsIgnoringWhitespace('mixin M on B implements A { }'));
  }

  Future<void> test_writeMixinDeclaration_memberWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeMixinDeclaration('M', membersWriter: () {
          builder.write('/**/');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('mixin M { /**/}'));
  }

  Future<void> test_writeMixinDeclaration_nameGroupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeMixinDeclaration('M', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('mixin M { }'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
  }

  Future<void> test_writeMixinDeclaration_superclassConstraints() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'class A {}');
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeMixinDeclaration('M', superclassConstraints: [typeA]);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('mixin M on A { }'));
  }

  Future<void> test_writeParameter() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('a'));
  }

  Future<void> test_writeParameter_covariant() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a', isCovariant: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('covariant a'));
  }

  Future<void> test_writeParameter_type() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParameter('a', type: typeA);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A a'));
  }

  Future<void> test_writeParameterMatchingArgument() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = r'''
f() {}
g() {
  f(new A());
}
class A {}
''';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;
    var g = unit.declarations[1] as FunctionDeclaration;
    var body = g.functionExpression.body as BlockFunctionBody;
    var statement = body.block.statements[0] as ExpressionStatement;
    var invocation = statement.expression as MethodInvocation;
    var argument = invocation.argumentList.arguments[0];

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(2, (builder) {
        builder.writeParameterMatchingArgument(argument, 0, <String>{});
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A a'));
  }

  Future<void> test_writeParameters_named() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'f(int a, {bool b = false, String c}) {}';
    addSource(path, content);

    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var parameters = f.functionExpression.parameters;
    var elements =
        parameters?.parameters.map((p) => p.declaredFragment!.element);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFormalParameters(elements!);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement,
        equalsIgnoringWhitespace('(int a, {bool b = false, String c})'));
  }

  Future<void> test_writeParameters_noDefaults() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'f(int a, {bool b = false, String c = ""}) {}';
    addSource(path, content);

    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var parameters = f.functionExpression.parameters;
    var elements =
        parameters?.parameters.map((p) => p.declaredFragment!.element);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFormalParameters(elements!, includeDefaultValues: false);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement,
        equalsIgnoringWhitespace('(int a, {bool b, String c})'));
  }

  Future<void> test_writeParameters_positional() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'f(int a, [bool b = false, String c]) {}';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var parameters = f.functionExpression.parameters;
    var elements =
        parameters?.parameters.map((p) => p.declaredFragment!.element);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFormalParameters(elements!);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement,
        equalsIgnoringWhitespace('(int a, [bool b = false, String c])'));
  }

  Future<void> test_writeParameters_required() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'f(int i, String s) {}';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var parameters = f.functionExpression.parameters;
    var elements =
        parameters?.parameters.map((p) => p.declaredFragment!.element);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFormalParameters(elements!);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('(int i, String s)'));
  }

  Future<void> test_writeParameters_requiredTypes() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'void f(e) {}';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var parameters = f.functionExpression.parameters;
    var elements =
        parameters?.parameters.map((p) => p.declaredFragment!.element);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeFormalParameters(elements!, requiredTypes: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equals('(dynamic e)'));
  }

  Future<void> test_writeParametersMatchingArguments_named() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
f(int i, String s) {
  g(s, index: i);
}''';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var body = f.functionExpression.body as BlockFunctionBody;
    var statement = body.block.statements[0] as ExpressionStatement;
    var invocation = statement.expression as MethodInvocation;

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParametersMatchingArguments(invocation.argumentList);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement,
        equalsIgnoringWhitespace('String s, {required int index}'));
  }

  Future<void> test_writeParametersMatchingArguments_required() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '''
f(int i, String s) {
  g(s, i);
}''';
    addSource(path, content);
    var unit = (await resolveFile(path)).unit;
    var f = unit.declarations[0] as FunctionDeclaration;
    var body = f.functionExpression.body as BlockFunctionBody;
    var statement = body.block.statements[0] as ExpressionStatement;
    var invocation = statement.expression as MethodInvocation;

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeParametersMatchingArguments(invocation.argumentList);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('String s, int i'));
  }

  Future<void> test_writeReference_method() async {
    var aPath = convertPath('$testPackageRootPath/a.dart');
    addSource(aPath, r'''
class A {
  void foo() {}
}
''');

    var path = convertPath('$testPackageRootPath/lib/test.dart');
    var content = r'''
import 'a.dart';
''';
    addSource(path, content);

    var aElement = await _getClassElement(aPath, 'A');
    var fooElement = aElement.methods[0];

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeReference(fooElement);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('foo'));
  }

  Future<void> test_writeReference_topLevel_hasImport_noPrefix() async {
    var aPath = convertPath('$testPackageRootPath/lib/a.dart');
    addSource(aPath, 'const a = 42;');

    var path = convertPath('$testPackageRootPath/lib/test.dart');
    var content = r'''
import 'a.dart';
''';
    addSource(path, content);

    var aElement = await _getTopLevelGetter(aPath, 'a');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeReference(aElement);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('a'));
  }

  Future<void> test_writeReference_topLevel_hasImport_prefix() async {
    var aPath = convertPath('/home/test/lib/a.dart');
    addSource(aPath, 'const a = 42;');

    var path = convertPath('/home/test/lib/test.dart');
    var content = r'''
import 'a.dart' as p;
''';
    addSource(path, content);

    var aElement = await _getTopLevelGetter(aPath, 'a');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeReference(aElement);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('p.a'));
  }

  Future<void> test_writeReference_topLevel_noImport() async {
    var aPath = convertPath('/home/test/bin/a.dart');
    addSource(aPath, 'const a = 42;');

    var path = convertPath('/home/test/bin/test.dart');
    var content = '';
    addSource(path, content);

    var aElement = await _getTopLevelGetter(aPath, 'a');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(0, (builder) {
        builder.writeReference(aElement);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    expect(edits[0].replacement, equalsIgnoringWhitespace('a'));
    expect(edits[1].replacement, equalsIgnoringWhitespace("import 'a.dart';"));
    var result = SourceEdit.applySequence(content, edits);
    expect(result, '''
import 'a.dart';

a''');
  }

  Future<void> test_writeSetterDeclaration_bodyWriter() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeSetterDeclaration('s', bodyWriter: () {
          builder.write('{/* TODO */}');
        });
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('set s(s) {/* TODO */}'));
  }

  Future<void> test_writeSetterDeclaration_isStatic() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeSetterDeclaration('s', isStatic: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('static set s(s) {}'));
  }

  Future<void> test_writeSetterDeclaration_nameGroupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeSetterDeclaration('s', nameGroupName: 'name');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('set s(s) {}'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
    var position = group.positions[0];
    expect(position.offset, equals(13));
  }

  Future<void> test_writeSetterDeclaration_parameterType() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeSetterDeclaration('s',
            parameterType: typeA, parameterTypeGroupName: 'returnType');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('set s(A s) {}'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group.length, 1);
    expect(group.positions, hasLength(1));
    var position = group.positions[0];
    expect(position.offset, equals(26));
  }

  Future<void> test_writeType_dynamic() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    var unitResult = await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        var typeProvider = unitResult.libraryElement.typeProvider;
        builder.writeType(typeProvider.dynamicType);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace(''));
  }

  Future<void> test_writeType_function() async {
    await _assertwriteType2('int Function(double a, String b)');
  }

  Future<void> test_writeType_function_generic() async {
    await _assertwriteType2('T Function<T, U>(T a, U b)');
  }

  Future<void> test_writeType_function_noReturnType() async {
    await _assertwriteType2('Function()');
  }

  Future<void> test_writeType_function_parameters_named() async {
    await _assertwriteType2('int Function(int a, {int b, int c})');
  }

  Future<void> test_writeType_function_parameters_noName() async {
    await _assertwriteType2('int Function(double p1, String p2)');
  }

  Future<void> test_writeType_function_parameters_positional() async {
    await _assertwriteType2('int Function(int a, [int b, int c])');
  }

  Future<void> test_writeType_genericType() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B<E> {}';
    addSource(path, content);
    var typeA = await _getType(path, 'A');
    var typeBofA = await _getType(path, 'B', typeArguments: [typeA]);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(typeBofA);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('B<A>'));
  }

  Future<void> test_writeType_groupName() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B extends A {} class C extends B {}';
    addSource(path, content);
    DartType typeC = await _getType(path, 'C');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(typeC, groupName: 'type');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('C'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    expect(group, isNotNull);
  }

  Future<void> test_writeType_groupName_addSupertypeProposals() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B extends A {} class C extends B {}';
    addSource(path, content);
    DartType typeC = await _getType(path, 'C');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(typeC,
            addSupertypeProposals: true, groupName: 'type');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('C'));

    var linkedEditGroups = builder.sourceChange.linkedEditGroups;
    expect(linkedEditGroups, hasLength(1));
    var group = linkedEditGroups[0];
    var suggestions = group.suggestions;
    expect(suggestions, hasLength(4));
    var values = suggestions.map((LinkedEditSuggestion suggestion) {
      expect(suggestion.kind, LinkedEditSuggestionKind.TYPE);
      return suggestion.value;
    });
    expect(values, contains('Object'));
    expect(values, contains('A'));
    expect(values, contains('B'));
    expect(values, contains('C'));
  }

  Future<void> test_writeType_groupName_invalidType() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A<T> {}';
    addSource(path, content);

    var classA = await _getClassElement(path, 'A');
    DartType typeT = classA.typeParameters.single.instantiate(
      nullabilitySuffix: NullabilitySuffix.none,
    );

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length, (builder) {
        // "T" cannot be written, because we are outside of "A".
        // So, we also should not create linked groups.
        builder.writeType(typeT, groupName: 'type');
      });
    });
    expect(builder.sourceChange.linkedEditGroups, isEmpty);
  }

  Future<void> test_writeType_interface_typeArguments() async {
    await _assertwriteType2('Map<int, List<String>>');
  }

  Future<void> test_writeType_interface_typeArguments_allDynamic() async {
    await _assertwriteType2('Map');
  }

  Future<void> test_writeType_null() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(null);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace(''));
  }

  Future<void> test_writeType_preserveHiddenTypesA() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class B {} class C {} class D {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' hide C, B, A;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    var typeD = await _getType(aPath, 'D');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeD);
        builder.write('();');
        builder.writeType(typeA);
        builder.write('();');
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' hide C, B;D();A();"));
  }

  Future<void> test_writeType_preserveHiddenTypesB() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class B {} class C {} class D {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' hide C, B, A;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeB = await _getType(aPath, 'B');
    var typeD = await _getType(aPath, 'D');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeD);
        builder.write('();');
        builder.writeType(typeB);
        builder.write('();');
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' hide C, A;D();B();"));
  }

  Future<void> test_writeType_preserveHiddenTypesC() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class B {} class C {} class D {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' hide C, B, A;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeC = await _getType(aPath, 'C');
    var typeD = await _getType(aPath, 'D');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeD);
        builder.write('();');
        builder.writeType(typeC);
        builder.write('();');
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' hide B, A;D();C();"));
  }

  Future<void> test_writeType_required_dynamic() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    var unitResult = await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        var typeProvider = unitResult.libraryElement.typeProvider;
        builder.writeType(typeProvider.dynamicType, required: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('var'));
  }

  Future<void> test_writeType_required_notNull() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(typeA, required: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A'));
  }

  Future<void> test_writeType_required_null() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(null, required: true);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('var'));
  }

  Future<void> test_writeType_shownImport() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' show Other;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show A, Other;A"));
  }

  /// The same test as [test_writeType_shownImport] but where the updated
  /// import is not the last import. This verifies the code that updates imports
  /// correctly breaks after updating the import so it does not also import a
  /// duplicate.
  Future<void> test_writeType_shownImport_nonLast() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = '''
import 'package:test/test_a.dart' show Other;
import 'package:test/test_b.dart';
''';
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(edited, equalsIgnoringWhitespace('''
import 'package:test/test_a.dart' show A, Other;
import 'package:test/test_b.dart';
A'''));
  }

  Future<void> test_writeType_shownImportUnsorted() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class B {} class C {} class D {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' show C, A;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeB = await _getType(aPath, 'B');
    var typeD = await _getType(aPath, 'D');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeD);
        builder.write('();');
        builder.writeType(typeB);
        builder.write('();');
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show C, A, B, D;D();B();"));
  }

  Future<void> test_writeType_shownImportWithCombinatorsOrdering() async {
    writeTestPackageAnalysisOptionsFile(lints: ['combinators_ordering']);
    var aPath = convertPath('$testPackageRootPath/lib/test_a.dart');
    var aContent = 'class A {} class C {} class Other {}';
    addSource(aPath, aContent);
    var bPath = convertPath('$testPackageRootPath/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' show C, A;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'Other');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show A, C, Other;Other"));
  }

  Future<void> test_writeType_shownImportWithConfiguration() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' show Other if (a.b);";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show A, Other if (a.b);A"));
  }

  Future<void> test_writeType_shownImportWithHide() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {} class OtherOne {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent =
        "import 'package:test/test_a.dart' show OtherOne hide Other;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show A, OtherOne hide Other;A"));
  }

  Future<void> test_writeType_shownImportWithHideSplit() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {} class OtherOne {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent =
        "import 'package:test/test_a.dart' show OtherOne; import 'package:test/test_a.dart' hide Other;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show OtherOne; import 'package:test/test_a.dart' hide Other;A"));
  }

  Future<void> test_writeType_shownImportWithMultipleCombinators() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class B {} class C {} class D {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent =
        "import 'package:test/test_a.dart' show B hide C show D hide A;";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(3));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show B hide C show A, D;A"));
  }

  Future<void> test_writeType_shownImportWithPrefix() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' as pack show Other;\n";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    var typeA = await _getType(aPath, 'A');
    await builder.addDartFileEdit(bPath, (builder) {
      builder.addInsertion(bContent.length, (builder) {
        builder.writeType(typeA);
      });
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' as pack show Other; import 'package:test/test_a.dart'; A"));
  }

  Future<void> test_writeType_simpleType() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(typeA);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A'));
  }

  Future<void> test_writeType_typedef_typeArguments() async {
    await _assertwriteType2('F<int, String>',
        declarations: 'typedef void F<T, U>(T t, U u);');
  }

  Future<void> test_writeType_void() async {
    await _assertwriteType2('void Function()');
  }

  Future<void> test_writeTypes_empty() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeTypes([]);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, isEmpty);
  }

  Future<void> test_writeTypes_noPrefix() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');
    DartType typeB = await _getType(path, 'B');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeTypes([typeA, typeB]);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('A, B'));
  }

  Future<void> test_writeTypes_null() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {}';
    addSource(path, content);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeTypes(null);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, isEmpty);
  }

  Future<void> test_writeTypes_prefix() async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = 'class A {} class B {}';
    addSource(path, content);
    DartType typeA = await _getType(path, 'A');
    DartType typeB = await _getType(path, 'B');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeTypes([typeA, typeB], prefix: 'implements ');
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace('implements A, B'));
  }

  Future<void> _assertwriteType2(String typeCode,
      {String? declarations}) async {
    var path = convertPath('/home/test/lib/test.dart');
    var content = '${declarations ?? ''}$typeCode v;';
    addSource(path, content);

    var f = await _getTopLevelGetter(path, 'v');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 1, (builder) {
        builder.writeType(f.returnType);
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, typeCode);
  }

  Future<ClassElement> _getClassElement(String path, String name) async {
    var unitResult = await resolveFile(path);
    return unitResult.libraryElement.getClass(name)!;
  }

  Future<PropertyAccessorElement> _getTopLevelGetter(
      String path, String name) async {
    var unitResult = await resolveFile(path);
    return unitResult.libraryElement.getGetter(name)!;
  }

  Future<InterfaceType> _getType(
    String path,
    String name, {
    List<DartType> typeArguments = const [],
  }) async {
    var classElement = await _getClassElement(path, name);
    return classElement.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }
}

@reflectiveTest
class DartFileEditBuilderImplTest extends AbstractContextTest
    with DartChangeBuilderMixin {
  Future<ResolvedUnitResult> resolveContent(String path, String content) {
    path = convertPath(path);
    addSource(path, content);
    return resolveFile(path);
  }

  Future<void> test_convertFunctionFromSyncToAsync_closure() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '''var f = () {}''');

    var resolvedUnit = await resolveFile(path);
    var findNode = FindNode(resolvedUnit.content, resolvedUnit.unit);
    var body = findNode.functionBody('{}');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.convertFunctionFromSyncToAsync(
        body: body,
        typeSystem: resolvedUnit.typeSystem,
        typeProvider: resolvedUnit.typeProvider,
      );
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement, equalsIgnoringWhitespace('async'));
  }

  Future<void> test_convertFunctionFromSyncToAsync_topLevelFunction() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'String f() {}');

    var resolvedUnit = await resolveFile(path);
    var findNode = FindNode(resolvedUnit.content, resolvedUnit.unit);
    var body = findNode.functionBody('{}');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.convertFunctionFromSyncToAsync(
        body: body,
        typeSystem: resolvedUnit.typeSystem,
        typeProvider: resolvedUnit.typeProvider,
      );
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(2));
    expect(edits[0].replacement, equalsIgnoringWhitespace('async'));
    expect(edits[1].replacement, equalsIgnoringWhitespace('Future<String>'));
  }

  Future<void> test_fileHeader_emptyFile() async {
    var initialCode = '''
''';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.fileHeader = '''
// File header
''';
    });

    var edits = getEdits(builder);
    var resultCode = SourceEdit.applySequence(initialCode, edits);
    expect(resultCode, r'''
// File header

''');
  }

  Future<void> test_fileHeader_withImports() async {
    var initialCode = '''
class C {}
''';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.fileHeader = '''
// File header
''';
      builder.importLibrary(Uri.parse('package:p/p.dart'));
    });

    var edits = getEdits(builder);
    var resultCode = SourceEdit.applySequence(initialCode, edits);
    expect(resultCode, r'''
// File header

import 'package:p/p.dart';

class C {}
''');
  }

  Future<void> test_fileHeader_withoutImports() async {
    var initialCode = '''
class C {}
''';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.fileHeader = '''
// File header
''';
    });

    var edits = getEdits(builder);
    var resultCode = SourceEdit.applySequence(initialCode, edits);
    expect(resultCode, r'''
// File header

class C {}
''');
  }

  Future<void> test_format_hasEdits() async {
    var initialCode = r'''
void functionBefore() {
  1 +  2;
}

void foo() {
  1 +  2;
  42;
  3 +  4;
}

void functionAfter() {
  1 +  2;
}
''';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(34, (builder) {
        builder.writeln('  3 +  4;');
      });
      builder.addSimpleReplacement(SourceRange(62, 2), '1 +  2 +  3');
      builder.addInsertion(112, (builder) {
        builder.writeln('  3 +  4;');
      });
      builder.format(SourceRange(48, 29));
    });

    var edits = getEdits(builder);
    var resultCode = SourceEdit.applySequence(initialCode, edits);
    expect(resultCode, r'''
void functionBefore() {
  1 +  2;
  3 +  4;
}

void foo() {
  1 + 2;
  1 + 2 + 3;
  3 + 4;
}

void functionAfter() {
  1 +  2;
  3 +  4;
}
''');
  }

  Future<void> test_format_noEdits() async {
    var initialCode = r'''
void functionBefore() {
  1 +  2;
}

void foo() {
  1 +  2;
  3;
  4 +  5;
}

void functionAfter() {
  1 +  2;
}
''';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.format(SourceRange(37, 39));
    });

    var edits = getEdits(builder);
    var resultCode = SourceEdit.applySequence(initialCode, edits);
    expect(resultCode, r'''
void functionBefore() {
  1 +  2;
}

void foo() {
  1 + 2;
  3;
  4 + 5;
}

void functionAfter() {
  1 +  2;
}
''');
  }

  Future<void> test_importElementLibrary_libElement() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');

    var resolvedLibUnit =
        await resolveContent('/home/test/lib/a.dart', 'class A {}');

    var findNode = FindNode(resolvedLibUnit.content, resolvedLibUnit.unit);
    var classElement = findNode.classDeclaration('A').declaredFragment!.element;
    var cache = <Element, LibraryElement?>{};
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) async {
      var builderImpl = builder as DartFileEditBuilderImpl;
      await builderImpl.importElementLibrary(classElement, resultCache: cache);
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement,
        equalsIgnoringWhitespace("import 'package:test/a.dart';\n"));
    expect(cache[classElement], resolvedLibUnit.libraryElement);
  }

  /// If `importElementLibrary` adds a pending import 'a.dart' and a subsequent
  /// call adds 'b.dart' that also exports the required element from 'b.dart'
  /// then the now-redundant 'a.dart' should be removed.

  Future<void> test_importElementLibrary_replacesPendingImports() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');

    // 'a.dart' exports just A.
    var resolvedAUnit =
        await resolveContent('/home/test/lib/a.dart', 'class A {}');

    // 'all.dart' exports both A and B.
    var resolvedAllUnit = await resolveContent('/home/test/lib/all.dart', '''
export 'a.dart';
class B {}
''');

    var classA = FindNode(resolvedAUnit.content, resolvedAUnit.unit)
        .classDeclaration('A')
        .declaredFragment!
        .element;
    var classB = FindNode(resolvedAllUnit.content, resolvedAllUnit.unit)
        .classDeclaration('B')
        .declaredFragment!
        .element;

    var cache = <Element, LibraryElement?>{};
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) async {
      var builderImpl = builder as DartFileEditBuilderImpl;
      await builderImpl.importElementLibrary(classA, resultCache: cache);
      await builderImpl.importElementLibrary(classB, resultCache: cache);
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement,
        equalsIgnoringWhitespace("import 'package:test/all.dart';\n"));
  }

  /// [test_importElementLibrary_replacesPendingImports] verifies that
  /// `importElementLibrary` can replace pending imports, but it must not do so
  /// if they were added explicitly (and not to satisfy a given [Element]).
  Future<void>
      test_importElementLibrary_replacesPendingImports_unlessImportedExplicitly() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');

    // 'a.dart' exports just A.
    var resolvedAUnit =
        await resolveContent('/home/test/lib/a.dart', 'class A {}');

    // 'all.dart' exports both A and B.
    var resolvedAllUnit = await resolveContent('/home/test/lib/all.dart', '''
export 'a.dart';
class B {}
''');

    var classA = FindNode(resolvedAUnit.content, resolvedAUnit.unit)
        .classDeclaration('A')
        .declaredFragment!
        .element;
    var classB = FindNode(resolvedAllUnit.content, resolvedAllUnit.unit)
        .classDeclaration('B')
        .declaredFragment!
        .element;

    var cache = <Element, LibraryElement?>{};
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) async {
      var builderImpl = builder as DartFileEditBuilderImpl;
      // Explicitly add 'a.dart' in addition to locating it for elements.
      builderImpl.importLibrary(Uri.parse('package:test/a.dart'));
      await builderImpl.importElementLibrary(classA, resultCache: cache);
      await builderImpl.importElementLibrary(classB, resultCache: cache);
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    // Expect 'a.dart' was not removed, because it was added explicitly.
    expect(edits[0].replacement, equalsIgnoringWhitespace('''
import 'package:test/a.dart';
import 'package:test/all.dart';
        '''));
  }

  Future<void> test_importElementLibrary_sdkElement() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');

    var futureOrElement = resolvedUnit.typeProvider.futureOrElement;
    var cache = <Element, LibraryElement?>{};
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) async {
      var builderImpl = builder as DartFileEditBuilderImpl;
      await builderImpl.importElementLibrary(futureOrElement,
          resultCache: cache);
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(
        edits[0].replacement, equalsIgnoringWhitespace("import 'dart:async';"));
    expect(cache[futureOrElement], futureOrElement.library);
  }

  Future<void> test_importElementLibrary_srcElement() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');

    var resolvedSrcUnit =
        await resolveContent('/home/test/lib/src/a.dart', 'class A {}');

    var resolvedExportUnit =
        await resolveContent('/home/test/lib/a.dart', "export 'src/a.dart'");

    var findNode = FindNode(resolvedSrcUnit.content, resolvedSrcUnit.unit);
    var classElement = findNode.classDeclaration('A').declaredFragment!.element;
    var cache = <Element, LibraryElement?>{};
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) async {
      var builderImpl = builder as DartFileEditBuilderImpl;
      await builderImpl.importElementLibrary(classElement, resultCache: cache);
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement,
        equalsIgnoringWhitespace("import 'package:test/a.dart';\n"));
    expect(cache[classElement], resolvedExportUnit.libraryElement);
  }

  Future<void> test_importElementLibrary_usesCache() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');

    // Create a fake file to put into the cache to verify it's being used.
    var resolvedFakeUnit = await resolveContent('/home/test/lib/fake.dart', '');

    var futureOrElement = resolvedUnit.typeProvider.futureOrElement;
    var cache = <Element, LibraryElement?>{
      futureOrElement: resolvedFakeUnit.libraryElement,
    };
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) async {
      var builderImpl = builder as DartFileEditBuilderImpl;
      await builderImpl.importElementLibrary(futureOrElement,
          resultCache: cache);
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement,
        equalsIgnoringWhitespace("import 'package:test/fake.dart';"));
    expect(cache[futureOrElement], resolvedFakeUnit.libraryElement);
  }

  /// Ensure that trying to add an import to show a symbol works with an
  /// explicit empty prefix (to ensure an import with a prefix is not reused nor
  /// a prefix generated).
  Future<void> test_importLibrary_showName_emptyPrefix() async {
    var aPath = convertPath('/home/test/lib/test_a.dart');
    var aContent = 'class A {} class Other {}';
    addSource(aPath, aContent);
    var bPath = convertPath('/home/test/lib/test_b.dart');
    var bContent = "import 'package:test/test_a.dart' show Other; A";
    addSource(bPath, bContent);

    var builder = await newBuilder();
    await builder.addDartFileEdit(bPath, (builder) {
      // Add an import to ensure 'A' is visible without a prefix.
      builder.importLibrary(Uri.parse('package:test/test_a.dart'),
          showName: 'A', prefix: '');
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    var edited = SourceEdit.applySequence(bContent, edits);
    expect(
        edited,
        equalsIgnoringWhitespace(
            "import 'package:test/test_a.dart' show A, Other; A"));
  }

  Future<void> test_importLibrary_sorted() async {
    var resolvedUnit = await resolveContent('/home/test/lib/test.dart', '');
    var builder = await newBuilder();
    await builder.addDartFileEdit(resolvedUnit.path, (builder) {
      builder.importLibrary(Uri.parse('z.dart'));
      builder.importLibrary(Uri.parse('a.dart'));
      builder.importLibrary(Uri.parse('../z.dart'));
      builder.importLibrary(Uri.parse('../a.dart'));
      builder.importLibrary(Uri.parse('package:foo/x.dart'));
      builder.importLibrary(Uri.parse('package:foo/a.dart'));
      builder.importLibrary(Uri.parse('dart:x'));
      builder.importLibrary(Uri.parse('dart:a'));
    });

    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement, equalsIgnoringWhitespace('''
import 'dart:a';
import 'dart:x';
import 'package:foo/a.dart';
import 'package:foo/x.dart';
import '../a.dart';
import '../z.dart';
import 'a.dart';
import 'z.dart';
'''));
  }

  Future<void> test_multipleEdits_concurrently() async {
    var initialCode = '00';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    var future = Future.wait([
      builder.addDartFileEdit(path, (builder) {
        builder.addSimpleInsertion(0, '11');
      }),
      builder.addDartFileEdit(path, (builder) {
        builder.addSimpleInsertion(2, '22');
      }),
    ]);

    expect(future, throwsA(TypeMatcher<StateError>()));
  }

  Future<void> test_multipleEdits_sequentially() async {
    var initialCode = '00';
    var path = convertPath('/home/test/lib/test.dart');
    newFile(path, initialCode);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addSimpleInsertion(0, '11');
    });
    await builder.addDartFileEdit(path, (builder) {
      builder.addSimpleInsertion(2, '22');
    });

    var edits = getEdits(builder);
    var resultCode = SourceEdit.applySequence(initialCode, edits);
    expect(resultCode, '110022');
  }

  Future<void> test_replaceTypeWithFuture() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, 'String f() {}');

    var resolvedUnit = await resolveFile(path);
    var findNode = FindNode(resolvedUnit.content, resolvedUnit.unit);
    var type = findNode.typeAnnotation('String');

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.replaceTypeWithFuture(
        typeAnnotation: type,
        typeProvider: resolvedUnit.typeProvider,
        typeSystem: resolvedUnit.typeSystem,
      );
    });
    var edits = getEdits(builder);
    expect(edits, hasLength(1));
    expect(edits[0].replacement, equalsIgnoringWhitespace('Future<String>'));
  }

  Future<void> test_revert_librariesToImport() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '');
    await resolveFile(path);

    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.importLibrary(Uri.parse('dart:math'));
    });
    builder.commit();

    await builder.addDartFileEdit(path, (builder) {
      builder.importLibrary(Uri.parse('dart:io'));
    });
    builder.revert();

    var change = builder.sourceChange;
    expect(change.edits[0].edits[0].replacement, 'import \'dart:math\';\n');
  }
}

@reflectiveTest
class DartLinkedEditBuilderImplTest extends AbstractContextTest {
  Future<void> test_addSuperTypesAsSuggestions_noneSuffix() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '''
class A {}
class B extends A {}
class C extends B {}
''');
    var unit = (await resolveFile(path)).unit;
    var classC = unit.declarations[2] as ClassDeclaration;
    var builder = DartLinkedEditBuilderImpl(MockDartEditBuilderImpl());
    builder.addSuperTypesAsSuggestions(
      classC.declaredFragment!.element.instantiate(
        typeArguments: [],
        nullabilitySuffix: NullabilitySuffix.none,
      ),
    );
    var suggestions = builder.suggestions;
    expect(suggestions, hasLength(4));
    expect(suggestions.map((s) => s.value),
        unorderedEquals(['Object', 'A', 'B', 'C']));
  }

  Future<void> test_addSuperTypesAsSuggestions_questionSuffix() async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, '''
class A {}
class B extends A {}
class C extends B {}
''');
    var unit = (await resolveFile(path)).unit;
    var classC = unit.declarations[2] as ClassDeclaration;
    var builder = DartLinkedEditBuilderImpl(MockDartEditBuilderImpl());
    builder.addSuperTypesAsSuggestions(
      classC.declaredFragment!.element.instantiate(
        typeArguments: [],
        nullabilitySuffix: NullabilitySuffix.question,
      ),
    );
    var suggestions = builder.suggestions;
    expect(suggestions, hasLength(4));
    expect(suggestions.map((s) => s.value),
        unorderedEquals(['Object?', 'A?', 'B?', 'C?']));
  }
}

@reflectiveTest
class ImportLibraryElementTest extends AbstractContextTest
    with DartChangeBuilderMixin {
  Future<void> test_show_name_differentCombinators() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';
import 'other.dart' hide B, C show A, D;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';
import 'other.dart' hide C show A, B, D;

class A {}
''',
    );
  }

  Future<void> test_show_name_hideCombinator_multipleNames() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';
import 'other.dart' hide A, B;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';
import 'other.dart' hide A;

class A {}
''',
    );
  }

  Future<void> test_show_name_hideCombinator_name() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';
import 'other.dart' hide B;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';
import 'other.dart';

class A {}
''',
    );
  }

  Future<void> test_show_name_multipleHide() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';
import 'other.dart' hide B hide A, D;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';
import 'other.dart' hide A, D;

class A {}
''',
    );
  }

  Future<void> test_show_name_multipleShow() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';
import 'other.dart' show B show A, D;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';
import 'other.dart' show B show A, B, D;

class A {}
''',
    );
  }

  Future<void> test_show_name_no_combinator() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';

import 'package:test/other.dart';

class A {}
''',
    );
  }

  Future<void> test_show_name_prefix() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';

import 'package:test/other.dart' as b;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';

import 'package:test/other.dart' as b;

class A {}
''',
    );
  }

  Future<void> test_show_name_showCombinator() async {
    _createOther();
    await _assertImportLibraryElement(
      initialCode: '''
import 'dart:aaa';
import 'other.dart' show A;

class A {}
''',
      uriString: 'package:test/other.dart',
      showName: 'B',
      expectedCode: '''
import 'dart:aaa';
import 'other.dart' show A, B;

class A {}
''',
    );
  }

  Future<void> _assertImportLibraryElement({
    required String initialCode,
    required String uriString,
    required String expectedCode,
    String? prefix,
    String? showName,
    bool createEditsForImports = true,
  }) async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, initialCode);
    var builder = await newBuilder();
    await builder.addDartFileEdit(path,
        createEditsForImports: createEditsForImports, (builder) {
      var uri = Uri.parse(uriString);
      builder.importLibraryElement(uri, prefix: prefix, showName: showName);
    });

    var resultCode = initialCode;
    var edits = getEdits(builder);
    for (var edit in edits) {
      resultCode = edit.apply(resultCode);
    }
    expect(resultCode, expectedCode);
  }

  File _createOther() {
    return newFile(convertPath('/home/test/lib/other.dart'), '''
class A {}
class B {}
class C {}
class D {}
''');
  }
}

@reflectiveTest
class ImportLibraryTest extends AbstractContextTest
    with DartChangeBuilderMixin {
  Future<void> test_dart_afterDart_last() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:aaa';

class A {}
''',
      uriList: ['dart:bbb'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';

class A {}
''',
    );
  }

  Future<void> test_dart_beforeDart() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:aaa';
import 'dart:ccc';
''',
      uriList: ['dart:bbb'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';
import 'dart:ccc';
''',
    );
  }

  Future<void> test_dart_beforeDart_first() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:bbb';
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';
''',
    );
  }

  Future<void> test_dart_beforeExport() async {
    await _assertImportLibrary(
      initialCode: '''
export 'dart:aaa';
''',
      uriList: ['dart:bbb'],
      expectedCode: '''
import 'dart:bbb';

export 'dart:aaa';
''',
    );
  }

  Future<void> test_dart_beforePackage() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:foo/foo.dart';
''',
      uriList: ['dart:async'],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';
''',
    );
  }

  Future<void> test_default_quote() async {
    await _assertImportLibrary(
      initialCode: '''
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import 'dart:aaa';
''',
    );
  }

  Future<void> test_directive_adjacent_strings() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:' "async";
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:' "async";
''',
    );
  }

  Future<void> test_directive_common_double_quote() async {
    await _assertImportLibrary(
      initialCode: '''
import "dart:async";
import "dart:math";
import 'dart:bbb';
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import "dart:aaa";
import "dart:async";
import "dart:math";
import 'dart:bbb';
''',
    );
  }

  Future<void> test_directive_common_single_quote() async {
    await _assertImportLibrary(
      initialCode: '''
import "dart:math";
import 'dart:bbb';
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import 'dart:aaa';
import "dart:math";
import 'dart:bbb';
''',
    );
  }

  Future<void> test_directive_double_quote() async {
    await _assertImportLibrary(
      initialCode: '''
import "dart:bbb";
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import "dart:aaa";
import "dart:bbb";
''',
    );
  }

  Future<void> test_directive_single_quote() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:bbb';
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';
''',
    );
  }

  Future<void> test_multiple_dart_then_package() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:aaa';
import 'dart:ccc';

import 'package:aaa/aaa.dart';
import 'package:ccc/ccc.dart';
''',
      uriList: ['dart:bbb', 'package:bbb/bbb.dart'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';
import 'dart:ccc';

import 'package:aaa/aaa.dart';
import 'package:bbb/bbb.dart';
import 'package:ccc/ccc.dart';
''',
    );
  }

  Future<void> test_multiple_package_then_dart() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:aaa';
import 'dart:ccc';

import 'package:aaa/aaa.dart';
import 'package:ccc/ccc.dart';
''',
      uriList: ['package:bbb/bbb.dart', 'dart:bbb'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';
import 'dart:ccc';

import 'package:aaa/aaa.dart';
import 'package:bbb/bbb.dart';
import 'package:ccc/ccc.dart';
''',
    );
  }

  Future<void> test_noDirectives_docComment() async {
    await _assertImportLibrary(
      initialCode: '''
/// Documentation comment.
/// Continues.
void main() {}
''',
      uriList: ['dart:async'],
      expectedCode: '''
import 'dart:async';

/// Documentation comment.
/// Continues.
void main() {}
''',
    );
  }

  Future<void> test_noDirectives_hashBang() async {
    await _assertImportLibrary(
      initialCode: '''
#!/bin/dart

void main() {}
''',
      uriList: ['dart:async'],
      expectedCode: '''
#!/bin/dart

import 'dart:async';

void main() {}
''',
    );
  }

  Future<void> test_noDirectives_lineComment() async {
    await _assertImportLibrary(
      initialCode: '''
// Not documentation comment.
// Continues.

void main() {}
''',
      uriList: ['dart:async'],
      expectedCode: '''
// Not documentation comment.
// Continues.

import 'dart:async';

void main() {}
''',
    );
  }

  Future<void> test_noImports_afterLibrary_hasDeclaration() async {
    await _assertImportLibrary(
      initialCode: '''
library test;

class A {}
''',
      uriList: ['dart:async'],
      expectedCode: '''
library test;

import 'dart:async';

class A {}
''',
    );
  }

  Future<void> test_noImports_afterLibrary_hasPart() async {
    await _assertImportLibrary(
      initialCode: '''
library test;

part 'a.dart';
''',
      uriList: ['dart:aaa', 'dart:bbb'],
      expectedCode: '''
library test;

import 'dart:aaa';
import 'dart:bbb';

part 'a.dart';
''',
    );
  }

  Future<void> test_noImports_beforePart() async {
    await _assertImportLibrary(
      initialCode: '''
part 'a.dart';
part 'b.dart';
''',
      uriList: ['dart:aaa', 'dart:bbb'],
      expectedCode: '''
import 'dart:aaa';
import 'dart:bbb';

part 'a.dart';
part 'b.dart';
''',
    );
  }

  Future<void> test_package_afterDart() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';
''',
      uriList: ['package:aaa/aaa.dart'],
      expectedCode: '''
import 'dart:async';

import 'package:aaa/aaa.dart';
''',
    );
  }

  Future<void> test_package_afterPackage() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:aaa/a1.dart';

import 'foo.dart';
''',
      uriList: ['package:aaa/a2.dart'],
      expectedCode: '''
import 'package:aaa/a1.dart';
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_afterPackage_leadingComment() async {
    await _assertImportLibrary(
      initialCode: '''
// comment
import 'package:aaa/a1.dart';

import 'foo.dart';
''',
      uriList: ['package:aaa/a2.dart'],
      expectedCode: '''
// comment
import 'package:aaa/a1.dart';
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_afterPackage_trailingComment() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:aaa/a1.dart'; // comment

import 'foo.dart';
''',
      uriList: ['package:aaa/a2.dart'],
      expectedCode: '''
import 'package:aaa/a1.dart'; // comment
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_beforePackage() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:aaa/a1.dart';
import 'package:aaa/a3.dart';

import 'foo.dart';
''',
      uriList: ['package:aaa/a2.dart'],
      expectedCode: '''
import 'package:aaa/a1.dart';
import 'package:aaa/a2.dart';
import 'package:aaa/a3.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_beforePackage_first() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
      uriList: ['package:aaa/a1.dart'],
      expectedCode: '''
import 'package:aaa/a1.dart';
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_beforePackage_leadingComments() async {
    await _assertImportLibrary(
      initialCode: '''
// comment a2
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
      uriList: ['package:aaa/a1.dart'],
      expectedCode: '''
// comment a2
import 'package:aaa/a1.dart';
import 'package:aaa/a2.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_beforePackage_trailingComments() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:aaa/a2.dart'; // comment a2

import 'foo.dart';
''',
      uriList: ['package:aaa/a1.dart'],
      expectedCode: '''
import 'package:aaa/a1.dart';
import 'package:aaa/a2.dart'; // comment a2

import 'foo.dart';
''',
    );
  }

  Future<void> test_package_beforeRelative() async {
    await _assertImportLibrary(
      initialCode: '''
import 'foo.dart';
''',
      uriList: ['package:aaa/aaa.dart'],
      expectedCode: '''
import 'package:aaa/aaa.dart';

import 'foo.dart';
''',
    );
  }

  Future<void> test_prefer_double_quotes() async {
    writeTestPackageAnalysisOptionsFile(lints: ['prefer_double_quotes']);
    await _assertImportLibrary(
      initialCode: '''
import 'dart:bbb';
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import "dart:aaa";
import 'dart:bbb';
''',
    );
  }

  Future<void> test_prefer_single_quotes() async {
    writeTestPackageAnalysisOptionsFile(lints: ['prefer_single_quotes']);
    await _assertImportLibrary(
      initialCode: '''
import "dart:bbb";
''',
      uriList: ['dart:aaa'],
      expectedCode: '''
import 'dart:aaa';
import "dart:bbb";
''',
    );
  }

  Future<void> test_relative_afterDart() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';
''',
      uriList: ['aaa.dart'],
      expectedCode: '''
import 'dart:async';

import 'aaa.dart';
''',
    );
  }

  Future<void> test_relative_afterPackage() async {
    await _assertImportLibrary(
      initialCode: '''
import 'package:foo/foo.dart';
''',
      uriList: ['aaa.dart'],
      expectedCode: '''
import 'package:foo/foo.dart';

import 'aaa.dart';
''',
    );
  }

  Future<void> test_relative_beforeRelative() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart';
import 'ccc.dart';
''',
      uriList: ['bbb.dart'],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart';
import 'bbb.dart';
import 'ccc.dart';
''',
    );
  }

  Future<void> test_relative_beforeRelative_first() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'bbb.dart';
''',
      uriList: ['aaa.dart'],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart';
import 'bbb.dart';
''',
    );
  }

  Future<void> test_relative_last() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';

import 'package:foo/foo.dart';
''',
      uriList: ['aaa.dart'],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart';
''',
    );
  }

  Future<void> test_withoutImportEdits() async {
    await _assertImportLibrary(
      createEditsForImports: false,
      initialCode: '''
import 'dart:aaa';

class A {}
''',
      uriList: ['dart:bbb'],
      expectedCode: '''
import 'dart:aaa';

class A {}
''',
    );
  }

  Future<void> test_withPrefix() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';

import 'package:foo/foo.dart';
''',
      uriList: ['aaa.dart'],
      prefixList: ['aaa'],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart' as aaa;
''',
    );
  }

  Future<void> test_withPrefix_andUnprefixed() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';

import 'package:foo/foo.dart';
''',
      uriList: ['aaa.dart', 'aaa.dart'],
      prefixList: ['aaa', ''],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart';
import 'aaa.dart' as aaa;
''',
    );
  }

  Future<void> test_withPrefix_multiple() async {
    await _assertImportLibrary(
      initialCode: '''
import 'dart:async';

import 'package:foo/foo.dart';
''',
      uriList: ['aaa.dart', 'aaa.dart'],
      prefixList: ['aaa1', 'aaa2'],
      expectedCode: '''
import 'dart:async';

import 'package:foo/foo.dart';

import 'aaa.dart' as aaa1;
import 'aaa.dart' as aaa2;
''',
    );
  }

  Future<void> _assertImportLibrary({
    required String initialCode,
    required List<String> uriList,
    required String expectedCode,
    List<String?>? prefixList,
    bool createEditsForImports = true,
  }) async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, initialCode);
    var builder = await newBuilder();
    await builder.addDartFileEdit(path,
        createEditsForImports: createEditsForImports, (builder) {
      for (var i = 0; i < uriList.length; ++i) {
        var uri = Uri.parse(uriList[i]);
        builder.importLibrary(uri, prefix: prefixList?[i]);
      }

      expect(builder.requiredImports.map((uri) => uri.toString()),
          uriList.toSet());
    });

    var resultCode = initialCode;
    var edits = getEdits(builder);
    for (var edit in edits) {
      resultCode = edit.apply(resultCode);
    }
    expect(resultCode, expectedCode);
  }
}

@reflectiveTest
class WriteOverrideTest extends AbstractContextTest
    with DartChangeBuilderMixin {
  Future<void> test_getter_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  int get zero;
}
class B extends A {
}
''',
      nameToOverride: 'zero',
      expected: '''
  @override
  // TODO: implement zero
  int get zero => throw UnimplementedError();
''',
      displayText: 'zero => …',
      selection: SourceRange(111, 26),
    );
  }

  Future<void> test_getter_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  int get zero => 0;
}
class B extends A {
}
''',
      nameToOverride: 'zero',
      invokeSuper: true,
      expected: '''
  @override
  // TODO: implement zero
  int get zero => super.zero;
''',
      displayText: 'zero => …',
      selection: SourceRange(107, 10),
    );
  }

  Future<void> test_method_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  A add(A a);
}
class B extends A {
}
''',
      nameToOverride: 'add',
      expected: '''
  @override
  A add(A a) {
    // TODO: implement add
    throw UnimplementedError();
  }
''',
      displayText: 'add(A a) { … }',
      selection: SourceRange(111, 27),
    );
  }

  Future<void> test_method_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  A add(A a) => null;
}
class B extends A {
}
''',
      nameToOverride: 'add',
      invokeSuper: true,
      expected: '''
  @override
  A add(A a) {
    // TODO: implement add
    return super.add(a);
  }
''',
      displayText: 'add(A a) { … }',
      selection: SourceRange(110, 20),
    );
  }

  Future<void> test_method_functionTypeAlias_abstract() async {
    await _assertWriteOverride(
      content: '''
typedef int F(int left, int right);
abstract class A {
  void perform(F f);
}
class B extends A {
}
''',
      nameToOverride: 'perform',
      expected: '''
  @override
  void perform(F f) {
    // TODO: implement perform
  }
''',
      displayText: 'perform(F f) { … }',
    );
  }

  Future<void> test_method_functionTypeAlias_concrete() async {
    await _assertWriteOverride(
      content: '''
typedef int F(int left, int right);
class A {
  void perform(F f) {}
}
class B extends A {
}
''',
      nameToOverride: 'perform',
      invokeSuper: true,
      expected: '''
  @override
  void perform(F f) {
    // TODO: implement perform
    super.perform(f);
  }
''',
      displayText: 'perform(F f) { … }',
      selection: SourceRange(158, 17),
    );
  }

  Future<void> test_method_functionTypedParameter_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  forEach(int f(double p1, String p2));
}
class B extends A {
}
''',
      nameToOverride: 'forEach',
      expected: '''
  @override
  forEach(int Function(double p1, String p2) f) {
    // TODO: implement forEach
    throw UnimplementedError();
  }
''',
      displayText: 'forEach(int Function(double p1, String p2) f) { … }',
      selection: SourceRange(176, 27),
    );
  }

  Future<void> test_method_functionTypedParameter_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  forEach(int f(double p1, String p2)) {}
}
class B extends A {
}
''',
      nameToOverride: 'forEach',
      invokeSuper: true,
      expected: '''
  @override
  forEach(int Function(double p1, String p2) f) {
    // TODO: implement forEach
    return super.forEach(f);
  }
''',
      displayText: 'forEach(int Function(double p1, String p2) f) { … }',
      selection: SourceRange(169, 24),
    );
  }

  Future<void> test_method_generic_noBounds_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  List<T> get<T>(T key);
}
class B implements A {
}
''',
      nameToOverride: 'get',
      expected: '''
  @override
  List<T> get<T>(T key) {
    // TODO: implement get
    throw UnimplementedError();
  }
''',
      displayText: 'get<T>(T key) { … }',
      selection: SourceRange(136, 27),
    );
  }

  Future<void> test_method_generic_noBounds_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  List<T> get<T>(T key) {}
}
class B implements A {
}
''',
      nameToOverride: 'get',
      invokeSuper: true,
      expected: '''
  @override
  List<T> get<T>(T key) {
    // TODO: implement get
    return super.get(key);
  }
''',
      displayText: 'get<T>(T key) { … }',
      selection: SourceRange(129, 22),
    );
  }

  Future<void> test_method_generic_withBounds_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A<K1, V1> {
  List<T> get<T extends V1>(K1 key);
}
class B<K2, V2> implements A<K2, V2> {
}
''',
      nameToOverride: 'get',
      expected: '''
  @override
  List<T> get<T extends V2>(K2 key) {
    // TODO: implement get
    throw UnimplementedError();
  }
''',
      displayText: 'get<T extends V2>(K2 key) { … }',
      selection: SourceRange(184, 27),
    );
  }

  Future<void> test_method_generic_withBounds_concrete() async {
    await _assertWriteOverride(
      content: '''
class A<K1, V1> {
  List<T> get<T extends V1>(K1 key) {
    return null;
  }
}
class B<K2, V2> implements A<K2, V2> {
}
''',
      nameToOverride: 'get',
      invokeSuper: true,
      expected: '''
  @override
  List<T> get<T extends V2>(K2 key) {
    // TODO: implement get
    return super.get(key);
  }
''',
      displayText: 'get<T extends V2>(K2 key) { … }',
      selection: SourceRange(197, 22),
    );
  }

  Future<void> test_method_genericFunctionTypedParameter_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  int foo(T Function<T>() fn);
}
class B extends A {
}
''',
      nameToOverride: 'foo',
      expected: '''
  @override
  int foo(T Function<T>() fn) {
    // TODO: implement foo
    throw UnimplementedError();
 }
''',
      displayText: 'foo(T Function<T>() fn) { … }',
      selection: SourceRange(145, 27),
    );
  }

  Future<void> test_method_genericFunctionTypedParameter_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  int foo(T Function<T>() fn) => 0;
}
class B extends A {
}
''',
      nameToOverride: 'foo',
      invokeSuper: true,
      expected: '''
  @override
  int foo(T Function<T>() fn) {
    // TODO: implement foo
    return super.foo(fn);
 }
''',
      displayText: 'foo(T Function<T>() fn) { … }',
      selection: SourceRange(141, 21),
    );
  }

  Future<void> test_method_nullAsTypeArgument_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  List<Null> foo();
}
class B extends A {
}
''',
      nameToOverride: 'foo',
      expected: '''
  @override
  List<Null> foo() {
    // TODO: implement foo
    throw UnimplementedError();
 }
''',
      displayText: 'foo() { … }',
      selection: SourceRange(123, 27),
    );
  }

  Future<void> test_method_nullAsTypeArgument_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  List<Null> foo() => null
}
class B extends A {
}
''',
      nameToOverride: 'foo',
      invokeSuper: true,
      expected: '''
  @override
  List<Null> foo() {
    // TODO: implement foo
    return super.foo();
 }
''',
      displayText: 'foo() { … }',
      selection: SourceRange(121, 19),
    );
  }

  Future<void> test_method_returnVoid_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  void test();
}
class B extends A {
}
''',
      nameToOverride: 'test',
      expected: '''
  @override
  void test() {
    // TODO: implement test
  }
''',
      displayText: 'test() { … }',
      selection: SourceRange(109, 0),
    );
  }

  Future<void> test_method_voidAsTypeArgument_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  List<void> foo();
}
class B extends A {
}
''',
      nameToOverride: 'foo',
      expected: '''
  @override
  List<void> foo() {
    // TODO: implement foo
    throw UnimplementedError();
  }
''',
      displayText: 'foo() { … }',
      selection: SourceRange(123, 27),
    );
  }

  Future<void> test_method_voidAsTypeArgument_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  List<void> foo() => null;
}
class B extends A {
}
''',
      nameToOverride: 'foo',
      invokeSuper: true,
      expected: '''
  @override
  List<void> foo() {
    // TODO: implement foo
    return super.foo();
  }
''',
      displayText: 'foo() { … }',
      selection: SourceRange(122, 19),
    );
  }

  Future<void> test_method_wildcardParams() async {
    await _assertWriteOverride(
      content: '''
class A {
  void m(int _, [int _]) { }
}
class B extends A {
}
''',
      nameToOverride: 'm',
      expected: '''
  @override void m(int _, [int _]) {
    // TODO: implement m
  }
''',
      displayText: 'm(int _, [int _]) { … }',
      selection: SourceRange(122, 0),
    );
  }

  Future<void> test_mixin_method_of_interface() async {
    await _assertWriteOverride(
      content: '''
class A {
  void foo(int a) {}
}

mixin M implements A {
}
''',
      nameToOverride: 'foo',
      targetMixinName: 'M',
      expected: '''
  @override
  void foo(int a) {
    // TODO: implement foo
  }
''',
      displayText: 'foo(int a) { … }',
      selection: SourceRange(113, 0),
    );
  }

  Future<void> test_mixin_method_of_superclassConstraint() async {
    await _assertWriteOverride(
      content: '''
class A {
  void foo(int a) {}
}

mixin M on A {
}
''',
      nameToOverride: 'foo',
      targetMixinName: 'M',
      invokeSuper: true,
      expected: '''
  @override
  void foo(int a) {
    // TODO: implement foo
    super.foo(a);
  }
''',
      displayText: 'foo(int a) { … }',
      selection: SourceRange(110, 13),
    );
  }

  Future<void> test_setter_abstract() async {
    await _assertWriteOverride(
      content: '''
abstract class A {
  set value(int value);
}
class B extends A {
}
''',
      nameToOverride: 'value=',
      expected: '''
  @override
  set value(int value) {
    // TODO: implement value
  }
''',
      displayText: 'value(int value) { … }',
      selection: SourceRange(128, 0),
    );
  }

  Future<void> test_setter_concrete() async {
    await _assertWriteOverride(
      content: '''
class A {
  set value(int value) {}
}
class B extends A {
}
''',
      nameToOverride: 'value=',
      invokeSuper: true,
      expected: '''
  @override
  set value(int value) {
    // TODO: implement value
    super.value = value;
  }
''',
      displayText: 'value(int value) { … }',
      selection: SourceRange(126, 20),
    );
  }

  /// Assuming that the [content] being edited defines a class named `A` whose
  /// member with the given [nameToOverride] to be overridden and has
  /// `class B extends A {...}` to which an inherited method is to be added,
  /// assert that the text of the overridden member matches the [expected] text
  /// (modulo white space). Assert that the generated display text matches the
  /// given [displayText]. If a [selection] is provided, assert that the
  /// generated selection range matches it.
  Future<void> _assertWriteOverride({
    required String content,
    required String nameToOverride,
    required String expected,
    String? displayText,
    SourceRange? selection,
    String targetClassName = 'B',
    String? targetMixinName,
    bool invokeSuper = false,
  }) async {
    var path = convertPath('/home/test/lib/test.dart');
    addSource(path, content);

    InterfaceElement? targetElement;
    {
      var unitResult = await resolveFile(path);
      if (targetMixinName != null) {
        targetElement = unitResult.libraryElement.getMixin(targetMixinName)!;
      } else {
        targetElement = unitResult.libraryElement.getClass(targetClassName)!;
      }
    }

    var inherited =
        targetElement.getInheritedMember(Name(null, nameToOverride));
    var displayBuffer = displayText != null ? StringBuffer() : null;
    var builder = await newBuilder();
    await builder.addDartFileEdit(path, (builder) {
      builder.addInsertion(content.length - 2, (builder) {
        builder.writeOverride(
          inherited!,
          displayTextBuffer: displayBuffer,
          invokeSuper: invokeSuper,
        );
      });
    });
    var edit = getEdit(builder);
    expect(edit.replacement, equalsIgnoringWhitespace(expected));
    expect(displayBuffer?.toString(), displayText);
    if (selection != null) {
      expect(builder.selectionRange, selection);
    }
  }
}
