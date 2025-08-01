// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart';

import 'util.dart';

typedef JSMethods = Map<Procedure, ({String importName, String jsCode})>;

/// Collects JS methods and adds Dart stubs to libraries.
class MethodCollector {
  final CoreTypesUtil _util;
  final JSMethods jsMethods = {};
  late Library _library;
  int _methodN = 1;

  MethodCollector(this._util);

  void enterLibrary(Library library) => _library = library;

  // We could generate something more human readable, but for now we just
  // generate something short and unique.
  String generateMethodName() => '_${_methodN++}';

  Procedure addInteropProcedure(String name, String pragmaOptionString,
      FunctionNode function, Uri fileUri, AnnotationType type,
      {required bool isExternal, Library? library}) {
    library ??= _library;
    final procedure = Procedure(
        Name(name, library), ProcedureKind.Method, function,
        isStatic: true, isExternal: isExternal, fileUri: fileUri);
    _util.annotateProcedure(procedure, pragmaOptionString, type);
    library.addProcedure(procedure);
    return procedure;
  }

  void addMethod(Procedure dartProcedure, String methodName, String code) {
    jsMethods[dartProcedure] = (importName: methodName, jsCode: code);
  }
}
