// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert" show JsonEncoder;
import "dart:io" show File;

import "package:front_end/src/type_inference/type_schema.dart" show UnknownType;
import "package:kernel/ast.dart";

String jsonEncode(Object object) {
  return const JsonEncoder.withIndent("  ").convert(object);
}

Iterable<String> nameGenerator() sync* {
  int i = 0;
  while (true) {
    List<int> characters = <int>[];
    int j = i;
    while (j > 25) {
      int c = j % 26;
      j = (j ~/ 26) - 1;
      characters.add(c + 65);
    }
    characters.add(j + 65);
    yield new String.fromCharCodes(characters.reversed);
    i++;
  }
}

class BenchMaker implements DartTypeVisitor1<void, StringBuffer> {
  final List<Object> checks = <Object>[];

  final Map<TreeNode, String> nodeNames = <TreeNode, String>{};

  final Map<StructuralParameter, String> structuralParameterNames =
      <StructuralParameter, String>{};

  final Set<String> usedNames = new Set<String>();

  final Iterator<String> names = nameGenerator().iterator..moveNext();

  final List<String> declarations = <String>[];

  final List<TypeParameter> usedTypeParameters = <TypeParameter>[];

  final List<StructuralParameter> usedStructuralParameters =
      <StructuralParameter>[];

  String serializeTypeChecks(List<Object> typeChecks) {
    for (Object list in typeChecks) {
      List<Object> typeCheck = list as List<Object>;
      writeTypeCheck(typeCheck[0] as DartType, typeCheck[1] as DartType,
          typeCheck[2] as bool);
    }
    writeDeclarations();
    return jsonEncode(this);
  }

  void writeTypeCheck(DartType s, DartType t, bool expected) {
    assert(usedTypeParameters.isEmpty);
    assert(usedStructuralParameters.isEmpty);
    usedTypeParameters.clear();
    usedStructuralParameters.clear();
    StringBuffer sb = new StringBuffer();
    s.accept1(this, sb);
    String sString = "$sb";
    sb.clear();
    t.accept1(this, sb);
    String tString = "$sb";
    List<Object> arguments = <Object>[sString, tString];
    Set<TypeParameter> seenTypeParameters = new Set<TypeParameter>();
    Set<StructuralParameter> seenStructuralParameters =
        new Set<StructuralParameter>();
    List<String> parameterStrings = <String>[];
    while (usedTypeParameters.isNotEmpty) {
      List<TypeParameter> typeParameters = usedTypeParameters.toList();
      usedTypeParameters.clear();
      for (TypeParameter parameter in typeParameters) {
        if (seenTypeParameters.add(parameter)) {
          sb.clear();
          writeTypeParameter(parameter, sb);
          parameterStrings.add("$sb");
        }
      }
    }
    while (usedStructuralParameters.isNotEmpty) {
      List<StructuralParameter> structuralParameters =
          usedStructuralParameters.toList();
      usedStructuralParameters.clear();
      for (StructuralParameter parameter in structuralParameters) {
        if (seenStructuralParameters.add(parameter)) {
          sb.clear();
          writeStructuralParameter(parameter, sb);
          parameterStrings.add("$sb");
        }
      }
    }
    if (parameterStrings.isNotEmpty) {
      arguments.add(parameterStrings);
    }
    checks.add(<String, dynamic>{
      "kind": expected ? "isSubtype" : "isNotSubtype",
      "arguments": arguments,
    });
  }

  void writeTypeParameter(TypeParameter parameter, StringBuffer sb) {
    sb.write(computeName(parameter));
    DartType bound = parameter.bound;
    DartType defaultType = parameter.defaultType;
    bool hasExplicitBound = true;
    if (bound is InterfaceType && defaultType is DynamicType) {
      if (bound.classNode.supertype == null) {
        hasExplicitBound = false;
      }
    }
    if (hasExplicitBound) {
      sb.write(" extends ");
      bound.accept1(this, sb);
    }
  }

  void writeStructuralParameter(
      StructuralParameter parameter, StringBuffer sb) {
    sb.write(computeStructuralParameterName(parameter));
    DartType bound = parameter.bound;
    DartType defaultType = parameter.defaultType;
    bool hasExplicitBound = true;
    if (bound is InterfaceType && defaultType is DynamicType) {
      if (bound.classNode.supertype == null) {
        hasExplicitBound = false;
      }
    }
    if (hasExplicitBound) {
      sb.write(" extends ");
      bound.accept1(this, sb);
    }
  }

