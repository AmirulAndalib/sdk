// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dap/dap.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart' as vm;

import '../utils.dart';
import 'dart.dart';
import 'mixins.dart';

/// A DAP Debug Adapter for running and debugging Dart CLI scripts.
class DartCliDebugAdapter extends DartDebugAdapter<DartLaunchRequestArguments,
        DartAttachRequestArguments>
    with PidTracker, VmServiceInfoFileUtils, PackageConfigUtils {
  Process? _process;

  @override
  final parseLaunchArgs = DartLaunchRequestArguments.fromJson;

  @override
  final parseAttachArgs = DartAttachRequestArguments.fromJson;

  DartCliDebugAdapter(
    super.channel, {
    super.ipv6,
    super.logger,
    super.onError,
  });

  /// Whether the VM Service closing should be used as a signal to terminate the
  /// debug session.
  ///
  /// If we have a process, we will instead use its termination as a signal to
  /// terminate the debug session. Otherwise, we will use the VM Service close.
  @override
  bool get terminateOnVmServiceClose => _process == null;

  @override
  Future<void> debuggerConnected(vm.VM vmInfo) async {
    if (!isAttach) {
      // Capture the PID from the VM Service so that we can terminate it when
      // cleaning up. Terminating the process might not be enough as it could be
      // just a shell script (e.g. pub on Windows) and may not pass the
      // signal on correctly.
      // See: https://github.com/Dart-Code/Dart-Code/issues/907
      final pid = vmInfo.pid;
      if (pid != null) {
        pidsToTerminate.add(pid);
      }
    }
  }

  /// Called by [disconnectRequest] to request that we forcefully shut down the
  /// app being run (or in the case of an attach, disconnect).
  @override
  Future<void> disconnectImpl() async {
    if (isAttach) {
      await handleDetach();
    }
    terminatePids(ProcessSignal.sigkill);
  }

  @override
  Future<void> launchImpl() {
    throw UnsupportedError(
      'Calling launchImpl() for DartCliDebugAdapter is unsupported. '
      'Call launchAndRespond() instead.',
    );
  }

  /// Called by [launchRequest] to request that we actually start the app to be
  /// run/debugged.
  ///
  /// For debugging, this should start paused, connect to the VM Service, set
  /// breakpoints, and resume.
  @override
  Future<void> launchAndRespond(void Function() sendResponse) async {
    final args = this.args as DartLaunchRequestArguments;
    File? vmServiceInfoFile;

    final debug = !(args.noDebug ?? false);
    if (debug) {
      final progress = startProgressNotification(
        "launch",
        "Debugger",
        message: "Starting…",
      );
      vmServiceInfoFile = generateVmServiceInfoFile();
      unawaited(
        waitForVmServiceInfoFile(logger, vmServiceInfoFile).then((uri) async {
          progress.update(message: "Connecting…");
          await connectDebugger(uri);
          progress.end();
        }),
      );
    }

    final vmArgs = <String>[
      ...?args.vmAdditionalArgs,
      '--no-serve-devtools',
      if (debug) ...[
        '--enable-vm-service=${args.vmServicePort ?? 0}${ipv6 ? '/::1' : ''}',
      ],
      if (debug && vmServiceInfoFile != null) ...[
        '-DSILENT_VM_SERVICE=true',
        '--write-service-info=${Uri.file(vmServiceInfoFile.path)}'
      ],
    ];

    final toolArgs = args.toolArgs ?? [];
    if (debug) {
      // If the user has explicitly set pause-isolates-on-exit we need to
      // not add it ourselves, and specify that we didn't set it.
      if (containsVmFlag(toolArgs, '--pause_isolates_on_exit')) {
        pauseIsolatesOnExitSetByDap = false;
      } else {
        vmArgs.add('--pause_isolates_on_exit');
      }

      // If the user has explicitly set pause-isolates-on-start we need to
      // not add it ourselves, and specify that we didn't set it.
      if (containsVmFlag(toolArgs, '--pause_isolates_on_start')) {
        pauseIsolatesOnStartSetByDap = false;
      } else {
        vmArgs.add('--pause_isolates_on_start');
      }
    }

    // Handle customTool and deletion of any arguments for it.
    final executable = normalizePath(
      args.customTool ?? Platform.resolvedExecutable,
    );
    final removeArgs = args.customToolReplacesArgs;
    if (args.customTool != null && removeArgs != null) {
      vmArgs.removeRange(0, math.min(removeArgs, vmArgs.length));
    }

    final processArgs = [
      ...vmArgs,
      ...toolArgs,
      normalizePath(args.program),
      ...?args.args,
    ];

    // If the client supports runInTerminal and args.console is set to either
    // 'terminal' or 'runInTerminal' we won't run the process ourselves, but
    // instead call the client to run it for us (this allows it to run in a
    // terminal where the user can interact with `stdin`).
    final canRunInTerminal =
        initializeArgs?.supportsRunInTerminalRequest ?? false;

    // The terminal kinds used by DAP are 'integrated' and 'external'.
    final terminalKind = canRunInTerminal
        ? args.console == 'terminal'
            ? 'integrated'
            : args.console == 'externalTerminal'
                ? 'external'
                : null
        : null;

    var cwd = args.cwd;
    if (cwd != null) {
      cwd = normalizePath(cwd);
    }

    if (terminalKind != null) {
      // When running in the terminal, we want to respond to launchRequest()
      // before we ask to run in the terminal, because otherwise VS Code might
      // show the Debug Console (as part of the debug session starting) right
      // after showing the terminal. Since in terminal mode all output is going
      // to terminal (and the user likely picked this non-default mode so they
      // can type into `stdin`), we want the terminal to be shown last (and kept
      // visible).
      //
      // See https://github.com/Dart-Code/Dart-Code/issues/4287
      //
      // The implementation of `launchInEditorTerminal` already has
      // `try`/`catch` around launching and will print any errors and terminate
      // if appropriate.
      sendResponse();
      await launchInEditorTerminal(
        debug,
        terminalKind,
        executable,
        processArgs,
        workingDirectory: cwd,
        env: args.env,
      );
    } else {
      await launchAsProcess(
        executable,
        processArgs,
        workingDirectory: cwd,
        env: args.env,
      );
      sendResponse();
    }
  }

  /// Called by [attachRequest] to request that we actually connect to the app
  /// to be debugged.
  @override
  Future<void> attachImpl() async {
    final args = this.args as DartAttachRequestArguments;
    final vmServiceUri = args.vmServiceUri;
    final vmServiceInfoFile = args.vmServiceInfoFile;

    if ((vmServiceUri == null) == (vmServiceInfoFile == null)) {
      sendConsoleOutput(
        'To attach, provide exactly one of vmServiceUri/vmServiceInfoFile',
      );
      handleSessionTerminate();
      return;
    }

    final uri = vmServiceUri != null
        ? Uri.parse(vmServiceUri)
        : await waitForVmServiceInfoFile(logger, File(vmServiceInfoFile!));

    unawaited(connectDebugger(uri));
  }

  /// Calls the client (via a `runInTerminal` request) to spawn the process so
  /// that it can run in a local terminal that the user can interact with.
  Future<void> launchInEditorTerminal(
    bool debug,
    String terminalKind,
    String executable,
    List<String> processArgs, {
    required String? workingDirectory,
    required Map<String, String>? env,
  }) async {
    final args = this.args as DartLaunchRequestArguments;
    logger?.call('Spawning $executable with $processArgs in $workingDirectory'
        ' via client $terminalKind terminal');

    // runInTerminal is a DAP request that goes from server-to-client that
    // allows the DA to ask the client editor to run the debugee for us. In this
    // case we will have no access to the process (although we get the PID) so
    // for debugging will rely on the process writing the service-info file that
    // we can detect with the normal watching code.
    final requestArgs = RunInTerminalRequestArguments(
      args: [executable, ...processArgs],
      cwd: workingDirectory ?? normalizePath(path.dirname(args.program)),
      env: env,
      kind: terminalKind,
      title: args.name ?? 'Dart',
    );
    try {
      final response = await sendRequest(requestArgs);
      final body =
          RunInTerminalResponseBody.fromJson(response as Map<String, Object?>);
      logger?.call(
        'Client spawned process'
        ' (proc: ${body.processId}, shell: ${body.shellProcessId})',
      );
    } catch (e) {
      logger?.call('Client failed to spawn process $e');
      sendConsoleOutput('Failed to spawn process: $e');
      handleSessionTerminate();
    }

    // When using `runInTerminal` and `noDebug`, we will not connect to the VM
    // Service so we will have no way of knowing when the process completes, so
    // we just send the termination event right away.
    if (!debug) {
      handleSessionTerminate();
    }
  }

  /// Launches the program as a process controlled by the debug adapter.
  ///
  /// Output to `stdout`/`stderr` will be sent to the editor using
  /// [OutputEvent]s.
  Future<void> launchAsProcess(
    String executable,
    List<String> processArgs, {
    required String? workingDirectory,
    required Map<String, String>? env,
  }) async {
    logger?.call('Spawning $executable with $processArgs in $workingDirectory');
    final process = await Process.start(
      executable,
      processArgs,
      workingDirectory: workingDirectory,
      environment: env,
    );
    _process = process;
    pidsToTerminate.add(process.pid);

    process.stdout.listen(_handleStdout);
    process.stderr.listen(_handleStderr);
    unawaited(process.exitCode.then(_handleExitCode));
  }

  /// Called by [terminateRequest] to request that we gracefully shut down the
  /// app being run (or in the case of an attach, disconnect).
  @override
  Future<void> terminateImpl() async {
    if (isAttach) {
      await handleDetach();
    }
    terminatePids(ProcessSignal.sigterm);
    await _process?.exitCode;
  }

  void _handleExitCode(int code) {
    final codeSuffix = code == 0 ? '' : ' ($code)';
    logger?.call('Process exited ($code)');
    handleSessionTerminate(codeSuffix);
  }

  void _handleStderr(List<int> data) {
    sendOutput('stderr', utf8.decode(data));
  }

  void _handleStdout(List<int> data) {
    sendOutput('stdout', utf8.decode(data));
  }
}
