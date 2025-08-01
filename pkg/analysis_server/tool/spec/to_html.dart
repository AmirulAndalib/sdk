// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Code for displaying the API as HTML.  This is used both for generating a
/// full description of the API as a web page, and for generating doc comments
/// in generated code.
library;

import 'dart:convert';

import 'package:analyzer_utilities/html_dom.dart' as dom;
import 'package:analyzer_utilities/html_generator.dart';
import 'package:analyzer_utilities/tools.dart';

import 'api.dart';
import 'from_html.dart';

/// Embedded stylesheet
final String stylesheet =
    '''
body {
  font-family: 'Roboto', sans-serif;
  max-width: 800px;
  margin: 0 auto;
  padding: 0 16px;
  font-size: 16px;
  line-height: 1.5;
  color: #111;
  background-color: #fdfdfd;
  font-weight: 300;
  -webkit-font-smoothing: auto;
}

h2, h3, h4, h5 {
  margin-bottom: 0;
}

h2.domain {
  border-bottom: 1px solid rgb(200, 200, 200);
  margin-bottom: 0.5em;
}

h4 {
  font-size: 18px;
}

h5 {
  font-size: 16px;
}

p {
  margin-top: 0;
}

pre {
  margin: 0;
  font-family: 'Roboto Mono', monospace;
  font-size: 15px;
}

div.box {
  background-color: rgb(240, 245, 240);
  border-radius: 4px;
  padding: 4px 12px;
  margin: 16px 0;
}

div.hangingIndent {
  padding-left: 3em;
  text-indent: -3em;
}

dl dt {
  font-weight: bold;
}

dl dd {
  margin-left: 16px;
}

dt {
  margin-top: 1em;
}

dt.notification {
  font-weight: bold;
}

dt.refactoring {
  font-weight: bold;
}

dt.request {
  font-weight: bold;
}

dt.typeDefinition {
  font-weight: bold;
}

a {
  text-decoration: none;
}

a:focus, a:hover {
  text-decoration: underline;
}

.deprecated {
  text-decoration: line-through;
}

/* Styles for index */

.subindex ul {
  padding-left: 0;
  margin-left: 0;

  -webkit-margin-before: 0;
  -webkit-margin-start: 0;
  -webkit-padding-start: 0;

  list-style-type: none;
}
'''.trim();

final GeneratedFile target = GeneratedFile('analysis_server/doc/api.html', (
  pkgRoot,
) async {
  var visitor = ToHtmlVisitor(readApi(pkgRoot));
  var document = dom.Document();
  for (var node in visitor.collectHtml(visitor.visitApi)) {
    document.append(node);
  }
  return document.outerHtml;
});

String _toTitleCase(String str) {
  if (str.isEmpty) return str;
  return str.substring(0, 1).toUpperCase() + str.substring(1);
}

/// Visitor that records the mapping from HTML elements to various kinds of API
/// nodes.
class ApiMappings extends HierarchicalApiVisitor {
  Map<dom.Element, Domain> domains = <dom.Element, Domain>{};

  ApiMappings(super.api);

  @override
  void visitDomain(Domain domain) {
    domains[domain.html] = domain;
  }
}

