// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Code generation for the file "AnalysisServer.java".
library;

import 'package:analyzer_utilities/tools.dart';

import 'api.dart';
import 'codegen_java.dart';

final GeneratedFile target = javaGeneratedFile(
  'analysis_server/tool/spec/generated/java/AnalysisServer.java',
  (Api api) => CodegenAnalysisServer(api),
);

class CodegenAnalysisServer extends CodegenJavaVisitor {
  CodegenAnalysisServer(super.api);

  @override
  void visitApi() {
    outputHeader(javaStyle: true);
    writeln('package com.google.dart.server.generated;');
    writeln();
    writeln('import com.google.dart.server.*;');
    writeln('import org.dartlang.analysis.server.protocol.*;');
    writeln();
    writeln('import java.util.List;');
    writeln('import java.util.Map;');
    writeln();
    writeln('''/**
 * The interface {@code AnalysisServer} defines the behavior of objects that interface to an
 * analysis server.
 *
 * @coverage dart.server
 */''');
    makeClass('public interface AnalysisServer', () {
      //
      // addAnalysisServerListener(..)
      //
      publicMethod('addAnalysisServerListener', () {
        writeln('''/**
 * Add the given listener to the list of listeners that will receive notification when new
 * analysis results become available.
 *
 * @param listener the listener to be added
 */''');
        writeln(
          'public void addAnalysisServerListener(AnalysisServerListener listener);',
        );
      });

      //
      // removeAnalysisServerListener(..)
      //
      publicMethod('removeAnalysisServerListener', () {
        writeln('''/**
 * Remove the given listener from the list of listeners that will receive notification when new
   * analysis results become available.
 *
 * @param listener the listener to be removed
 */''');
        writeln(
          'public void removeAnalysisServerListener(AnalysisServerListener listener);',
        );
      });

      //
      // addRequestListener(..)
      //
      publicMethod('addRequestListener', () {
        writeln('''/**
 * Add the given listener to the list of listeners that will receive notification when
   * requests are made by an analysis server client.
 *
 * @param listener the listener to be added
 */''');
        writeln('public void addRequestListener(RequestListener listener);');
      });

      //
      // removeRequestListener(..)
      //
      publicMethod('removeRequestListener', () {
        writeln('''/**
 * Remove the given listener from the list of listeners that will receive notification when
   * requests are made by an analysis server client.
 *
 * @param listener the listener to be removed
 */''');
        writeln('public void removeRequestListener(RequestListener listener);');
      });

      //
      // addResponseListener(..)
      //
      publicMethod('addResponseListener', () {
        writeln('''/**
 * Add the given listener to the list of listeners that will receive notification when
 * responses are received by an analysis server client.
 *
 * @param listener the listener to be added
 */''');
        writeln('public void addResponseListener(ResponseListener listener);');
      });

      //
      // removeResponseListener(..)
      //
      publicMethod('removeResponseListener', () {
        writeln('''/**
 * Remove the given listener from the list of listeners that will receive notification when
   * responses are received by an analysis server client.
 *
 * @param listener the listener to be removed
 */''');
        writeln(
          'public void removeResponseListener(ResponseListener listener);',
        );
      });

      //
      // addStatusListener(..)
      //
      publicMethod('addStatusListener', () {
        writeln('''/**
 * Add the given listener to the list of listeners that will receive notification when the server
 * is not active
 *
 * @param listener the listener to be added
 */''');
        writeln(
          'public void addStatusListener(AnalysisServerStatusListener listener);',
        );
      });

      //
      // isSocketOpen()
      //
      publicMethod('isSocketOpen', () {
        writeln('''/**
 * Return {@code true} if the socket is open.
 */''');
        writeln('public boolean isSocketOpen();');
      });

      //
      // start(..)
      //
      publicMethod('start', () {
        writeln('''/**
 * Start the analysis server.
 */''');
        writeln('public void start() throws Exception;');
      });
      super.visitApi();
    });
  }

  @override
  void visitRequest(Request request) {
    var methodName = '${request.domainName}_${request.method}';
    publicMethod(methodName, () {
      docComment(
        toHtmlVisitor.collectHtml(() {
          toHtmlVisitor.write('{@code ${request.longMethod}}');
          toHtmlVisitor.translateHtml(request.html);
          toHtmlVisitor.javadocParams(request.params);
          if (request.deprecated) {
            toHtmlVisitor.p(() => toHtmlVisitor.write('@deprecated'));
          }
        }),
      );
      write('public void $methodName(');
      var arguments = <String>[];

      var params = request.params;
      if (params != null) {
        for (var field in params.fields) {
          arguments.add('${javaType(field.type)} ${javaName(field.name)}');
        }
      }

      if (request.result != null) {
        arguments.add('${consumerName(request)} consumer');
      }

      write(arguments.join(', '));
      writeln(');');
    });
  }
}
