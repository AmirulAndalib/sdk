// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:analysis_server/protocol/protocol_constants.dart'
    show PROTOCOL_VERSION;
import 'package:analysis_server/src/analytics/analytics_manager.dart';
import 'package:analysis_server/src/legacy_analysis_server.dart';
import 'package:analysis_server/src/lsp/lsp_socket_server.dart';
import 'package:analysis_server/src/server/crash_reporting.dart';
import 'package:analysis_server/src/server/crash_reporting_attachments.dart';
import 'package:analysis_server/src/server/detachable_filesystem_manager.dart';
import 'package:analysis_server/src/server/dev_server.dart';
import 'package:analysis_server/src/server/diagnostic_server.dart';
import 'package:analysis_server/src/server/error_notifier.dart';
import 'package:analysis_server/src/server/features.dart';
import 'package:analysis_server/src/server/http_server.dart';
import 'package:analysis_server/src/server/isolate_analysis_server.dart';
import 'package:analysis_server/src/server/lsp_stdio_server.dart';
import 'package:analysis_server/src/server/sdk_configuration.dart';
import 'package:analysis_server/src/server/stdio_server.dart';
import 'package:analysis_server/src/services/correction/assist_internal.dart';
import 'package:analysis_server/src/services/correction/fix_internal.dart';
import 'package:analysis_server/src/socket_server.dart';
import 'package:analysis_server/src/utilities/request_statistics.dart';
import 'package:analysis_server/starter.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/instrumentation/file_instrumentation.dart';
import 'package:analyzer/instrumentation/instrumentation.dart';
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/util/sdk.dart';
import 'package:args/args.dart';
import 'package:linter/src/rules.dart' as linter;
import 'package:telemetry/crash_reporting.dart';
import 'package:unified_analytics/unified_analytics.dart';

import '../utilities/usage_tracking/usage_tracking.dart';

/// The [Driver] class represents a single running instance of the analysis
/// server application.  It is responsible for parsing command line options
/// and starting the HTTP and/or stdio servers.
class Driver implements ServerStarter {
  /// The name of the application that is used to start a server.
  static const BINARY_NAME = 'analysis_server';

  /// The name of the option used to set the identifier for the client.
  static const String CLIENT_ID = 'client-id';

  /// The name of the option used to set the version for the client.
  static const String CLIENT_VERSION = 'client-version';

  /// The name of the option used to disable exception handling.
  static const String DISABLE_SERVER_EXCEPTION_HANDLING =
      'disable-server-exception-handling';

  /// The name of the option to disable the completion feature.
  static const String DISABLE_SERVER_FEATURE_COMPLETION =
      'disable-server-feature-completion';

  /// The name of the option to disable the search feature.
  static const String DISABLE_SERVER_FEATURE_SEARCH =
      'disable-server-feature-search';

  /// The name of the option to disable the debouncing of `server.status`
  /// notifications.
  static const String DISABLE_STATUS_NOTIFICATION_DEBOUNCING =
      'disable-status-notification-debouncing';

  /// The name of the option to prevent exceptions during analysis from being
  /// silent.
  static const String DISABLE_SILENT_ANALYSIS_EXCEPTIONS =
      'disable-silent-analysis-exceptions';

  /// The name of the multi-option to enable one or more experiments.
  static const String ENABLE_EXPERIMENT = 'enable-experiment';

  /// The name of the option used to print usage information.
  static const String HELP_OPTION = 'help';

  /// The name of the flag used to configure reporting legacy analytics.
  static const String ANALYTICS_FLAG = 'analytics';

  /// Suppress legacy analytics for this session.
  static const String SUPPRESS_ANALYTICS_FLAG = 'suppress-analytics';

  /// The name of the option used to cause instrumentation to also be written to
  /// a local file.
  static const String PROTOCOL_TRAFFIC_LOG = 'protocol-traffic-log';
  static const String PROTOCOL_TRAFFIC_LOG_ALIAS = 'instrumentation-log-file';

  /// The name of the option used to specify if [print] should print to the
  /// console instead of being intercepted.
  static const String INTERNAL_PRINT_TO_CONSOLE = 'internal-print-to-console';

