// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Code generation for the file "integration_test_methods.dart".
library;

import 'package:analyzer_utilities/tools.dart';

import 'api.dart';
import 'codegen_dart.dart';
import 'from_html.dart';
import 'to_html.dart';

final GeneratedFile target = GeneratedFile(
  'analysis_server/integration_test/support/integration_test_methods.dart',
  (pkgRoot) async {
    var visitor = CodegenInttestMethodsVisitor(
      'analysis_server',
      readApi(pkgRoot),
    );
    return visitor.collectCode(visitor.visitApi);
  },
);

/// Visitor that generates the code for integration_test_methods.dart
class CodegenInttestMethodsVisitor extends DartCodegenVisitor
    with CodeGenerator {
  /// The name of the package into which code is being generated.
  final String packageName;

  /// Visitor used to produce doc comments.
  final ToHtmlVisitor toHtmlVisitor;

  /// Code snippets concatenated to initialize all of the class fields.
  List<String> fieldInitializationCode = <String>[];

  /// Code snippets concatenated to produce the contents of the switch statement
  /// for dispatching notifications.
  List<String> notificationSwitchContents = <String>[];

  CodegenInttestMethodsVisitor(this.packageName, Api api)
    : toHtmlVisitor = ToHtmlVisitor(api),
      super(api) {
    codeGeneratorSettings.commentLineLength = 79;
    codeGeneratorSettings.docCommentStartMarker = null;
    codeGeneratorSettings.docCommentLineLeader = '/// ';
    codeGeneratorSettings.docCommentEndMarker = null;
    codeGeneratorSettings.languageName = 'dart';
  }

  /// Generate a function argument for the given parameter field.
  String formatArgument(TypeObjectField field) =>
      '${fieldDartType(field)} ${field.name}';

  /// Figures out the appropriate Dart type for data having the given API
  /// protocol [type].
  String jsonType(TypeDecl type) {
    type = resolveTypeReferenceChain(type);
    return switch (type) {
      TypeEnum() => 'String',
      TypeList() => 'List<${jsonType(type.itemType)}>',
      TypeMap() => 'Map<String, ${jsonType(type.valueType)}>',
      TypeObject() => 'Map<String, dynamic>',
      TypeReference() => switch (type.typeName) {
        // These types correspond exactly to Dart types.
        'String' || 'int' || 'bool' => type.typeName,
        'object' => 'Map<String, dynamic>',
        _ => throw Exception(type.typeName),
      },
      TypeUnion() => 'Object',
    };
  }

  @override
  void visitApi() {
    outputHeader(year: '2017');
    writeln();
    writeln('/// Convenience methods for running integration tests.');
    writeln('library;');
    writeln();
    writeln("import 'dart:async';");
    writeln();
    writeln("import 'package:$packageName/protocol/protocol_generated.dart';");
    writeln(
      "import 'package:$packageName/src/protocol/protocol_internal.dart';",
    );
    writeln(
      "import 'package:analyzer_plugin/src/utilities/client_uri_converter.dart';",
    );
    for (var uri in api.types.importUris) {
      write("import '");
      write(uri);
      writeln("';");
    }
    writeln("import 'package:path/path.dart' as path;");
    writeln("import 'package:test/test.dart';");
    writeln();
    writeln("import 'integration_tests.dart';");
    writeln("import 'protocol_matchers.dart';");
    writeln();
    writeln('/// Base implementation for running integration tests.');
    writeln('abstract class IntegrationTest {');
    indent(() {
      writeln('Server get server;');
      writeln();
      writeln(
        '/// The converter used to convert between URI/Paths in server communication.',
      );
      writeln(
        'final ClientUriConverter uriConverter = ClientUriConverter.noop(path.context);',
      );
      super.visitApi();
      writeln();
      docComment(
        toHtmlVisitor.collectHtml(() {
          toHtmlVisitor.writeln('Dispatch the notification named [event], and');
          toHtmlVisitor.writeln('containing parameters [params], to the');
          toHtmlVisitor.writeln('appropriate stream.');
        }),
      );
      writeln('void dispatchNotification(String event, params) {');
      indent(() {
        writeln('var decoder = ResponseDecoder(null);');
        writeln('switch (event) {');
        indent(() {
          write(notificationSwitchContents.join());
          writeln('default:');
          indent(() {
            writeln("fail('Unexpected notification: \$event');");
          });
        });
        writeln('}');
      });
      writeln('}');
    });
    writeln('}');
  }

  @override
  void visitNotification(Notification notification) {
    var streamName = camelJoin([
      'on',
      notification.domainName,
      notification.event,
    ]);
    var className = camelJoin([
      notification.domainName,
      notification.event,
      'params',
    ], doCapitalize: true);
    writeln();
    docComment(
      toHtmlVisitor.collectHtml(() {
        toHtmlVisitor.translateHtml(notification.html);
        toHtmlVisitor.describePayload(notification.params, 'Parameters');
      }),
    );
    writeln(
      'late final Stream<$className> $streamName = '
      '_$streamName.stream.asBroadcastStream();',
    );
    writeln();
    docComment(
      toHtmlVisitor.collectHtml(() {
        toHtmlVisitor.write('Stream controller for [$streamName].');
      }),
    );
    writeln('final _$streamName = StreamController<$className>(sync: true);');
    notificationSwitchContents.add(
      collectCode(() {
        writeln("case '${notification.longEvent}':");
        indent(() {
          var paramsValidator = camelJoin([
            'is',
            notification.domainName,
            notification.event,
            'params',
          ]);
          writeln('outOfTestExpect(params, $paramsValidator);');
          String constructorCall;
          if (notification.params == null) {
            constructorCall = '$className()';
          } else {
            constructorCall =
                "$className.fromJson(decoder, 'params', params, clientUriConverter: uriConverter)";
          }
          writeln('_$streamName.add($constructorCall);');
        });
      }),
    );
  }

  @override
  void visitRequest(Request request) {
    var methodName = camelJoin(['send', request.domainName, request.method]);
    var args = <String>[];
    var optionalArgs = <String>[];
    var params = request.params;
    if (params != null) {
      for (var field in params.fields) {
        if (field.optional) {
          optionalArgs.add(formatArgument(field));
        } else {
          args.add(formatArgument(field));
        }
      }
    }
    if (optionalArgs.isNotEmpty) {
      args.add('{${optionalArgs.join(', ')}}');
    }
    writeln();
    docComment(
      toHtmlVisitor.collectHtml(() {
        toHtmlVisitor.translateHtml(request.html);
        toHtmlVisitor.describePayload(params, 'Parameters');
        toHtmlVisitor.describePayload(request.result, 'Returns');
      }),
    );
    if (request.deprecated) {
      writeln('  // TODO(srawlins): Provide a deprecation message, or remove.');
      writeln('  // ignore: provide_deprecation_message');
      writeln('@deprecated');
    }

    String? resultClass;
    String futureClass;
    var hasResult = request.result != null;
    if (hasResult) {
      resultClass = camelJoin([
        request.domainName,
        request.method,
        'result',
      ], doCapitalize: true);
      futureClass = 'Future<$resultClass>';
    } else {
      futureClass = 'Future<void>';
    }

    writeln('$futureClass $methodName(${args.join(', ')}) async {');
    indent(() {
      var requestClass = camelJoin([
        request.domainName,
        request.method,
        'params',
      ], doCapitalize: true);
      var paramsVar = 'null';
      if (params != null) {
        paramsVar = 'params';
        var args = <String>[];
        var optionalArgs = <String>[];
        for (var field in params.fields) {
          if (field.optional) {
            optionalArgs.add('${field.name}: ${field.name}');
          } else {
            args.add(field.name);
          }
        }
        args.addAll(optionalArgs);
        writeln(
          'var params = $requestClass(${args.join(', ')}).toJson(clientUriConverter: uriConverter);',
        );
      }
      var methodJson = "'${request.longMethod}'";
      writeln('var result = await server.send($methodJson, $paramsVar);');
      if (resultClass != null) {
        var kind = 'null';
        if (requestClass == 'EditGetRefactoringParams') {
          kind = 'kind';
        }
        writeln('var decoder = ResponseDecoder($kind);');
        writeln(
          "return $resultClass.fromJson(decoder, 'result', result, clientUriConverter: uriConverter);",
        );
      } else {
        writeln('outOfTestExpect(result, isNull);');
      }
    });
    writeln('}');
  }
}
