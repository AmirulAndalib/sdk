// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

import "package:expect/expect.dart";
import 'dart:async';
import 'package:expect/async_helper.dart';

main() {
  asyncStart();
  // Ensure that `runZonedGuarded`'s onError handles synchronous errors but
  // delegates to the next runZoned when the handler returns false.
  bool sawInnerHandler = false;
  try {
    runZonedGuarded(() {
      runZonedGuarded(() {
        throw 0;
      }, (e, s) {
        Expect.equals(0, e);
        sawInnerHandler = true;
        throw e;
      });
    }, (e, s) {
      Expect.equals(0, e);
      Expect.isTrue(sawInnerHandler);
      // If we are waiting for an error, don't asyncEnd, but let it time out.
      throw e; //# 01: ok
      asyncEnd();
    });
  } catch (e) {
    asyncEnd(); //# 01: continued
    return; //# 01: continued
    rethrow;
  }
}
