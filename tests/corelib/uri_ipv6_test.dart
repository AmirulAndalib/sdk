// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

void testValidIpv6Uri() {
  var path = 'http://[::1]:1234/path?query=5#now';
  var uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('::1', uri.host);
  Expect.equals(1234, uri.port);
  Expect.equals('/path', uri.path);
  Expect.equals('query=5', uri.query);
  Expect.equals('now', uri.fragment);
  Expect.equals(path, uri.toString());

  path = 'http://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:8080/index.html';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('fedc:ba98:7654:3210:fedc:ba98:7654:3210', uri.host);
  Expect.equals(8080, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals(path.toLowerCase(), uri.toString());

  path = 'http://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:80/index.html';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('fedc:ba98:7654:3210:fedc:ba98:7654:3210', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals(
    'http://[fedc:ba98:7654:3210:fedc:ba98:7654:3210]/index.html',
    uri.toString(),
  );

  path = 'https://[FEDC:BA98:7654:3210:FEDC:BA98:7654:3210]:443/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('fedc:ba98:7654:3210:fedc:ba98:7654:3210', uri.host);
  Expect.equals(443, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals(
    'https://[fedc:ba98:7654:3210:fedc:ba98:7654:3210]/index.html',
    uri.toString(),
  );

  path = 'http://[1080:0:0:0:8:800:200C:417A]/index.html';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('1080:0:0:0:8:800:200c:417a', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals(path.toLowerCase(), uri.toString());

  path = 'http://[3ffe:2a00:100:7031::1]';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('3ffe:2a00:100:7031::1', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('', uri.path);
  Expect.equals(path, uri.toString());

  path = 'http://[1080::8:800:200C:417A]/foo';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('1080::8:800:200c:417a', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('/foo', uri.path);
  Expect.equals(path.toLowerCase(), uri.toString());

  path = 'http://[::192.9.5.5]/ipng';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('::192.9.5.5', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('/ipng', uri.path);
  Expect.equals(path, uri.toString());

  path = 'http://[::FFFF:129.144.52.38]:8080/index.html';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('::ffff:129.144.52.38', uri.host);
  Expect.equals(8080, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals(path.toLowerCase(), uri.toString());

  path = 'http://[::FFFF:129.144.52.38]:80/index.html';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('::ffff:129.144.52.38', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals('http://[::ffff:129.144.52.38]/index.html', uri.toString());

  path = 'https://[::FFFF:129.144.52.38]:443/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('::ffff:129.144.52.38', uri.host);
  Expect.equals(443, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[::ffff:129.144.52.38]/index.html', uri.toString());

  path = 'http://[2010:836B:4179::836B:4179]';
  uri = Uri.parse(path);
  Expect.equals('http', uri.scheme);
  Expect.equals('2010:836b:4179::836b:4179', uri.host);
  Expect.equals(80, uri.port);
  Expect.equals('', uri.path);
  Expect.equals(path.toLowerCase(), uri.toString());

  // Checks for ZoneID in RFC 6874
  path = 'https://[fe80::a%en1]:443/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('fe80::a%25en1', uri.host);
  Expect.equals(443, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[fe80::a%25en1]/index.html', uri.toString());

  path = 'https://[fe80::a%25eE1]:443/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('fe80::a%25eE1', uri.host);
  Expect.equals(443, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[fe80::a%25eE1]/index.html', uri.toString());

  // Recognize bare '%' and transform into '%25'
  path = 'https://[fe80::a%1]:443/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('fe80::a%251', uri.host);
  Expect.equals(443, uri.port);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[fe80::a%251]/index.html', uri.toString());

  path = 'https://[ff02::5678%pvc1.3]/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('ff02::5678%25pvc1.3', uri.host);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[ff02::5678%25pvc1.3]/index.html', uri.toString());

  // ZoneID contains percent encoded
  path = 'https://[ff02::1%%321]/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('ff02::1%2521', uri.host);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[ff02::1%2521]/index.html', uri.toString());

  path = 'https://[ff02::1%321]/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('ff02::1%25321', uri.host);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[ff02::1%25321]/index.html', uri.toString());

  // Lower cases
  path = 'https://[ff02::1%1%41]/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('ff02::1%251a', uri.host);
  Expect.equals('/index.html', uri.path);
  Expect.equals('https://[ff02::1%251a]/index.html', uri.toString());

  path = 'https://[fe80::8eae:4c4d:fee9:8434%rename3]/index.html';
  uri = Uri.parse(path);
  Expect.equals('https', uri.scheme);
  Expect.equals('fe80::8eae:4c4d:fee9:8434%25rename3', uri.host);
  Expect.equals('/index.html', uri.path);
  Expect.equals(
    'https://[fe80::8eae:4c4d:fee9:8434%25rename3]/index.html',
    uri.toString(),
  );

  // Test constructors with host name
  uri = Uri(scheme: 'https', host: '[ff02::5678%pvc1.3]');
  uri = Uri(scheme: 'https', host: '[fe80::a%1]');
  uri = Uri(scheme: 'https', host: '[fe80::a%25eE1]');
  uri = Uri(scheme: 'https', host: '[fe80::a%en1]');
}

void testParseIPv6Address() {
  void pass(String host, List<int> expected) {
    Expect.listEquals(expected, Uri.parseIPv6Address(host));
  }

  void fail(String host) {
    Expect.throwsFormatException(() => Uri.parseIPv6Address(host));
  }

  pass('::127.0.0.1', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 0, 0, 1]);
  pass('0::127.0.0.1', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 127, 0, 0, 1]);
  pass('::', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  pass('0::', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  fail(':0::127.0.0.1');
  fail('0:::');
  fail(':::');
  fail('::0:');
  fail('::0::');
  fail('::0::0');
  fail('00000::0');
  fail('-1::0');
  fail('-AAA::0');
  fail('0::127.0.0.1:0');
  fail('0::127.0.0');
  pass('0::1111', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17, 17]);
  pass('2010:836B:4179::836B:4179', [
    32,
    16,
    131,
    107,
    65,
    121,
    0,
    0,
    0,
    0,
    0,
    0,
    131,
    107,
    65,
    121,
  ]);
  fail('2010:836B:4179:0000:127.0.0.1');
  fail('2010:836B:4179:0000:0000:127.0.0.1');
  fail('2010:836B:4179:0000:0000:0000::127.0.0.1');
  fail('2010:836B:4179:0000:0000:0000:0000:127.0.0.1');
  pass('2010:836B:4179:0000:0000:0000:127.0.0.1', [
    32,
    16,
    131,
    107,
    65,
    121,
    0,
    0,
    0,
    0,
    0,
    0,
    127,
    0,
    0,
    1,
  ]);
}

void testPropagateIPv6() {
  // A regression test for https://dartbug.com/55085

  // A "Normal" URI. Simple URIs cannot have IPv6 addresses.
  var ipv6Uri = Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q#f");

  // A non-IPv6 URI.
  var plainUri = Uri.parse("s2://u2:p2@host:2/p3/p4?q2#f2");

  void expectSame(Uri expected, Uri actual) {
    Expect.equals(expected, actual, "URI equality");
    Expect.equals(
      expected.toString(),
      actual.toString(),
      "URI.toString() equality",
    );
  }

  Expect.equals("s://u:p@[::127.0.0.1]:1/p1/p2?q#f", ipv6Uri.toString());
  Expect.equals("::127.0.0.1", ipv6Uri.host);
  Expect.equals("u:p", ipv6Uri.userInfo);
  Expect.equals(1, ipv6Uri.port);

  // Using resolve to change parts of an IPv6 URI.
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q#f2"),
    ipv6Uri.resolve("#f2"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q2#f2"),
    ipv6Uri.resolve("?q2#f2"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p3?q2#f2"),
    ipv6Uri.resolve("p3?q2#f2"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p3/p4?q2#f2"),
    ipv6Uri.resolve("/p3/p4?q2#f2"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p3/p4?q2#f2"),
    ipv6Uri.resolve("/p3/p4?q2#f2"),
  );
  expectSame(
    Uri.parse("s://u2:p2@192.168.0.1:2/p3/p4?q2#f2"),
    ipv6Uri.resolve("//u2:p2@192.168.0.1:2/p3/p4?q2#f2"),
  );
  expectSame(
    Uri.parse("s2://u2:p2@192.168.0.1:2/p3/p4?q2#f2"),
    ipv6Uri.resolve("s2://u2:p2@192.168.0.1:2/p3/p4?q2#f2"),
  );

  // Using resolve to change parts to an IPv6 URI.
  expectSame(
    Uri.parse("s2://u:p@[::127.0.0.1]:1/p1/p2?q#f"),
    plainUri.resolve("//u:p@[::127.0.0.1]:1/p1/p2?q#f"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q#f"),
    plainUri.resolveUri(ipv6Uri),
  );

  // Using replace to change non-host parts of an IPv6 URI.
  expectSame(
    Uri.parse("s2://u:p@[::127.0.0.1]:1/p1/p2?q#f"),
    ipv6Uri.replace(scheme: "s2"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:2/p1/p2?q#f"),
    ipv6Uri.replace(port: 2),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p3/p4?q#f"),
    ipv6Uri.replace(path: "p3/p4"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1?q#f"),
    ipv6Uri.replace(path: ""),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q2#f"),
    ipv6Uri.replace(query: "q2"),
  );
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q#f2"),
    ipv6Uri.replace(fragment: "f2"),
  );
  // Replacing the host to or from an IPv6 address.
  expectSame(
    Uri.parse("s://u:p@host:1/p1/p2?q#f"),
    ipv6Uri.replace(host: "host"),
  );
  expectSame(
    Uri.parse("s2://u2:p2@[::127.0.0.1]:2/p3/p4?q2#f2"),
    plainUri.replace(host: "[::127.0.0.1]"),
  );
  expectSame(
    Uri.parse("s2://u2:p2@[::127.0.0.1]:2/p3/p4?q2#f2"),
    plainUri.replace(host: "::127.0.0.1"),
  );

  // Removing fragment.
  expectSame(
    Uri.parse("s://u:p@[::127.0.0.1]:1/p1/p2?q"),
    ipv6Uri.removeFragment(),
  );
}

void main() {
  testValidIpv6Uri();
  testParseIPv6Address();
  testPropagateIPv6();
}
