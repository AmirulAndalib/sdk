// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test merging streams.
library dart.test.stream_from_iterable;

import 'dart:async';

import 'package:expect/legacy/async_minitest.dart'; // ignore: deprecated_member_use
import 'package:expect/config.dart';

// The Stopwatch is more precise than the Timer.
// Some browsers (Firefox and IE so far) can trigger too early. So we add more
// margin.
int get safetyMargin => isWebConfiguration ? 5 : 0;

main() {
  test("stream-periodic3", () {
    Stopwatch watch = new Stopwatch()..start();
    Stream stream = new Stream.periodic(
      const Duration(milliseconds: 1),
      (x) => x,
    );
    stream
        .take(10)
        .listen(
          (_) {},
          onDone: expectAsync(() {
            int millis = watch.elapsedMilliseconds + safetyMargin;
            expect(millis, greaterThanOrEqualTo(10));
          }),
        );
  });
}
