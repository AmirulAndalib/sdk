// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file

part of models;

abstract class StronglyReachableInstancesRepository {
  Future<InstanceSet> get(IsolateRef isolate, ClassRef cls, {int limit = 100});
  Future<Guarded<InstanceRef>> getAsArray(
    IsolateRef isolate,
    ClassRef cls, {
    bool includeSubclasses = false,
    includeImplementors = false,
  });
}
