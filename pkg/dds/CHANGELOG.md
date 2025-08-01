# 5.0.5
- [DAP] The change in DDS 5.0.4 to individually add/remove breakpoints has been reverted and may be restored in a future version.

# 5.0.4
- [DAP] Breakpoints are now added/removed individually instead of all being cleared and re-added during a `setBreakpoints` request. This improves performance and can avoid breakpoints flickering between unresolved/resolved when adding new breakpoints in the same file.

# 5.0.3
- [DAP] Handle some additional errors if the VM Service is shutting down during an attempt to resume an isolate.
- [DAP] Stack frames with dots in paths will now be parsed and have locations attached to `OutputEvents`s.
- [DAP] Responses to `evaluateRequest` that are lists now include `indexedVariables` to allow for client-side paging.

# 5.0.2
- [DAP] Handle possible race condition when interacting with web applications
  that can cause an `RPCError` to be thrown if the application's isolate is
  disposed mid-RPC.

# 5.0.1
- Widen the dependency on `package:shelf_web_socket`.
- Require Dart SDK v. 3.5.0 or higher.
- Started caching events sent on the 'Timer' stream. The cached events can be retrieved using the `getStreamHistory` RPC.

# 5.0.0
- [DAP] The debug adapter no longer spawns its own in-process copy of DDS, instead relying on one started by the Dart VM (or `Flutter`). This means the `enableDds` and `enableAuthCodes` arguments to the `DartDebugAdapter` base class have been deprecated and have any effect. Suppressing DDS (or auth codes) should be done in launch configuration (for example using `vmAdditionalArgs` or `toolArgs` depending on the target tool).
- Updated the `devtools_shared` dependency to version `^11.0.0`.
- Made `runDartDevelopmentServiceFromCLI` pass the specified bind address
  directly into `startDartDevelopmentService` without resolving the address.
- [DAP] Evaluations now use Service ID Zones to more precisely control the
  lifetime of instance references returned. This should avoid instances being
  collected while execution is paused, while releasing them once execution
  resumes.
- Updated `vm_service` constraint to `>=14.3.0 <16.0.0`.
- [DAP] Updated `dap` constraint to ^1.4.0.
- [DAP] Set `supportsANSIStyling` to `true` in debug adapter capabilities to indicate that `Output` events might contain ansi color codes.
- [DAP] Stack traces in more formats will be parsed and have locations attached to `OutputEvents`s.
- Update to be forward compatible with `package:shelf_web_socket` version `3.x`.

# 4.2.7
- Added a new constant `RpcErrorCodes.kConnectionDisposed = -32010` for requests
  failing because the service connection was closed. This value is not currently
  used but is provided for clients to handle in preperation for a future release
  that will use it to avoid clients having to read error messages.
- Loosened type of `google3WorkspaceRoot` parameter to `DartDevelopmentServiceLauncher.start`
  from `Uri?` to `Object?`. This parameter will eventually be changed to `String?`, but will
  allow both `Uri?` and `String?` values for now.

# 4.2.6
- [DAP] Fixed an issue where "Service connection disposed" errors may go unhandled during termination/shutdown.
- Add `google3WorkspaceRoot` parameter to `DartDevelopmentServiceLauncher.start`.

# 4.2.5+1
- Fix issue where `DartDevelopmentServiceException.fromJson` would throw a `StateError` whenever called, except when called to create an `ExistingDartDevelopmentServiceException`.

# 4.2.5
- Fixed DevTools URI not including a trailing '/' before the query parameters, which could prevent DevTools from loading properly.
- [DAP] Fixed an issue where format specifiers and `format.hex` in `variablesRequest` would not apply to values from lists such as `Uint8List` from `dart:typed_data`.
- Added `package:dds/dds_launcher.dart`, a library which can be used to launch DDS instances using `dart development-service`.

# 4.2.4+1
- Added missing type to `Event` in `postEvent`.
- [DAP] Instaces with both fields and getters of the same name will no longer show duplicates in `variables` responses.
- `bin/dds.dart` now closes the `stderr` pipe after writing its JSON to the stream.

# 4.2.3
- Added missing await of `WebSocketChannel.ready` in `startDartDevelopmentService`.

# 4.2.2
- [DAP] Exceptions that occur while the debug adapter is connecting to the VM Service and configuring isolates will no longer cause the debug adapter to terminate. Instead, the errors are reporting via a `console` `OutputEvent` and the adapter will shut down gracefully.