  /// The name of the option used to describe the new analysis driver logger.
  static const String ANALYSIS_DRIVER_LOG = 'analysis-driver-log';
  static const String ANALYSIS_DRIVER_LOG_ALIAS = 'new-analysis-driver-log';

  /// The option for specifying the http diagnostic port.
  /// If specified, users can review server status and performance information
  /// by opening a web browser on http://localhost:<port>
  static const String DIAGNOSTIC_PORT = 'diagnostic-port';
  static const String DIAGNOSTIC_PORT_ALIAS = 'port';

  /// The path to the SDK.
  static const String DART_SDK = 'dart-sdk';
  static const String DART_SDK_ALIAS = 'sdk';

  /// The path to the data cache.
  static const String CACHE_FOLDER = 'cache';

  /// The path to the package config file override.
  static const String PACKAGES_FILE = 'packages';

  /// The forced protocol version that the server will report to the client.
  static const String REPORT_PROTOCOL_VERSION = 'report-protocol-version';

  /// The name of the flag specifying the server protocol to use.
  static const String SERVER_PROTOCOL = 'protocol';
  static const String PROTOCOL_ANALYZER = 'analyzer';
  static const String PROTOCOL_LSP = 'lsp';

  /// The name of the flag to use the Language Server Protocol (LSP).
  static const String USE_LSP = 'lsp';

  /// A directory to analyze in order to train an analysis server snapshot.
  static const String TRAIN_USING = 'train-using';

  /// Flag to not use a (Evicting)FileByteStore.
  static const String DISABLE_FILE_BYTE_STORE = 'disable-file-byte-store';

  /// The builder for attachments that should be included into crash reports.
  CrashReportingAttachmentsBuilder crashReportingAttachmentsBuilder =
      CrashReportingAttachmentsBuilder.empty;

  /// An optional manager to handle file systems which may not always be
  /// available.
  DetachableFileSystemManager? detachableFileSystemManager;

  /// The instrumentation service that is to be used by the analysis server.
  late final InstrumentationService _instrumentationService;

