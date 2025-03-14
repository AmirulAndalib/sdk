// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

main() {
  var sc;
  var i = 0;
  void send() {
    if (i == 5) {
      sc.close();
    } else {
      sc.add(i++);
    }
  }

  sc = new StreamController<int>(onListen: send, onResume: send);

  f(Stream<int> s) async {
    var r = 0;
    await for (var i in s) {
      r += await new Future.delayed(new Duration(milliseconds: 10), () => i);
    }
    return r;
  }

  asyncStart();
  f(sc.stream).then((v) {
    Expect.equals(10, v);
    asyncEnd();
  });
}