  void writeTypeParameters(
      List<TypeParameter> typeParameters, StringBuffer sb) {
    if (typeParameters.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (TypeParameter p in typeParameters) {
        if (!first) sb.write(", ");
        writeTypeParameter(p, sb);
        first = false;
      }
      sb.write(">");
    }
  }

  void writeStructuralParameters(
      List<StructuralParameter> typeParameters, StringBuffer sb) {
    if (typeParameters.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (StructuralParameter p in typeParameters) {
        if (!first) sb.write(", ");
        writeStructuralParameter(p, sb);
        first = false;
      }
      sb.write(">");
    }
  }

  void writeDeclarations() {
    Set<TreeNode> writtenDeclarations = new Set<TreeNode>();
    int index = 0;
    List<TreeNode> nodes = nodeNames.keys.toList();
    while (index < nodes.length) {
      for (; index < nodes.length; index++) {
        TreeNode node = nodes[index];
        writeDeclaration(node, writtenDeclarations);
      }
      nodes = nodeNames.keys.toList();
    }
  }

  void writeDeclaration(
      TreeNode? declaration, Set<TreeNode> writtenDeclarations) {
    if (declaration is Class) {
      writeClass(declaration, writtenDeclarations);
    } else if (declaration is Typedef) {
      writeTypedef(declaration, writtenDeclarations);
    } else if (declaration is ExtensionTypeDeclaration) {
      writeExtensionTypeDeclaration(declaration, writtenDeclarations);
    }
  }

  void writeDeclarationForType(
      DartType type, Set<TreeNode> writtenDeclarations) {
    if (type is InterfaceType) {
      writeClass(type.classNode, writtenDeclarations);
    } else if (type is TypedefType) {
      writeTypedef(type.typedefNode, writtenDeclarations);
    } else if (type is ExtensionType) {
      writeExtensionTypeDeclaration(
          type.extensionTypeDeclaration, writtenDeclarations);
    }
  }

  void writeClass(Class? cls, Set<TreeNode> writtenDeclarations) {
    if (cls == null || !writtenDeclarations.add(cls)) {
      return;
    }
    Supertype? supertype = cls.supertype;
    writeClass(supertype?.classNode, writtenDeclarations);
    Supertype? mixedInType = cls.mixedInType;
    writeClass(mixedInType?.classNode, writtenDeclarations);
    for (Supertype implementedType in cls.implementedTypes) {
      writeClass(implementedType.classNode, writtenDeclarations);
    }

    StringBuffer sb = new StringBuffer();
    sb.write("class ");
    sb.write(computeName(cls));
    writeTypeParameters(cls.typeParameters, sb);
    if (supertype != null) {
      sb.write(" extends ");
      supertype.asInterfaceType.accept1(this, sb);
    }
    if (mixedInType != null) {
      sb.write(" with ");
      mixedInType.asInterfaceType.accept1(this, sb);
    }
    bool first = true;
    for (Supertype implementedType in cls.implementedTypes) {
      if (first) {
        sb.write(" implements ");
      } else {
        sb.write(", ");
      }
      implementedType.asInterfaceType.accept1(this, sb);
      first = false;
    }
    Procedure? callOperator;
    for (Procedure procedure in cls.procedures) {
      if (procedure.name.text == "call") {
        callOperator = procedure;
      }
    }
    if (callOperator != null) {
      sb.write("{ ");
      callOperator.function
          .computeFunctionType(cls.enclosingLibrary.nonNullable)
          .accept1(this, sb);
      sb.write(" }");
    } else {
      sb.write(";");
    }
    declarations.add("$sb");
  }

  void writeTypedef(Typedef? typedefNode, Set<TreeNode> writtenDeclarations) {
    if (typedefNode == null || !writtenDeclarations.add(typedefNode)) {
      return;
    }
    DartType? rhsType = typedefNode.type;
    if (rhsType != null) {
      writeDeclarationForType(rhsType, writtenDeclarations);
    }

    StringBuffer sb = new StringBuffer();
    sb.write("typedef ");
    sb.write(computeName(typedefNode));
    writeTypeParameters(typedefNode.typeParameters, sb);
    sb.write(" ");
    rhsType?.accept1(this, sb);
    sb.write(";");
    declarations.add("$sb");
  }