# 4.2.1
- [DAP]: Fixed an issue where breakpoint `changed` events might contain incorrect location information when new isolates are created, causing breakpoints to appear to move in the editor.
- [DAP]: For consistency with other values, automatic `toString()` invocations for debugger views no longer expand long strings and instead show truncated values. Full values continue to be returned for evaluation (`context=="repl"`) and when copying to the clipboard (`context=="clipboard"`).
- [DAP]: Improved handling of sentinel responses when building `variables` responses. This prevents entire map/list requests from failing when only some values inside are sentinels.
- [DAP] Set `requirePermissionToResume` and `requireUserPermissionToResume` for `onPauseStart` and `onPauseExit` so that DDS waits for DAP's permission before resuming the isolate.

# 4.2.0
- [DAP] All `OutputEvent`s are now scanned for stack frames to attach `source` metadata to. The [parseStackFrames] parameter for `sendOutput` is ignored and deprecated.

# 4.1.0
- Internal change: removed static method `DevToolsUtils.initializeAnalytics`
and prepared DDS for using `unified_analytics` through the Dart Tooling Daemon.
- Internal change: removed `analytics` parameter from the DevTools server `defaultHandler` method.
- Updated `README.md` and added  contributing guide (`CONTRIBUTING.md`).
- Updated `package:dds_service_extensions` constraint to ^2.0.0.
- Determine default `requireUserPermissionToResume` values from the `pause_isolates_on_start` and `pause_isolates_on_exit` flags.
- Indicate compatibility with `package:web_socket_channel` 2.x and 3.x
- Indicate compatibility with `package:shelf_web_socket` 1.x and 2.x
- Updated the `devtools_shared` dependency to version `^9.0.1`.
- Remove the `package:unified_analytics` dependency.
- Serve DevTools extensions from their absolute location.

# 4.0.0
- Updated DDS protocol to version 2.0.
- Added `readyToResume` and `requireUserPermissionToResume` RPCs.
- **Breaking change:** `resume` is now treated as a user-initiated resume request and force resumes paused isolates, regardless of required resume approvals. Tooling relying on resume permissions should use the `readyToResume` RPC to indicate to DDS that they are ready to resume.

# 3.4.0
- Start the Dart Tooling Daemon from the DevTools server when a connection is not passed to the server on start.

# 3.3.1
- [DAP] Fixed an issue introduced in 3.3.0 where `Source.name` could contain a file paths when a `package:` or `dart:` URI should have been used.
- Updated `package:devtools_shared` version to ^8.0.1.

# 3.3.0
- **Breaking change:** [DAP] Several signatures in DAP debug adapter classes have been updated to use `Uri`s where they previously used `String path`s. This is to support communicating with the DAP client using URIs instead of file paths. URIs may be used only when the client sets the custom `supportsDartUris` client capability during initialization.
- [DAP] Added support for using mapping `dart-macro+file:///` URIs in communication with the client if the `supportsDartUris` flag is set in arguments for `initializeRequest`.
- Fixed issue where DDS would fail to initialize when an isolate in the target process was unable to handle service requests (b/323386606).
- Updated `package:dap` version to 1.2.0.

# 3.2.1
- Adding `unified_analytics` as a dependency and added static method `DevToolsUtils.initializeAnalytics` to create analytics instance for DevTools.
- Updated `devtools_shared` constraint to ^7.0.0.

# 3.2.0
- [DAP] Fixed "Unable to find library" errors when using global evaluation when the context file resolves to a `package:` URI.
- Updated `devtools_shared` to ^6.0.4.
- Added `--dtd-uri=<uri>` flag to DevTools server.
- Updated `vm_service` constraint to ^14.0.0.

# 3.1.2
- Improved error handling for serving static DevTools assets.
- Updated `devtools_shared` constraint to ^6.0.3.
- [DAP] The error message shown when global evaluation is unavailable been improved.
- [DAP] Error messages shown on the client no longer contain verbose stack traces (although they are still included in the JSON payloads).
- [DAP] `stackTraceRequest` now returns an empty stack instead of throwing if called for a thread that has exited.
- [DAP] Fixed an issue that could cause a crash during shutdown if an isolate was being resumed.
- Updated `vm_service` constraint to ^13.0.0.

# 3.1.1
- Updated `vm_service` constraint to ^14.0.0.

# 3.1.0+1
Hot-fix release of changes in 3.1.2 without the changes in 3.1.1

