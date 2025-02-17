// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "package:expect/async_helper.dart";
import "package:expect/expect.dart";

sumStream(Stream<int> s) async {
  int accum = 0;
  await for (var v in s) {
    accum += v;
  }
  return accum;
}

Future test() async {
  var countStreamController;
  int i = 0;
  void tick() {
    if (i < 10) {
      countStreamController.add(i);
      i++;
      scheduleMicrotask(tick);
    } else {
      countStreamController.close();
    }
  }

  countStreamController = new StreamController<int>(
    onListen: () {
      scheduleMicrotask(tick);
    },
  );
  Expect.equals(45, await sumStream(countStreamController.stream));
}

void main() {
  asyncStart();
  test().then((_) => asyncEnd());
}