  void writeExtensionTypeDeclaration(
      ExtensionTypeDeclaration? extensionTypeDeclaration,
      Set<TreeNode> writtenDeclarations) {
    if (extensionTypeDeclaration == null ||
        !writtenDeclarations.add(extensionTypeDeclaration)) {
      return;
    }
    writeDeclarationForType(extensionTypeDeclaration.declaredRepresentationType,
        writtenDeclarations);
    for (TypeDeclarationType implementedType
        in extensionTypeDeclaration.implements) {
      writeDeclaration(implementedType.typeDeclaration, writtenDeclarations);
    }

    StringBuffer sb = new StringBuffer();
    sb.write("extension type ");
    sb.write(computeName(extensionTypeDeclaration));
    writeTypeParameters(extensionTypeDeclaration.typeParameters, sb);
    sb.write("(");
    extensionTypeDeclaration.declaredRepresentationType.accept1(this, sb);
    sb.write(" it)");
    bool first = true;
    for (TypeDeclarationType implementedType
        in extensionTypeDeclaration.implements) {
      if (first) {
        sb.write(" implements ");
      } else {
        sb.write(", ");
      }
      implementedType.accept1(this, sb);
      first = false;
    }
    sb.write(";");
    declarations.add("$sb");
  }

  String computeName(TreeNode node) {
    String? name = nodeNames[node];
    if (name != null) return name;
    if (node
        case Class(:var name, :var enclosingLibrary) ||
            Typedef(:var name, :var enclosingLibrary) ||
            ExtensionTypeDeclaration(:var name, :var enclosingLibrary)) {
      Library library = enclosingLibrary;
      String uriString = "${library.importUri}";
      if (uriString == "dart:core" || uriString == "dart:async") {
        if (!usedNames.add(name)) {
          throw "Class name conflict for $node";
        }
        return nodeNames[node] = name;
      }
    }
    while (!usedNames.add(name = names.current)) {
      names.moveNext();
    }
    names.moveNext();
    return nodeNames[node] = name;
  }

  String computeStructuralParameterName(StructuralParameter node) {
    String? name = structuralParameterNames[node];
    if (name != null) return name;
    while (!usedNames.add(name = names.current)) {
      names.moveNext();
    }
    names.moveNext();
    return structuralParameterNames[node] = name;
  }

  void writeNullability(Nullability nullability, StringBuffer sb) {
    switch (nullability) {
      case Nullability.nullable:
        sb.write("?");
        break;
      case Nullability.undetermined:
        sb.write("%");
        break;
      case Nullability.nonNullable:
        break;
    }
  }

  @override
  void visitAuxiliaryType(AuxiliaryType node, StringBuffer sb) {
    if (node is UnknownType) {
      sb.write("?");
    } else {
      throw "Unsupported auxiliary type ${node} (${node.runtimeType}).";
    }
  }

  @override
  void visitInvalidType(InvalidType node, StringBuffer sb) {
    throw "not implemented";
  }

  @override
  void visitDynamicType(DynamicType node, StringBuffer sb) {
    sb.write("dynamic");
  }

  @override
  void visitVoidType(VoidType node, StringBuffer sb) {
    sb.write("void");
  }

  @override
  void visitNeverType(NeverType node, StringBuffer sb) {
    sb.write("Never");
    writeNullability(node.nullability, sb);
  }

  @override
  void visitNullType(NullType node, StringBuffer sb) {
    sb.write("Null");
  }

  @override
  void visitInterfaceType(InterfaceType node, StringBuffer sb) {
    Class cls = node.classNode;
    sb.write(computeName(cls));
    if (node.typeArguments.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (DartType type in node.typeArguments) {
        if (!first) sb.write(", ");
        type.accept1(this, sb);
        first = false;
      }
      sb.write(">");
    }
    Uri clsImportUri = cls.enclosingLibrary.importUri;
    bool isNull = cls.name == "Null" &&
        clsImportUri.isScheme("dart") &&
        clsImportUri.path == "core";
    if (!isNull) {
      writeNullability(node.nullability, sb);
    }
  }

  @override
  void visitFutureOrType(FutureOrType node, StringBuffer sb) {
    sb.write("FutureOr<");
    node.typeArgument.accept1(this, sb);
    sb.write(">");
    writeNullability(node.declaredNullability, sb);
  }