  /// Use the given command-line [arguments] to start this server.
  ///
  /// If [sendPort] is not null, assumes this is launched in an isolate and will
  /// connect to the original isolate via an isolate channel.
  @override
  void start(
    List<String> arguments, {
    SendPort? sendPort,
    bool defaultToLsp = false,
  }) {
    var sessionStartTime = DateTime.now();
    var parser = createArgParser(defaultToLsp: defaultToLsp);
    var results = parser.parse(arguments);

    var analysisServerOptions = AnalysisServerOptions();
    analysisServerOptions.newAnalysisDriverLog =
        results.option(ANALYSIS_DRIVER_LOG) ??
        results.option(ANALYSIS_DRIVER_LOG_ALIAS);
    if (results.wasParsed(USE_LSP)) {
      analysisServerOptions.useLanguageServerProtocol = results.flag(USE_LSP);
    } else {
      analysisServerOptions.useLanguageServerProtocol =
          results.option(SERVER_PROTOCOL) == PROTOCOL_LSP;
    }
    // For clients that don't supply their own identifier, use a default based
    // on whether the server will run in LSP mode or not.
    var clientId =
        results.option(CLIENT_ID) ??
        (analysisServerOptions.useLanguageServerProtocol
            ? 'unknown.client.lsp'
            : 'unknown.client.classic');
    analysisServerOptions.clientId = clientId;
    analysisServerOptions.clientVersion = results.option(CLIENT_VERSION);
    analysisServerOptions.cacheFolder = results.option(CACHE_FOLDER);
    analysisServerOptions.packagesFile = results.option(PACKAGES_FILE);
    analysisServerOptions.reportProtocolVersion = results.option(
      REPORT_PROTOCOL_VERSION,
    );

    analysisServerOptions.enabledExperiments = results.multiOption(
      ENABLE_EXPERIMENT,
    );

    // Read in any per-SDK overrides specified in <sdk>/config/settings.json.
    var sdkConfig = SdkConfiguration.readFromSdk();
    analysisServerOptions.configurationOverrides = sdkConfig;

    // Analytics (legacy, and unified)
    var disableAnalyticsForSession = results.flag(SUPPRESS_ANALYTICS_FLAG);

    if (results.wasParsed(TRAIN_USING)) {
      disableAnalyticsForSession = true;
    }

    var defaultSdkPath = _getSdkPath(results);
    var dartSdkManager = DartSdkManager(defaultSdkPath);

    // TODO(brianwilkerson): It would be nice to avoid creating an SDK that
    // can't be re-used, but the SDK is needed to create a package map provider
    // in the case where we need to run `pub` in order to get the package map.
    var defaultSdk = _createDefaultSdk(defaultSdkPath);

    // Create the analytics manager.
    Analytics analytics;
    if (disableAnalyticsForSession) {
      analytics = NoOpAnalytics();
    } else {
      var tool = switch (clientId) {
        'VS-Code' || 'VS-Code-Remote' => DashTool.vscodePlugins,
        'IntelliJ-IDEA' => DashTool.intellijPlugins,
        'Android-Studio' => DashTool.androidStudioPlugins,
        _ => null,
      };
      if (tool != null) {
        analytics = _createAnalytics(defaultSdk, defaultSdkPath, tool);
      } else {
        analytics = NoOpAnalytics();
      }
    }
    var analyticsManager = AnalyticsManager(analytics);

    bool shouldSendCallback() {
      // Check sdkConfig to optionally force reporting on.
      if (sdkConfig.crashReportingForceEnabled == true) {
        return true;
      }

      // Reuse the unified_analytics consent mechanism to determine whether
      // we can send a crash report.
      return analyticsManager.analytics.okToSend;
    }

    // Crash reporting

    // Use sdkConfig to optionally override analytics settings.
    var crashProductId = sdkConfig.crashReportingId ?? 'Dart_analysis_server';
    var crashReportSender = CrashReportSender.prod(
      crashProductId,
      shouldSendCallback,
    );

    {
      var disableCompletion = results.flag(DISABLE_SERVER_FEATURE_COMPLETION);
      var disableSearch = results.flag(DISABLE_SERVER_FEATURE_SEARCH);
      if (disableCompletion || disableSearch) {
        analysisServerOptions.featureSet = FeatureSet(
          completion: !disableCompletion,
          search: !disableSearch,
        );
      }
    }

    if (results.flag(HELP_OPTION)) {
      _printUsage(parser, fromHelp: true);
      return;
    }

    // Record the start of the session.
    analyticsManager.startUp(
      time: sessionStartTime,
      arguments: _getArgumentsForAnalytics(results),
      clientId: clientId,
      clientVersion: analysisServerOptions.clientVersion,
    );
    //
    // Initialize the instrumentation service.
    //
    var logFilePath =
        results.option(PROTOCOL_TRAFFIC_LOG) ??
        results.option(PROTOCOL_TRAFFIC_LOG_ALIAS);
    var allInstrumentationServices = <InstrumentationService>[];
    if (logFilePath != null) {
      _rollLogFiles(logFilePath, 5);
      allInstrumentationServices.add(
        InstrumentationLogAdapter(
          FileInstrumentationLogger(logFilePath),
          watchEventExclusionFiles: {logFilePath},
        ),
      );
    }

    var errorNotifier = ErrorNotifier();
    allInstrumentationServices.add(errorNotifier);
    allInstrumentationServices.add(
      CrashReportingInstrumentation(crashReportSender),
    );
    _instrumentationService = MulticastInstrumentationService(
      allInstrumentationServices,
    );

    _instrumentationService.logVersion(
      results.option(TRAIN_USING) != null
          ? 'training-0'
          : _readUuid(_instrumentationService),
      analysisServerOptions.clientId ?? '',
      analysisServerOptions.clientVersion ?? '',
      PROTOCOL_VERSION,
      defaultSdk.languageVersion.toString(),
    );
    AnalysisEngine.instance.instrumentationService = _instrumentationService;

    int? diagnosticServerPort;
    var portValue =
        results.option(DIAGNOSTIC_PORT) ??
        results.option(DIAGNOSTIC_PORT_ALIAS);
    if (portValue != null) {
      try {
        diagnosticServerPort = int.parse(portValue);
      } on FormatException {
        print('Invalid port number: $portValue');
        print('');
        _printUsage(parser);
        exitCode = 1;
        return;
      }
    }

    // TODO(brianwilkerson): Pass the following value to the server and
    // implement the debouncing when it hasn't been disabled.
    // var disableDebouncing = results[DISABLE_STATUS_NOTIFICATION_DEBOUNCING] as bool;
    if (analysisServerOptions.useLanguageServerProtocol) {
      if (sendPort != null) {
        throw UnimplementedError(
          'Isolate usage not implemented for LspAnalysisServer',
        );
      }
      startLspServer(
        results,
        analysisServerOptions,
        dartSdkManager,
        analyticsManager,
        _instrumentationService,
        diagnosticServerPort,
        errorNotifier,
      );
    } else {
      startAnalysisServer(
        results,
        analysisServerOptions,
        parser,
        dartSdkManager,
        analyticsManager,
        crashReportingAttachmentsBuilder,
        _instrumentationService,
        RequestStatisticsHelper(),
        diagnosticServerPort,
        errorNotifier,
        sendPort,
      );
    }

    configureMemoryUsageTracking(
      arguments,
      (memoryUsageEvent) => analyticsManager.sendMemoryUsage(memoryUsageEvent),
    );
  }

