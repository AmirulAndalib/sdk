// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart test program for testing that isolates can spawn other isolates and
// that the nested isolates can communicate with the main once the spawner has
// disappeared.

library NestedSpawn2Test;

import 'dart:isolate';
import 'package:expect/async_helper.dart';
import 'package:expect/expect.dart';

void isolateA(SendPort init) {
  ReceivePort port = new ReceivePort();
  init.send(port.sendPort);
  port.first.then((message) {
    Expect.equals(message[0], "launch nested!");
    SendPort replyTo = message[1];
    Isolate.spawn(isolateB, replyTo);
  });
}

String msg0 = "0 there?";
String msg1 = "1 Yes.";
String msg2 = "2 great. Think the other one is already dead?";
String msg3 = "3 Give him some time.";
String msg4 = "4 now?";
String msg5 = "5 Now.";
String msg6 = "6 Great. Bye";

void _call(SendPort p, msg, void onreceive(m, replyTo)) {
  final replyTo = new ReceivePort();
  p.send([msg, replyTo.sendPort]);
  replyTo.first.then((m) {
    onreceive(m[0], m[1]);
  });
}

void isolateB(SendPort mainPort) {
  // Do a little ping-pong dance to give the intermediate isolate
  // time to die.
  _call(mainPort, msg0, ((msg, replyTo) {
    Expect.equals(msg[0], "1");
    _call(replyTo, msg2, ((msg, replyTo) {
      Expect.equals(msg[0], "3");
      _call(replyTo, msg4, ((msg, replyTo) {
        Expect.equals(msg[0], "5");
        replyTo.send([msg6, null]);
      }));
    }));
  }));
}

void main([args, port]) {
  // spawned isolate can spawn other isolates
  ReceivePort init = new ReceivePort();
  Isolate.spawn(isolateA, init.sendPort);
  asyncStart();
  init.first.then((port) {
    _call(port, "launch nested!", (msg, replyTo) {
      Expect.equals(msg[0], "0");
      _call(replyTo, msg1, (msg, replyTo) {
        Expect.equals(msg[0], "2");
        _call(replyTo, msg3, (msg, replyTo) {
          Expect.equals(msg[0], "4");
          _call(replyTo, msg5, (msg, _) {
            Expect.equals(msg[0], "6");
            asyncEnd();
          });
        });
      });
    });
  });
}