  @override
  void visitFunctionType(FunctionType node, StringBuffer sb) {
    writeStructuralParameters(node.typeParameters, sb);
    sb.write("(");
    bool first = true;
    for (int i = 0; i < node.requiredParameterCount; i++) {
      if (!first) sb.write(", ");
      node.positionalParameters[i].accept1(this, sb);
      first = false;
    }
    if (node.requiredParameterCount != node.positionalParameters.length) {
      if (!first) sb.write(", ");
      sb.write("[");
      first = true;
      for (int i = node.requiredParameterCount;
          i < node.positionalParameters.length;
          i++) {
        if (!first) sb.write(", ");
        node.positionalParameters[i].accept1(this, sb);
        first = false;
      }
      sb.write("]");
      first = false;
    }
    if (node.namedParameters.isNotEmpty) {
      if (!first) sb.write(", ");
      sb.write("{");
      first = true;
      for (NamedType named in node.namedParameters) {
        if (!first) sb.write(", ");
        named.type.accept1(this, sb);
        sb.write(" ");
        sb.write(named.name);
        first = false;
      }
      sb.write("}");
      first = false;
    }
    sb.write(") ->");
    writeNullability(node.nullability, sb);
    sb.write(" ");
    node.returnType.accept1(this, sb);
  }

  @override
  void visitRecordType(RecordType node, StringBuffer sb) {
    sb.write("(");
    bool first = true;
    for (int i = 0; i < node.positional.length; i++) {
      if (!first) sb.write(", ");
      node.positional[i].accept1(this, sb);
      first = false;
    }
    if (node.named.isNotEmpty) {
      if (!first) sb.write(", ");
      sb.write("{");
      first = true;
      for (NamedType named in node.named) {
        if (!first) sb.write(", ");
        named.type.accept1(this, sb);
        sb.write(" ");
        sb.write(named.name);
        first = false;
      }
      sb.write("}");
      first = false;
    }
    sb.write(")");
    writeNullability(node.nullability, sb);
  }

  @override
  void visitTypeParameterType(TypeParameterType node, StringBuffer sb) {
    String name = computeName(node.parameter);
    usedTypeParameters.add(node.parameter);
    sb.write(name);
    writeNullability(node.nullability, sb);
  }

  @override
  void visitStructuralParameterType(
      StructuralParameterType node, StringBuffer sb) {
    String name = computeStructuralParameterName(node.parameter);
    usedStructuralParameters.add(node.parameter);
    sb.write(name);
    writeNullability(node.nullability, sb);
  }

  @override
  void visitIntersectionType(IntersectionType node, StringBuffer sb) {
    node.left.accept1(this, sb);
    sb.write(" & ");
    node.right.accept1(this, sb);
  }

  @override
  void visitTypedefType(TypedefType node, StringBuffer sb) {
    Typedef typedefNode = node.typedefNode;
    sb.write(computeName(typedefNode));
    if (node.typeArguments.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (DartType type in node.typeArguments) {
        if (!first) sb.write(", ");
        type.accept1(this, sb);
        first = false;
      }
      sb.write(">");
    }
    Uri clsImportUri = typedefNode.enclosingLibrary.importUri;
    bool isNull = typedefNode.name == "Null" &&
        clsImportUri.isScheme("dart") &&
        clsImportUri.path == "core";
    if (!isNull) {
      writeNullability(node.nullability, sb);
    }
  }

  @override
  void visitExtensionType(ExtensionType node, StringBuffer sb) {
    ExtensionTypeDeclaration extensionTypeDeclaration =
        node.extensionTypeDeclaration;
    sb.write(computeName(extensionTypeDeclaration));
    if (node.typeArguments.isNotEmpty) {
      sb.write("<");
      bool first = true;
      for (DartType type in node.typeArguments) {
        if (!first) sb.write(", ");
        type.accept1(this, sb);
        first = false;
      }
      sb.write(">");
    }
    Uri clsImportUri = extensionTypeDeclaration.enclosingLibrary.importUri;
    bool isNull = extensionTypeDeclaration.name == "Null" &&
        clsImportUri.isScheme("dart") &&
        clsImportUri.path == "core";
    if (!isNull) {
      writeNullability(node.nullability, sb);
    }
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "classes": declarations,
      "checks": checks,
    };
  }

  static void writeTypeChecks(String filename, List<Object> typeChecks) {
    new File(filename)
        .writeAsString(new BenchMaker().serializeTypeChecks(typeChecks));
  }
}