  void startAnalysisServer(
    ArgResults results,
    AnalysisServerOptions analysisServerOptions,
    ArgParser parser,
    DartSdkManager dartSdkManager,
    AnalyticsManager analyticsManager,
    CrashReportingAttachmentsBuilder crashReportingAttachmentsBuilder,
    InstrumentationService instrumentationService,
    RequestStatisticsHelper requestStatistics,
    int? diagnosticServerPort,
    ErrorNotifier errorNotifier,
    SendPort? sendPort,
  ) {
    var capture =
        results.flag(DISABLE_SERVER_EXCEPTION_HANDLING)
            ? (_, Function f, {void Function(String)? print}) => f()
            : _captureExceptions;
    var trainDirectory = results.option(TRAIN_USING);
    if (trainDirectory != null) {
      if (!FileSystemEntity.isDirectorySync(trainDirectory)) {
        print("Training directory '$trainDirectory' not found.\n");
        exitCode = 1;
        return;
      }
    }
    linter.registerLintRules();
    registerBuiltInAssistGenerators();
    registerBuiltInFixGenerators();

    var diagnosticServer = _DiagnosticServerImpl();

    //
    // Create the sockets and start listening for requests.
    //
    var socketServer = SocketServer(
      analysisServerOptions,
      dartSdkManager,
      crashReportingAttachmentsBuilder,
      instrumentationService,
      requestStatistics,
      diagnosticServer,
      analyticsManager,
      detachableFileSystemManager,
    );

    diagnosticServer.httpServer = HttpAnalysisServer(socketServer);
    if (diagnosticServerPort != null) {
      diagnosticServer.startOnPort(diagnosticServerPort);
    }

    if (trainDirectory != null) {
      if (sendPort != null) {
        throw UnimplementedError(
          'isolate usage not supported for DevAnalysisServer',
        );
      }
      var tempDriverDir = Directory.systemTemp.createTempSync(
        'analysis_server_',
      );
      analysisServerOptions.cacheFolder = tempDriverDir.path;
      analysisServerOptions.disableFileByteStore = results.flag(
        DISABLE_FILE_BYTE_STORE,
      );

      var devServer = DevAnalysisServer(socketServer);
      devServer.initServer();

      () async {
        // We first analyze code with an empty driver cache.
        print('Analyzing with an empty driver cache:');
        var exitCode = await devServer.processDirectories([trainDirectory]);
        if (exitCode != 0) exit(exitCode);

        print('');

        // Then again with a populated cache.
        print('Analyzing with a populated driver cache:');
        exitCode = await devServer.processDirectories([trainDirectory]);
        if (exitCode != 0) exit(exitCode);

        diagnosticServer.httpServer.close();
        await instrumentationService.shutdown();
        unawaited(socketServer.analysisServer!.shutdown());

        try {
          tempDriverDir.deleteSync(recursive: true);
        } catch (_) {
          // Ignore any exception.
        }

        exit(exitCode);
      }();
    } else {
      capture(
        instrumentationService,
        () {
          Future<void> serveResult;
          if (sendPort == null) {
            var stdioServer = StdioAnalysisServer(socketServer);
            serveResult = stdioServer.serveStdio();
          } else {
            var isolateAnalysisServer = IsolateAnalysisServer(socketServer);
            serveResult = isolateAnalysisServer.serveIsolate(sendPort);
          }
          errorNotifier.server = socketServer.analysisServer;
          if (results.flag(DISABLE_SILENT_ANALYSIS_EXCEPTIONS)) {
            errorNotifier.sendSilentExceptionsToClient = true;
          }
          serveResult.then((_) async {
            diagnosticServer.httpServer.close();
            await instrumentationService.shutdown();
            unawaited(socketServer.analysisServer!.shutdown());
            if (sendPort == null) exit(0);
          });
        },
        print:
            results.flag(INTERNAL_PRINT_TO_CONSOLE)
                ? null
                : diagnosticServer.httpServer.recordPrint,
      );
    }
  }