/// Helper methods for creating HTML elements.
mixin HtmlMixin {
  void anchor(String id, void Function() callback) {
    element('a', {'name': id}, callback);
  }

  void b(void Function() callback) => element('b', {}, callback);
  void body(void Function() callback) => element('body', {}, callback);
  void box(void Function() callback) {
    element('div', {'class': 'box'}, callback);
  }

  void br() => element('br', {});
  void dd(void Function() callback) => element('dd', {}, callback);
  void dl(void Function() callback) => element('dl', {}, callback);
  void dt(String cls, void Function() callback) =>
      element('dt', {'class': cls}, callback);
  void element(
    String name,
    Map<String, String> attributes, [
    void Function() callback,
  ]);
  void gray(void Function() callback) =>
      element('span', {'style': 'color:#999999'}, callback);
  void h1(void Function() callback) => element('h1', {}, callback);
  void h2(String cls, void Function() callback) {
    return element('h2', {'class': cls}, callback);
  }

  void h3(void Function() callback) => element('h3', {}, callback);
  void h4(void Function() callback) => element('h4', {}, callback);
  void h5(void Function() callback) => element('h5', {}, callback);
  void hangingIndent(void Function() callback) =>
      element('div', {'class': 'hangingIndent'}, callback);
  void head(void Function() callback) => element('head', {}, callback);
  void html(void Function() callback) => element('html', {}, callback);
  void i(void Function() callback) => element('i', {}, callback);
  void li(void Function() callback) => element('li', {}, callback);
  void link(
    String id,
    void Function() callback, [
    Map<String, String>? attributes,
  ]) {
    attributes ??= {};
    attributes['href'] = '#$id';
    element('a', attributes, callback);
  }

  void p(void Function() callback) => element('p', {}, callback);
  void pre(void Function() callback) => element('pre', {}, callback);
  void span(String cls, void Function() callback) =>
      element('span', {'class': cls}, callback);
  void title(void Function() callback) => element('title', {}, callback);
  void tt(void Function() callback) => element('tt', {}, callback);
  void ul(void Function() callback) => element('ul', {}, callback);
}

