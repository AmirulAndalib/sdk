// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library contains logic to fetch RAM utilization information.
/// It is implemented as an RPC that connects to the VM's vm_service isolate and
/// all necessary details.
///
/// This is similar to the information that the VM prints when provided the
/// `--print_metrics` flag. However, this API allows us to obtain the data
/// directly while the process is running and embedded in the compiler output
/// (and in the future in dump-info).
///
/// Note that one could alternatively use Process.maxRss instead, however that
/// number may have a lot more variability depending on system conditions.
/// Our goal with this number is not so much to be exact, but to have a good
/// metric we can track overtime and use to detect improvements and regressions.
library;

import 'dart:developer';
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

Future<int?> _currentHeapCapacity() async {
  final info = await Service.controlWebServer(
    enable: true,
    silenceOutput: true,
  );
  final vmServiceWsUri = info.serverWebSocketUri?.toString();
  if (vmServiceWsUri == null) return null;

  final vmService = await vm_service_io.vmServiceConnectUri(vmServiceWsUri);
  final vm = await vmService.getVM();

  final nonSystemIsolateGroups = vm.isolateGroups;
  final relevantSystemIsolateGroups = vm.systemIsolateGroups?.where(
    (group) => group.name?.contains('dart2js') ?? false,
  );

  var relevantMemoryUsage = 0;
  for (final group in [
    ...?nonSystemIsolateGroups,
    ...?relevantSystemIsolateGroups,
  ]) {
    final usage = await vmService.getIsolateGroupMemoryUsage(group.id!);
    relevantMemoryUsage += usage.heapCapacity ?? 0;
  }
  vmService.dispose();
  return relevantMemoryUsage;
}

Future<String?> currentHeapCapacityInMb() async {
  final capacity = await _currentHeapCapacity();
  if (capacity == null || capacity == 0) return null;
  return "${(capacity / (1024 * 1024)).toStringAsFixed(3)} MB";
}