  void startLspServer(
    ArgResults args,
    AnalysisServerOptions analysisServerOptions,
    DartSdkManager dartSdkManager,
    AnalyticsManager analyticsManager,
    InstrumentationService instrumentationService,
    int? diagnosticServerPort,
    ErrorNotifier errorNotifier,
  ) {
    var capture =
        args.flag(DISABLE_SERVER_EXCEPTION_HANDLING)
            ? (_, Function f, {void Function(String)? print}) => f()
            : _captureExceptions;

    linter.registerLintRules();
    registerBuiltInAssistGenerators();
    registerBuiltInFixGenerators();

    var diagnosticServer = _DiagnosticServerImpl();

    var socketServer = LspSocketServer(
      analysisServerOptions,
      diagnosticServer,
      analyticsManager,
      dartSdkManager,
      instrumentationService,
      detachableFileSystemManager,
    );
    errorNotifier.server = socketServer.analysisServer;
    diagnosticServer.httpServer = HttpAnalysisServer(socketServer);

    if (diagnosticServerPort != null) {
      diagnosticServer.startOnPort(diagnosticServerPort);
    }

    capture(instrumentationService, () {
      var stdioServer = LspStdioAnalysisServer(socketServer);
      stdioServer.serveStdio().then((_) {
        // Only shutdown the server and exit if the server is not already
        // handling the shutdown.
        if (!socketServer.analysisServer!.willExit) {
          unawaited(socketServer.analysisServer!.shutdown());
          exit(0);
        }
      });
    });
  }

  /// Execute the given [callback] within a zone that will capture any unhandled
  /// exceptions and both report them to the client and send them to the given
  /// instrumentation [service]. If a [print] function is provided, then also
  /// capture any data printed by the callback and redirect it to the function.
  void _captureExceptions(
    InstrumentationService service,
    void Function() callback, {
    void Function(String line)? print,
  }) {
    void errorFunction(
      Zone self,
      ZoneDelegate parent,
      Zone zone,
      Object exception,
      StackTrace stackTrace,
    ) {
      service.logException(exception, stackTrace);
      throw exception;
    }

    var printFunction =
        print == null
            ? null
            : (Zone self, ZoneDelegate parent, Zone zone, String line) {
              // Note: we don't pass the line on to stdout, because that is
              // reserved for communication to the client.
              print(line);
            };
    var zoneSpecification = ZoneSpecification(
      handleUncaughtError: errorFunction,
      print: printFunction,
    );
    return runZoned(callback, zoneSpecification: zoneSpecification);
  }

  /// Create the `Analytics` instance to be used to report analytics.
  Analytics _createAnalytics(
    DartSdk dartSdk,
    String dartSdkPath,
    DashTool tool,
  ) {
    // TODO(brianwilkerson): Find out whether there's a way to get the channel
    //  without running `flutter channel`.
    var pathContext = PhysicalResourceProvider.INSTANCE.pathContext;
    var flutterSdkRoot = pathContext.dirname(
      pathContext.dirname(pathContext.dirname(dartSdkPath)),
    );
    var flutterVersionFile = PhysicalResourceProvider.INSTANCE.getFile(
      pathContext.join(flutterSdkRoot, 'version'),
    );
    String? flutterVersion;
    try {
      flutterVersion = flutterVersionFile.readAsStringSync();
    } catch (exception) {
      // If we can't read the file, ignore it.
    }
    return Analytics(
      tool: tool,
      dartVersion: dartSdk.sdkVersion,
      // flutterChannel: '',
      flutterVersion: flutterVersion,
    );
  }