/// Visitor that generates HTML documentation of the API.
class ToHtmlVisitor extends HierarchicalApiVisitor
    with HtmlMixin, HtmlGenerator {
  /// Set of types defined in the API.
  Set<String> definedTypes = <String>{};

  /// Mappings from HTML elements to API nodes.
  ApiMappings apiMappings;

  ToHtmlVisitor(super.api) : apiMappings = ApiMappings(api) {
    apiMappings.visitApi();
  }

  /// Describe the payload of request, response, notification, refactoring
  /// feedback, or refactoring options.
  ///
  /// If [force] is true, then a section is inserted even if the payload is
  /// null.
  void describePayload(TypeObject? subType, String name, {bool force = false}) {
    if (force || subType != null) {
      h4(() {
        write(name);
      });
      if (subType == null) {
        p(() {
          write('none');
        });
      } else {
        visitTypeDecl(subType);
      }
    }
  }

  void generateDomainIndex(Domain domain) {
    h4(() {
      write(domain.name);
      write(' (');
      link('domain_${domain.name}', () => write('\u2191'));
      write(')');
    });
    if (domain.requests.isNotEmpty) {
      element('div', {'class': 'subindex'}, () {
        generateRequestsIndex(domain.requests);
        if (domain.notifications.isNotEmpty) {
          generateNotificationsIndex(domain.notifications);
        }
      });
    } else if (domain.notifications.isNotEmpty) {
      element('div', {'class': 'subindex'}, () {
        generateNotificationsIndex(domain.notifications);
      });
    }
  }

  void generateDomainsHeader() {
    h1(() {
      write('Domains');
    });
  }

  void generateIndex() {
    h3(() => write('Domains'));
    for (var domain in api.domains) {
      if (domain.experimental ||
          (domain.requests.isEmpty && domain.notifications.isEmpty)) {
        continue;
      }
      generateDomainIndex(domain);
    }

    generateTypesIndex(definedTypes);
    generateRefactoringsIndex(api.refactorings);
  }

  void generateNotificationsIndex(Iterable<Notification> notifications) {
    h5(() => write('Notifications'));
    element('div', {'class': 'subindex'}, () {
      element('ul', {}, () {
        for (var notification in notifications) {
          element(
            'li',
            {},
            () => link(
              'notification_${notification.longEvent}',
              () => write(notification.event),
            ),
          );
        }
      });
    });
  }

  void generateRefactoringsIndex(Iterable<Refactoring> refactorings) {
    h3(() {
      write('Refactorings');
      write(' (');
      link('refactorings', () => write('\u2191'));
      write(')');
    });
    // TODO(paulberry): Individual refactorings are not yet hyperlinked.
    element('div', {'class': 'subindex'}, () {
      element('ul', {}, () {
        for (var refactoring in refactorings) {
          element(
            'li',
            {},
            () => link(
              'refactoring_${refactoring.kind}',
              () => write(refactoring.kind),
            ),
          );
        }
      });
    });
  }

  void generateRequestsIndex(Iterable<Request> requests) {
    h5(() => write('Requests'));
    element('ul', {}, () {
      for (var request in requests) {
        if (!request.experimental) {
          element(
            'li',
            {},
            () => link(
              'request_${request.longMethod}',
              () => write(request.method),
            ),
          );
        }
      }
    });
  }

  void generateTableOfContents() {
    for (var domain in api.domains.where((domain) => !domain.experimental)) {
      if (domain.experimental) continue;

      writeln();

      p(() {
        link('domain_${domain.name}', () {
          write(_toTitleCase(domain.name));
        });
      });

      ul(() {
        for (var request in domain.requests) {
          if (request.experimental) continue;

          li(() {
            link(
              'request_${request.longMethod}',
              () {
                write(request.longMethod);
              },
              request.deprecated ? {'class': 'deprecated'} : null,
            );
          });
          writeln();
        }
      });

      writeln();
    }
  }

  void generateTypesIndex(Set<String> types) {
    h3(() {
      write('Types');
      write(' (');
      link('types', () => write('\u2191'));
      write(')');
    });
    var sortedTypes = types.toList();
    sortedTypes.sort();
    element('div', {'class': 'subindex'}, () {
      element('ul', {}, () {
        for (var type in sortedTypes) {
          element('li', {}, () => link('type_$type', () => write(type)));
        }
      });
    });
  }

  void javadocParams(TypeObject? typeObject) {
    if (typeObject != null) {
      for (var field in typeObject.fields) {
        hangingIndent(() {
          write('@param ${field.name} ');
          translateHtml(field.html, squashParagraphs: true);
        });
      }
    }
  }

  /// Generate a description of [type] using [TypeVisitor].
  ///
  /// If [shortDesc] is non-null, the output is prefixed with this string
  /// and a colon.
  ///
  /// If [typeForBolding] is supplied, then fields in this type are shown in
  /// boldface.
  void showType(
    String? shortDesc,
    TypeDecl type, [
    TypeObject? typeForBolding,
  ]) {
    var fieldsToBold = <String>{};
    if (typeForBolding != null) {
      for (var field in typeForBolding.fields) {
        fieldsToBold.add(field.name);
      }
    }
    pre(() {
      if (shortDesc != null) {
        write('$shortDesc: ');
      }
      var typeVisitor = TypeVisitor(api, fieldsToBold: fieldsToBold);
      addAll(
        typeVisitor.collectHtml(() {
          typeVisitor.visitTypeDecl(type);
        }),
      );
    });
  }

  /// Copy the contents of the given HTML element, translating the special
  /// elements that define the API appropriately.
  void translateHtml(dom.Element? html, {bool squashParagraphs = false}) {
    if (html == null) {
      return;
    }
    for (var node in html.nodes) {
      if (node is dom.Element) {
        var localName = node.name;
        if (squashParagraphs && localName == 'p') {
          translateHtml(node, squashParagraphs: squashParagraphs);
          continue;
        }
        switch (localName) {
          case 'domains':
            generateDomainsHeader();
          case 'domain':
            visitDomain(apiMappings.domains[node]!);
          case 'head':
            head(() {
              translateHtml(node, squashParagraphs: squashParagraphs);
              element('link', {
                'rel': 'stylesheet',
                'href':
                    'https://fonts.googleapis.com/css2?family=Roboto+Mono:wght@300;400;700&family=Roboto:ital,wght@0,300;0,400;0,700;1,400&display=swap',
                'type': 'text/css',
              });
              element('style', {}, () {
                writeln(stylesheet);
              });
            });
          case 'refactorings':
            visitRefactorings(api.refactorings);
          case 'types':
            visitTypes(api.types);
          case 'version':
            translateHtml(node, squashParagraphs: squashParagraphs);
          case 'toc':
            generateTableOfContents();
          case 'index':
            generateIndex();
          default:
            if (!ApiReader.specialElements.contains(localName)) {
              element(localName, node.attributes, () {
                translateHtml(node, squashParagraphs: squashParagraphs);
              });
            }
        }
      } else if (node is dom.Text) {
        var text = node.textRemoveTags;
        write(text);
      }
    }
  }

  @override
  void visitApi() {
    var apiTypes = api.types.where((TypeDefinition td) => !td.experimental);
    definedTypes = apiTypes.map((TypeDefinition td) => td.name).toSet();

    html(() {
      translateHtml(api.html);
    });
  }

  @override
  void visitDomain(Domain domain) {
    if (domain.experimental) {
      return;
    }
    h2('domain', () {
      anchor('domain_${domain.name}', () {
        write('${domain.name} domain');
      });
    });
    translateHtml(domain.html);
    if (domain.requests.isNotEmpty) {
      h3(() {
        write('Requests');
      });
      dl(() {
        domain.requests.forEach(visitRequest);
      });
    }
    if (domain.notifications.isNotEmpty) {
      h3(() {
        write('Notifications');
      });
      dl(() {
        domain.notifications.forEach(visitNotification);
      });
    }
  }

  @override
  void visitNotification(Notification notification) {
    if (notification.experimental) {
      return;
    }
    dt('notification', () {
      anchor('notification_${notification.longEvent}', () {
        write(notification.longEvent);
      });
    });
    dd(() {
      box(() {
        showType(
          'notification',
          notification.notificationType,
          notification.params,
        );
      });
      translateHtml(notification.html);
      describePayload(notification.params, 'parameters:');
    });
  }

  @override
  void visitRefactoring(Refactoring refactoring) {
    dt('refactoring', () {
      write(refactoring.kind);
    });
    dd(() {
      translateHtml(refactoring.html);
      describePayload(refactoring.feedback, 'Feedback:', force: true);
      describePayload(refactoring.options, 'Options:', force: true);
    });
  }

  @override
  void visitRefactorings(Refactorings refactorings) {
    translateHtml(refactorings.html);
    dl(() {
      super.visitRefactorings(refactorings);
    });
  }

  @override
  void visitRequest(Request request) {
    if (request.experimental) {
      return;
    }
    dt(request.deprecated ? 'request deprecated' : 'request', () {
      anchor('request_${request.longMethod}', () {
        write(request.longMethod);
      });
    });
    dd(() {
      box(() {
        showType('request', request.requestType, request.params);
        br();
        showType('response', request.responseType, request.result);
      });
      translateHtml(request.html);
      describePayload(request.params, 'parameters:');
      describePayload(request.result, 'returns:');
    });
  }

  @override
  void visitTypeDefinition(TypeDefinition typeDefinition) {
    if (typeDefinition.experimental) {
      return;
    }
    dt(
      typeDefinition.deprecated
          ? 'typeDefinition deprecated'
          : 'typeDefinition',
      () {
        anchor('type_${typeDefinition.name}', () {
          write('${typeDefinition.name}: ');
          var typeVisitor = TypeVisitor(api, short: true);
          addAll(
            typeVisitor.collectHtml(() {
              typeVisitor.visitTypeDecl(typeDefinition.type);
            }),
          );
        });
      },
    );
    dd(() {
      translateHtml(typeDefinition.html);
      visitTypeDecl(typeDefinition.type);
    });
  }

  @override
  void visitTypeEnum(TypeEnum typeEnum) {
    dl(() {
      super.visitTypeEnum(typeEnum);
    });
  }

  @override
  void visitTypeEnumValue(TypeEnumValue typeEnumValue) {
    var isDocumented = false;
    for (var node in typeEnumValue.html.nodes) {
      if ((node is dom.Element && node.name != 'code') ||
          (node is dom.Text && node.text.trim().isNotEmpty)) {
        isDocumented = true;
        break;
      }
    }
    dt(typeEnumValue.deprecated ? 'value deprecated' : 'value', () {
      write(typeEnumValue.value);
    });
    if (isDocumented) {
      dd(() {
        translateHtml(typeEnumValue.html);
      });
    }
  }

  @override
  void visitTypeList(TypeList typeList) {
    visitTypeDecl(typeList.itemType);
  }

  @override
  void visitTypeMap(TypeMap typeMap) {
    visitTypeDecl(typeMap.valueType);
  }

  @override
  void visitTypeObject(TypeObject typeObject) {
    dl(() {
      super.visitTypeObject(typeObject);
    });
  }

  @override
  void visitTypeObjectField(TypeObjectField typeObjectField) {
    if (typeObjectField.experimental) {
      return;
    }
    dt('field', () {
      b(() {
        if (typeObjectField.deprecated) {
          span('deprecated', () {
            write(typeObjectField.name);
          });
        } else {
          write(typeObjectField.name);
        }
        if (typeObjectField.value != null) {
          write(' = ${json.encode(typeObjectField.value)}');
        } else {
          write(': ');
          var typeVisitor = TypeVisitor(api, short: true);
          addAll(
            typeVisitor.collectHtml(() {
              typeVisitor.visitTypeDecl(typeObjectField.type);
            }),
          );
          if (typeObjectField.optional) {
            gray(() => write(' (optional)'));
          }
        }
      });
    });
    dd(() {
      translateHtml(typeObjectField.html);
    });
  }

  @override
  void visitTypeReference(TypeReference typeReference) {}

  @override
  void visitTypes(Types types) {
    translateHtml(types.html);
    dl(() {
      var sortedTypes = types.toList();
      sortedTypes.sort(
        (TypeDefinition first, TypeDefinition second) =>
            first.name.compareTo(second.name),
      );
      sortedTypes.forEach(visitTypeDefinition);
    });
  }
}

