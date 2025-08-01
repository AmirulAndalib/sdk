// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ShadowFieldTest);
  });
}

@reflectiveTest
class ShadowFieldTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.shadowField;

  Future<void> test_is_assigned() async {
    await resolveTestCode('''
class C {
  num f = 0;

  void m() {
    if (^f is int) {
      print(f.abs());
    }
    f = 0;
    print(f.abs());
  }
}
''');
    await assertNoAssist();
  }

  Future<void> test_is_noBlock_while() async {
    await resolveTestCode('''
class C {
  num f = 0;

  void m() {
    while (true)
      if (^f is int) {
        print((f as int).abs());
      }
  }
}
''');
    await assertNoAssist();
  }

  Future<void> test_is_referencedViaThis() async {
    await resolveTestCode('''
class C {
  num f = 0;

  void m() {
    if (^f is int) {
      print(this.f);
    }
  }
}
''');
    await assertHasAssist('''
class C {
  num f = 0;

  void m() {
    var f = this.f;
    if (f is int) {
      print(this.f);
    }
  }
}
''');
  }

  Future<void> test_is_simple() async {
    await resolveTestCode('''
class C {
  num f = 0;

  void m() {
    if (^f is int) {
      print((f as int).abs());
    }
  }
}
''');
    await assertHasAssist('''
class C {
  num f = 0;

  void m() {
    var f = this.f;
    if (f is int) {
      print((f as int).abs());
    }
  }
}
''');
  }

  Future<void> test_notNull() async {
    await resolveTestCode('''
class C {
  int? f;

  void m() {
    if (^f != null) {
      print(f!.abs());
    }
  }
}
''');
    await assertHasAssist('''
class C {
  int? f;

  void m() {
    var f = this.f;
    if (f != null) {
      print(f!.abs());
    }
  }
}
''');
  }

  Future<void> test_notNull_assigned() async {
    await resolveTestCode('''
class C {
  int? f;

  void m() {
    if (^f != null) {
      print(f!.abs());
    }
    f = 0;
    print(f!.abs());
  }
}
''');
    await assertNoAssist();
  }

  Future<void> test_notNull_referencedViaThis() async {
    await resolveTestCode('''
class C {
  int? f;

  void m() {
    if (^f != null) {
      print(this.f!);
    }
  }
}
''');
    await assertHasAssist('''
class C {
  int? f;

  void m() {
    var f = this.f;
    if (f != null) {
      print(this.f!);
    }
  }
}
''');
  }
}