  DartSdk _createDefaultSdk(String defaultSdkPath) {
    var resourceProvider = PhysicalResourceProvider.INSTANCE;
    return FolderBasedDartSdk(
      resourceProvider,
      resourceProvider.getFolder(defaultSdkPath),
    );
  }

  /// Constructs a uuid combining the current date and a random integer.
  String _generateUuidString() {
    var millisecondsSinceEpoch = DateTime.now().millisecondsSinceEpoch;
    var random = Random().nextInt(0x3fffffff);
    return '$millisecondsSinceEpoch$random';
  }

  /// Return a list of the known command-line arguments that were parsed when
  /// creating the given [results]. We return only the names of the arguments,
  /// not the values of the arguments, in order to prevent the collection of any
  /// PII.
  List<String> _getArgumentsForAnalytics(ArgResults results) {
    // The arguments that are literal strings are deprecated and no longer read
    // from, but we still want to know if clients are using them.
    var knownArguments = [
      ANALYTICS_FLAG,
      CACHE_FOLDER,
      CLIENT_ID,
      CLIENT_VERSION,
      'completion-model',
      'dartpad',
      DART_SDK,
      DART_SDK_ALIAS,
      DIAGNOSTIC_PORT,
      DIAGNOSTIC_PORT_ALIAS,
      DISABLE_SERVER_EXCEPTION_HANDLING,
      DISABLE_SERVER_FEATURE_COMPLETION,
      DISABLE_SERVER_FEATURE_SEARCH,
      DISABLE_SILENT_ANALYSIS_EXCEPTIONS,
      DISABLE_STATUS_NOTIFICATION_DEBOUNCING,
      'enable-completion-model',
      'enable-experiment',
      'enable-instrumentation',
      'file-read-mode',
      HELP_OPTION,
      'ignore-unrecognized-flags',
      INTERNAL_PRINT_TO_CONSOLE,
      PACKAGES_FILE,
      'preview-dart-2',
      PROTOCOL_TRAFFIC_LOG,
      PROTOCOL_TRAFFIC_LOG_ALIAS,
      REPORT_PROTOCOL_VERSION,
      SERVER_PROTOCOL,
      SUPPRESS_ANALYTICS_FLAG,
      TRAIN_USING,
      'useAnalysisHighlight2',
      USE_LSP,
      'use-new-relevance',
      'use-fasta-parser',
      DISABLE_FILE_BYTE_STORE,
    ];
    return knownArguments
        .where((argument) => results.wasParsed(argument))
        .toList();
  }

  String _getSdkPath(ArgResults args) {
    String? sdkPath;

    void tryCandidateArgument(String argumentName) {
      var argumentValue = args[argumentName];
      if (sdkPath == null && argumentValue is String) {
        sdkPath = argumentValue;
      }
    }

    tryCandidateArgument(DART_SDK);
    tryCandidateArgument(DART_SDK_ALIAS);
    var sdkPath2 = sdkPath ?? getSdkPath();

    var pathContext = PhysicalResourceProvider.INSTANCE.pathContext;
    return pathContext.normalize(pathContext.absolute(sdkPath2));
  }

  /// Print information about how to use the server.
  void _printUsage(ArgParser parser, {bool fromHelp = false}) {
    print('Usage: $BINARY_NAME [flags]');
    print('');
    print('Supported flags are:');
    print(parser.usage);
  }