/// Visitor that generates a compact representation of a type, such as:
///
/// {
///   "id": String
///   "error": optional Error
///   "result": {
///     "version": String
///   }
/// }
class TypeVisitor extends HierarchicalApiVisitor
    with HtmlMixin, HtmlCodeGenerator {
  /// Set of fields which should be shown in boldface.
  final Set<String> fieldsToBold;

  /// True if a short description should be generated.  In a short description,
  /// objects are shown as simply "object", and enums are shown as "String".
  final bool short;

  TypeVisitor(super.api, {this.fieldsToBold = const {}, this.short = false});

  @override
  void visitTypeEnum(TypeEnum typeEnum) {
    if (short) {
      write('String');
      return;
    }
    writeln('enum {');
    indent(() {
      for (var value in typeEnum.values) {
        writeln(value.value);
      }
    });
    write('}');
  }

  @override
  void visitTypeList(TypeList typeList) {
    write('List<');
    visitTypeDecl(typeList.itemType);
    write('>');
  }

  @override
  void visitTypeMap(TypeMap typeMap) {
    write('Map<');
    visitTypeDecl(typeMap.keyType);
    write(', ');
    visitTypeDecl(typeMap.valueType);
    write('>');
  }

  @override
  void visitTypeObject(TypeObject typeObject) {
    if (short) {
      write('object');
      return;
    }
    writeln('{');
    indent(() {
      for (var field in typeObject.fields) {
        if (field.experimental) continue;
        write('"');
        if (fieldsToBold.contains(field.name)) {
          b(() {
            write(field.name);
          });
        } else {
          write(field.name);
        }
        write('": ');
        if (field.value != null) {
          write(json.encode(field.value));
        } else {
          if (field.optional) {
            gray(() {
              write('optional');
            });
            write(' ');
          }
          visitTypeDecl(field.type);
        }
        writeln();
      }
    });
    write('}');
  }

  @override
  void visitTypeReference(TypeReference typeReference) {
    var displayName = typeReference.typeName;
    if (api.types.containsKey(typeReference.typeName)) {
      link('type_${typeReference.typeName}', () {
        write(displayName);
      });
    } else {
      write(displayName);
    }
  }

  @override
  void visitTypeUnion(TypeUnion typeUnion) {
    var verticalBarNeeded = false;
    for (var choice in typeUnion.choices) {
      if (verticalBarNeeded) {
        write(' | ');
      }
      visitTypeDecl(choice);
      verticalBarNeeded = true;
    }
  }
}
