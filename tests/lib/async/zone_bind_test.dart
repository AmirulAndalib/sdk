// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/async_helper.dart';
import 'package:expect/expect.dart';
import 'dart:async';

main() {
  Completer done = new Completer();

  Expect.identical(Zone.root, Zone.current);
  // New zone, does nothing by itself.
  Zone forked = Zone.current.fork(specification: new ZoneSpecification());

  int ctr = 0;
  void expectZone([timer]) {
    Expect.identical(forked, Zone.current);
    if (timer != null) timer.cancel();
    if (++ctr == 3) {
      asyncEnd();
    }
  }

  asyncStart();
  Duration now = const Duration(seconds: 0);
  // Check that the callback is bound to the zone.
  forked.scheduleMicrotask(expectZone);
  forked.createTimer(now, expectZone);
  forked.createPeriodicTimer(now, expectZone);
}