  /// Read the UUID from disk, generating and storing a new one if necessary.
  String _readUuid(InstrumentationService service) {
    var instrumentationLocation = PhysicalResourceProvider.INSTANCE
        .getStateLocation('.instrumentation');
    if (instrumentationLocation == null) {
      return _generateUuidString();
    }
    var uuidFile = File(instrumentationLocation.getChild('uuid.txt').path);
    try {
      if (uuidFile.existsSync()) {
        var uuid = uuidFile.readAsStringSync();
        if (uuid.length > 5) {
          return uuid;
        }
      }
    } catch (exception, stackTrace) {
      service.logException(exception, stackTrace);
    }
    var uuid = _generateUuidString();
    try {
      uuidFile.parent.createSync(recursive: true);
      uuidFile.writeAsStringSync(uuid);
    } catch (exception, stackTrace) {
      service.logException(exception, stackTrace);
      // Slightly alter the uuid to indicate it was not persisted
      uuid = 'temp-$uuid';
    }
    return uuid;
  }

  /// Create and return the parser used to parse the command-line arguments.
  static ArgParser createArgParser({
    int? usageLineLength,
    bool includeHelpFlag = true,
    bool defaultToLsp = false,
  }) {
    var parser = ArgParser(usageLineLength: usageLineLength);
    if (includeHelpFlag) {
      parser.addFlag(
        HELP_OPTION,
        abbr: 'h',
        negatable: false,
        help: 'Print this usage information.',
      );
    }
    parser.addOption(
      CLIENT_ID,
      valueHelp: 'name',
      help: 'An identifier for the analysis server client.',
    );
    parser.addOption(
      CLIENT_VERSION,
      valueHelp: 'version',
      help: 'The version of the analysis server client.',
    );
    parser.addOption(
      DART_SDK,
      valueHelp: 'path',
      help: 'Override the Dart SDK to use for analysis.',
    );
    parser.addOption(DART_SDK_ALIAS, hide: true);
    parser.addOption(
      CACHE_FOLDER,
      valueHelp: 'path',
      help: 'Override the location of the analysis server\'s cache.',
    );
    parser.addOption(
      PACKAGES_FILE,
      valueHelp: 'path',
      help:
          'The path to the package resolution configuration file, which '
          'supplies a mapping of package names\ninto paths.',
    );
    parser.addMultiOption(
      ENABLE_EXPERIMENT,
      valueHelp: 'experiment',
      help:
          'Enable one or more experimental features '
          '(see dart.dev/go/experiments).',
      hide: true,
    );

    parser.addOption(
      SERVER_PROTOCOL,
      defaultsTo: defaultToLsp ? PROTOCOL_LSP : PROTOCOL_ANALYZER,
      valueHelp: 'protocol',
      allowed: [PROTOCOL_LSP, PROTOCOL_ANALYZER],
      allowedHelp: {
        PROTOCOL_LSP:
            'The Language Server Protocol '
            '(https://microsoft.github.io/language-server-protocol)',
        PROTOCOL_ANALYZER:
            'Dart\'s analysis server protocol '
            '(https://dart.dev/go/analysis-server-protocol)',
      },
      help:
          'Specify the protocol to use to communicate with the analysis server.',
    );
    // This option is hidden but still accepted; it's effectively translated to
    // the 'protocol' option above.
    parser.addFlag(
      USE_LSP,
      negatable: false,
      help: 'Whether to use the Language Server Protocol (LSP).',
      hide: true,
    );

    parser.addSeparator('Server diagnostics:');

    parser.addOption(
      PROTOCOL_TRAFFIC_LOG,
      valueHelp: 'file path',
      help: 'Write server protocol traffic to the given file.',
    );
    parser.addOption(PROTOCOL_TRAFFIC_LOG_ALIAS, hide: true);

    parser.addOption(
      ANALYSIS_DRIVER_LOG,
      valueHelp: 'file path',
      help: 'Write analysis driver diagnostic data to the given file.',
    );
    parser.addOption(ANALYSIS_DRIVER_LOG_ALIAS, hide: true);

    parser.addOption(
      DIAGNOSTIC_PORT,
      valueHelp: 'port',
      help:
          'Serve a web UI for status and performance data on the given '
          'port.',
    );
    parser.addOption(DIAGNOSTIC_PORT_ALIAS, hide: true);

    //
    // Hidden; these have not yet been made public.
    //
    parser.addFlag(
      ANALYTICS_FLAG,
      help:
          'Allow or disallow sending analytics information to '
          'Google for this session.',
      hide: true,
    );
    parser.addFlag(
      SUPPRESS_ANALYTICS_FLAG,
      negatable: false,
      help: 'Suppress analytics for this session.',
      hide: true,
    );

    //
    // Hidden; these are for internal development.
    //
    parser.addOption(
      TRAIN_USING,
      valueHelp: 'path',
      help:
          'Pass in a directory to analyze for purposes of training an '
          'analysis server snapshot.  Disables analytics.',
      hide: true,
    );
    parser.addFlag(
      DISABLE_FILE_BYTE_STORE,
      help:
          'Disable use of (Evicting)FileByteStore. Intended for benchmarking.',
      hide: true,
    );
    parser.addFlag(
      DISABLE_SERVER_EXCEPTION_HANDLING,
      // TODO(jcollins-g): Pipeline option through and apply to all
      // exception-nullifying runZoned() calls.
      help:
          'disable analyzer exception capture for interactive debugging '
          'of the server',
      hide: true,
    );
    parser.addFlag(
      DISABLE_SERVER_FEATURE_COMPLETION,
      help: 'disable all completion features',
      hide: true,
    );
    parser.addFlag(
      DISABLE_SERVER_FEATURE_SEARCH,
      help: 'disable all search features',
      hide: true,
    );
    parser.addFlag(
      DISABLE_SILENT_ANALYSIS_EXCEPTIONS,
      negatable: false,
      help: 'Prevent exceptions during analysis from being silent',
      hide: true,
    );
    parser.addFlag(
      DISABLE_STATUS_NOTIFICATION_DEBOUNCING,
      negatable: false,
      help: 'Suppress debouncing of status notifications.',
      hide: true,
    );
    parser.addFlag(
      INTERNAL_PRINT_TO_CONSOLE,
      help: 'enable sending `print` output to the console',
      negatable: false,
      hide: true,
    );
    parser.addOption(
      REPORT_PROTOCOL_VERSION,
      valueHelp: 'version',
      help:
          'The protocol version that the server will report to the client, '
          'can be used to temporary enabling features that we expect to be '
          'available in future versions.',
      hide: true,
    );

    //
    // Hidden; these are deprecated and no longer read from.
    //

    // Removed 11/15/2020.
    parser.addOption('completion-model', hide: true);
    // Removed 11/8/2020.
    parser.addFlag('dartpad', hide: true);
    // Removed 11/15/2020.
    parser.addFlag('enable-completion-model', hide: true);
    // Removed 9/23/2020.
    parser.addFlag('enable-instrumentation', hide: true);
    // Removed 11/12/2020.
    parser.addOption('file-read-mode', hide: true);
    // Removed 11/12/2020.
    parser.addFlag('ignore-unrecognized-flags', hide: true);
    // Removed 11/8/2020.
    parser.addFlag('preview-dart-2', hide: true);
    // Removed 11/12/2020.
    parser.addFlag('useAnalysisHighlight2', hide: true);
    // Removed 11/13/2020.
    parser.addFlag('use-new-relevance', hide: true);
    // Removed 9/23/2020.
    parser.addFlag('use-fasta-parser', hide: true);

    return parser;
  }

  /// Perform log files rolling.
  ///
  /// Rename existing files with names `[path].(x)` to `[path].(x+1)`.
  /// Keep at most [numOld] files.
  /// Rename the file with the given [path] to `[path].1`.
  static void _rollLogFiles(String path, int numOld) {
    for (var i = numOld - 1; i >= 0; i--) {
      try {
        var oldPath = i == 0 ? path : '$path.$i';
        File(oldPath).renameSync('$path.${i + 1}');
      } catch (e) {
        // If a file can't be renamed, then leave it and attempt to rename the
        // remaining files.
      }
    }
  }
}

/// Implements the [DiagnosticServer] class by wrapping an [HttpAnalysisServer].
class _DiagnosticServerImpl extends DiagnosticServer {
  late HttpAnalysisServer httpServer;

  @override
  Future<int> getServerPort() async => (await httpServer.serveHttp())!;

  Future<void> startOnPort(int port) {
    return httpServer.serveHttp(port);
  }
}