- Improved error handling for serving static DevTools assets.
- Updated `devtools_shared` constraint to ^6.0.3.
- [DAP] The error message shown when global evaluation is unavailable been improved.
- [DAP] Error messages shown on the client no longer contain verbose stack traces (although they are still included in the JSON payloads).
- [DAP] `stackTraceRequest` now returns an empty stack instead of throwing if called for a thread that has exited.
- [DAP] Fixed an issue that could cause a crash during shutdown if an isolate was being resumed.

# 3.1.0
- Updated `devtools_shared` to ^6.0.0.
- Updated `vm_service` to ^13.0.0.

# 3.0.0
- **Breaking change:** change type of `DartDebugAdapter.vmService` from `VmServiceInterface` to `VmService`.

# 2.11.1
- [DAP] `restartFrameRequest` is now supported for frames up until the first async boundary (that are not also the top frame).
- Update `vm_service` version to >=11.0.0 <13.0.0.

# 2.11.0
- Added a retry to the DevTools handler for serving static files.
- Updated `devtools_shared` to ^4.0.0.

# 2.10.0
- Updated `devtools_shared` to ^3.0.0.

# 2.9.5
- [DAP] The change to use VM Service Isolate numbers for `threadId`s has been reverted because Isolate numbers can be larger than the 32-bit integers allowed in DAP.
- [DAP] Threads returned from `threadsRequest` from the DDS DAP handler now include `isolateId` fields to allow mapping back to VM Service Isolates.

# 2.9.4
- Updated `devtools_shared` to ^2.26.1.

# 2.9.3
- [DAP] `threadId`s generated by the debug adapter now match the Isolate numbers of the underlying isolates.
- [DAP] Global evaluation (evaluation without a `frameId`) is now available for top-levels if a `file://` URI for a script is provided as the `context` for an `evaluate` request.
- [DAP] Fix ConcurrentModificationError when sending breakpoints.

# 2.9.2
- [DAP] Fixed an issue that could cause breakpoints to become unresolved when there are multiple isolates (such as during a test run).
- [DAP] Fixed an issue where stack frames parsed in test failures could produce incorrect absolute paths in the `source.path` field if the working directory of the debug adapter did not match that of the launch/attach request.
- [DAP] A new configuration option `bool? allowAnsiColorOutput` can enable using ansi color codes in `Output` events to improve readability of stack traces (fading out frames that are not user code).
- Increase minimum Dart SDK version to 3.0.0.

# 2.9.1
- [DAP] A new configuration option `bool? showGettersInDebugViews` allows getters to be shown wrapped in Variables/Evaluation responses so that they can be lazily expanded by the user. `evaluateGettersInDebugViews` must be `false` for this behaviour.
- [DAP] `runInTerminal` requests are now sent after first responding to the `launchRequest`.
- [DAP] Skipped tests are now marked with `!` instead of `✓` in `Output` events.
- [DAP] Implemented `pause` request.
- [DAP] Fixed an issue that could leave breakpoints unresolved when adding/removing other breakpoints in a file.
- Fixed a bug that was preventing clients from receiving `IsolateReload` events
  (see https://dartbug.com/49491).
- Added notifications for DAP events.

# 2.9.0
- Updated DDS protocol to version 1.6.
- Add `postEvent RPC.

# 2.8.3
- Pass-through expression evaluation types, method and class information.

# 2.8.2
- [DAP] Fixed an issue that could result in unhandled exceptions from in-flight requests when the application/VM Service is shutting down.

# 2.8.1
- Updated DDS protocol version to 1.5.
- Added `getPerfettoVMTimelineWithCpuSamples` RPC.
- Updated `vm_service` version to >=11.0.0 <12.0.0.

# 2.7.10
- [DAP] Isolates that exit immediately after being paused (perhaps by another debugger or due to the app shutting down) will no longer cause a crash.

# 2.7.9
- [DAP] Configuring and resuming isolates will no longer cause a crash if the isolate exits before the request is processed.

# 2.7.8
- [DAP] Sentinel values (such as uninitialized fields/locals) will no longer cause `scopesRequest`/`variablesRequest` to fail, instead showing appropriate text (like "<not initialized>") against the variable.

# 2.7.7
- [DAP] Debug adapters now only call `setLibraryDebuggable` when the debuggable flag changes from the default/current values, reducing the amount of VM Service traffic for new isolates/reloads.
- [DAP] `breakpoint` events are no longer sometimes sent prior to the response to the `setBreakpointsRequest` that created them.

# 2.7.6
- [DAP] `scopesRequest` now returns a `Globals` scope containing global variables for the current frame.
- [DAP] Responses to `setBreakpointsRequest` will now have `verified: false` and will send `breakpoint` events to update `verified` and/or `line`/`column` as the VM resolves them.

# 2.7.5
- Updated `vm_service` version to >=9.0.0 <12.0.0.

# 2.7.4
- [DAP] Added support for `,d` (decimal), `,h` (hex) and `,nq` (no quotes) format specifiers to be used as suffixes to evaluation requests.
- [DAP] Added support for `format.hex` in `variablesRequest` and `evaluateRequest`.

# 2.7.3
- [DAP] Added support for displaying records in responses to `variablesRequest`.
- A new exception `ExistingDartDevelopmentServiceException` (extending `DartDevelopmentServiceException`) is thrown when trying to connect DDS to a VM Service that already has a DDS instance. This new exception contains a `ddsUri` field that is populated with the URI of the existing DDS instance if provided by the target VM Service.

# 2.7.2
- Update DDS protocol version to 1.4.
- [DAP] Forward any events from the VM Service's `ToolEvent` stream as `dart.toolEvent` DAP events.

# 2.7.1
- Updated `vm_service` version to >=9.0.0 <11.0.0.
- Simplified the DevTools URI composed by DDS.
- Fix issue where DDS was invoking an unimplemented RPC against a non-VM target.

# 2.7.0
- Added `DartDevelopmentService.setExternalDevToolsUri(Uri uri)`, adding support for registering an external DevTools server with DDS.

# 2.6.1
- [DAP] Fix a crash handling errors when fetching full strings in evaluation and logging events.

# 2.6.0
- Add support for registering and subscribing to custom service streams.
- [DAP] Supplying incorrect types of arguments in `launch`/`attach` requests will now result in a clear error message in an error response instead of terminating the adapter.

# 2.5.0
- [DAP] `variables` requests now treat lists from `dart:typed_data` (such as `Uint8List`) like standard `List` instances and return their elements instead of class fields.
- [DAP] `variables` requests now return information about the number of items in lists to allow the client to page through them.
- [DAP] `terminated` events are now always sent when detaching whether or not the debuggee terminates after unpause.
- [DAP] Debug adapters can now add/overwrite `orgDartlangSdkMappings` to control mappings of `org-dartlang-sdk:///` paths.

# 2.4.0
- [DAP] Added support for sending progress notifications via `DartDebugAdapter.startProgressNotification`.
  Standard progress events are sent when a clients sets `supportsProgressReporting: true` in its capabilities,
  unless `sendCustomProgressEvents: true` is included in launch configuration, in which case prefixed (`dart.`) custom notifications will be sent instead.

# 2.3.1
- Fixed issue where DDS wasn't correctly handling `Sentinel` responses in `IsolateManager.initialize()`.

# 2.3.0
- [DAP] Removed an unused parameter `resumeIfStarting` from `DartDebugAdapter.connectDebugger`.
- [DAP] Fixed some issues where removing breakpoints could fail if an isolate exited during an update or multiple client breakpoints mapped to the same VM breakpoint.
- [DAP] Paths provided to DAP now always have Windows drive letters normalized to uppercase to avoid some issues where paths may be treated case sensitively.
- Fixed issue where DDS wasn't correctly handling `Sentinel` responses in `IsolateManager.initialize()`.

# 2.2.6
- Fixed an issue where debug adapters would not automatically close after terminating/disconnecting from the debugee.

# 2.2.5
- Updated `devtools_shared` version to 2.14.1.

# 2.2.4
- Fix an issue where DAP adapters could try to remove the same breakpoint multiple times.

# 2.2.3
- Internal DAP changes.

# 2.2.2
- Updated `vm_service` version to 9.0.0.

# 2.2.1
- Reduce latency of `streamListen` calls through improved locking behavior.

# 2.2.0
- Add support for serving DevTools via `package:dds/devtools_server.dart`.

# 2.1.7
- Re-release 2.1.6+1.

# 2.1.6+3
- Roll back to 2.1.4.

# 2.1.6+2
- Roll back to 2.1.5.

# 2.1.6+1
- Fix dependencies.

# 2.1.6
- Improve performance of CPU sample caching.

# 2.1.5
- Update to new CpuSamplesEvent format for CPU sample caching for improved
  performance.
- Add additional context in the case of failure to ascii decode headers caused
  by utf8 content on the stream.

# 2.1.4
- A new library `package:dds/dap.dart` exposes classes required to build a custom DAP
  debug-adapter on top of the base Dart DAP functionality in DDS.
  For more details on DAP support in Dart see
  [this README](https://github.com/dart-lang/sdk/blob/main/pkg/dds/tool/dap/README.md).

# 2.1.3
- Ensure cancelling multiple historical streams with the same name doesn't cause an
  asynchronous `StateError` to be thrown.

# 2.1.2
- Silently handle exceptions that occur within RPC request handlers.

# 2.1.1
- Fix another possibility of `LateInitializationError` being thrown when trying to
  cleanup after an error during initialization.

# 2.1.0
- Added getAvailableCachedCpuSamples and getCachedCpuSamples.

# 2.0.2
- Fix possibility of `LateInitializationError` being thrown when trying to
  cleanup after an error during initialization.

# 2.0.1
- Update `package:vm_service` to ^7.0.0.

# 2.0.0
- **Breaking change:** add null safety support.
- **Breaking change:** minimum Dart SDK revision bumped to 2.12.0.

# 1.8.0
- Add support for launching DevTools from DDS.
- Fixed issue where two clients subscribing to the same stream in close succession
  could result in DDS sending multiple `streamListen` requests to the VM service.

# 1.7.6
- Update dependencies.

# 1.7.5
- Add 30 second keep alive period for SSE connections.

# 1.7.4
- Update `package:vm_service` to 6.0.1-nullsafety.0.

# 1.7.3
- Return an RpcException error with code `kServiceDisappeared` if the VM
  service connection disappears with an outstanding forwarded request.

# 1.7.2
- Fixed issue where a null JSON RPC result could be sent if the VM service
  disconnected with a request in flight (see https://github.com/flutter/flutter/issues/74051).

# 1.7.1
- Fixed issue where DartDevelopmentServiceException could have a null message.

# 1.7.0
- Added `package:dds/vm_service_extensions.dart`, which adds DDS functionality to
  `package:vm_service` when imported.
  - Added `onEventWithHistory` method and `onLoggingEventWithHistory`, 
    `onStdoutEventWithHistory`, `onStderrEventWithHistory`, and 
    `onExtensionEventWithHistory` getters.
- Added `getStreamHistory` RPC.

# 1.6.1
- Fixed unhandled `StateError` that could be thrown if the VM service disconnected
  while a request was outstanding.

# 1.6.0
- Added `errorCode` to `DartDevelopmentServiceException` to communicate the
  underlying reason of the failure.

# 1.5.1
- Improve internal error handling for situations with less than graceful
  shutdowns.

# 1.5.0
- Added event caching for `Stdout`, `Stderr`, and `Extension` streams. When a
client subscribes to one of these streams, they will be sent up to 10,000
historical events from the stream.

# 1.4.1
- Fixed issue where `evaluate` and `evaluateInFrame` requests were not being
  forwarded to the VM service properly when no external compilation service
  was registered.

# 1.4.0
- Added `done` property to `DartDevelopmentService`.
- Throw `DartDeveloperServiceException` when shutdown occurs during startup.
- Fixed issue where `StateError` was thrown when DDS was shutdown with pending
  requests.

# 1.3.5

- Fixed issue where clients subscribing to the `Service` stream were not being
  sent `ServiceRegistered` events on connection.

# 1.3.4

- Fixed issue where `isolateId`s were expected to take the form `isolates/123`
  although this is not required by the VM service specification.

# 1.3.3

- Fixed issue where `DartDevelopmentService.sseUri` did not return a URI with a
  `sse` scheme.

# 1.3.2

- Add IPv6 hosting support.
- Fix handling of requests that are outstanding when a client channel is closed.

# 1.3.1

- Fixed issue where an exception could be thrown during startup if the target
  process had an isolate without an associated pause event.

# 1.3.0

- Added support for SSE connections from web-based clients.

# 1.2.4

- Fixed another issue where a `StateError` could be raised within `DartDevelopmentService`
  when a client has disconnected after the target VM service has shutdown.

# 1.2.3

- Fixed issue where DDS was expecting a client provided implementation of
`compileExpression` to return a response with two layers of `response` objects.

# 1.2.2

- Fixed issue where a `StateError` could be raised within `DartDevelopmentService`
  when a client has disconnected after the target VM service has shutdown.

# 1.2.1

- Fixed issue where `evaluate` and `evaluateInFrame` were not invoking client
  provided implementations of `compileExpression`.

# 1.2.0

- Fixed issue where forwarding requests with no RPC parameters would return an
  RPC error.

# 1.1.0

- Added `getDartDevelopmentServiceVersion` RPC.
- Added DDS protocol to VM service `getSupportedProtocols` response.
- Added example/example.dart.
- Allow for JSON-RPC 2.0 requests which are missing the `jsonrpc` parameter.

# 1.0.0

- Initial release.
