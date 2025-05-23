// Copyright (c) 2015, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_constants.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'instrumentation_input_converter.dart';
import 'log_file_input_converter.dart';
import 'operation.dart';

/// Common input converter superclass for sharing implementation.
abstract class CommonInputConverter extends Converter<String, Operation?> {
  static const _errorPrefix = 'Server responded with an error: ';
  final Logger logger = Logger('InstrumentationInputConverter');
  final Set<String> eventsSeen = <String>{};

  /// A mapping from request/response id to request json
  /// for those requests for which a response has not been processed.
  final Map<String, Object?> requestMap = {};

  /// A mapping from request/response id to a completer
  /// for those requests for which a response has not been processed.
  /// The completer is called with the actual json response
  /// when it becomes available.
  final Map<String, Completer<Object?>> responseCompleters = {};

  /// A mapping from request/response id to the actual response result
  /// for those responses that have not been processed.
  final Map<String, Object?> responseMap = {};

  /// A mapping of current overlay content
  /// parallel to what is in the analysis server
  /// so that we can update the file system.
  final Map<String, String> overlays = {};

  /// The prefix used to determine if a request parameter is a file path.
  final String rootPrefix = path.rootPrefix(path.current);

  /// A mapping of source path prefixes
  /// from location where instrumentation or log file was generated
  /// to the target location of the source using during performance measurement.
  final PathMap srcPathMap;

  /// The root directory for all source being modified
  /// during performance measurement.
  final String tmpSrcDirPath;

  CommonInputConverter(this.tmpSrcDirPath, this.srcPathMap);

  Map<String, Object?> asMap(dynamic value) => value as Map<String, Object?>;

  Map<String, Object?>? asMap2(dynamic value) => value as Map<String, Object?>?;

  /// Return an operation for the notification or `null` if none.
  Operation? convertNotification(Map<String, dynamic> json) {
    var event = json['event'] as String;
    if (event == SERVER_NOTIFICATION_STATUS) {
      // {"event":"server.status","params":{"analysis":{"isAnalyzing":false}}}
      var params = asMap2(json['params']);
      if (params != null) {
        var analysis = asMap2(params['analysis']);
        if (analysis != null && analysis['isAnalyzing'] == false) {
          return WaitForAnalysisCompleteOperation();
        }
      }
    }
    if (event == SERVER_NOTIFICATION_CONNECTED) {
      // {"event":"server.connected","params":{"version":"1.7.0"}}
      return StartServerOperation();
    }
    if (eventsSeen.add(event)) {
      logger.log(Level.INFO, 'Ignored notification: $event\n  $json');
    }
    return null;
  }

  /// Return an operation for the request or `null` if none.
  Operation convertRequest(Map<String, Object?> origJson) {
    var json = asMap(translateSrcPaths(origJson));
    requestMap[json['id'] as String] = json;
    var method = json['method'] as String;
    // Sanity check operations that modify source
    // to ensure that the operation is on source in temp space
    if (method == ANALYSIS_REQUEST_UPDATE_CONTENT) {
      // Track overlays in parallel with the analysis server
      // so that when an overlay is removed, the file can be updated on disk
      var request = Request.fromJson(json)!;
      var params = AnalysisUpdateContentParams.fromRequest(
        request,
        clientUriConverter: null,
      );
      params.files.forEach((String filePath, change) {
        if (change is AddContentOverlay) {
          var content = change.content;
          overlays[filePath] = content;
        } else if (change is ChangeContentOverlay) {
          var content = overlays[filePath];
          if (content == null) {
            throw 'expected cached overlay content\n$json';
          }
          overlays[filePath] = SourceEdit.applySequence(content, change.edits);
        } else if (change is RemoveContentOverlay) {
          var content = overlays.remove(filePath);
          if (content == null) {
            throw 'expected cached overlay content\n$json';
          }
          if (!path.isWithin(tmpSrcDirPath, filePath)) {
            throw 'found path referencing source outside temp space\n$filePath\n$json';
          }
          File(filePath).writeAsStringSync(content);
        } else {
          throw 'unknown overlay change $change\n$json';
        }
      });
      return RequestOperation(this, json);
    }
    // TODO(danrubel): replace this with code
    // that just forwards the translated request
    if (method == ANALYSIS_REQUEST_GET_HOVER ||
        method == ANALYSIS_REQUEST_SET_ANALYSIS_ROOTS ||
        method == ANALYSIS_REQUEST_SET_PRIORITY_FILES ||
        method == ANALYSIS_REQUEST_SET_SUBSCRIPTIONS ||
        method == ANALYSIS_REQUEST_UPDATE_OPTIONS ||
        method == EDIT_REQUEST_GET_ASSISTS ||
        method == EDIT_REQUEST_GET_AVAILABLE_REFACTORINGS ||
        method == EDIT_REQUEST_GET_FIXES ||
        method == EDIT_REQUEST_GET_REFACTORING ||
        method == EDIT_REQUEST_SORT_MEMBERS ||
        method == EXECUTION_REQUEST_CREATE_CONTEXT ||
        method == EXECUTION_REQUEST_DELETE_CONTEXT ||
        method == EXECUTION_REQUEST_MAP_URI ||
        method == EXECUTION_REQUEST_SET_SUBSCRIPTIONS ||
        method == SEARCH_REQUEST_FIND_ELEMENT_REFERENCES ||
        method == SEARCH_REQUEST_FIND_MEMBER_DECLARATIONS ||
        method == SERVER_REQUEST_GET_VERSION ||
        method == SERVER_REQUEST_SET_SUBSCRIPTIONS) {
      return RequestOperation(this, json);
    }
    throw 'unknown request: $method\n  $json';
  }

  /// Return an operation for the recorded/expected response.
  Operation convertResponse(Map<String, dynamic> json) {
    return ResponseOperation(
      this,
      asMap(requestMap.remove(json['id'])),
      asMap(translateSrcPaths(json)),
    );
  }

  void logOverlayContent() {
    logger.log(Level.WARNING, '${overlays.length} overlays');
    var allPaths = overlays.keys.toList()..sort();
    for (var filePath in allPaths) {
      logger.log(Level.WARNING, 'overlay $filePath\n${overlays[filePath]}');
    }
  }

  /// Process an error response from the server by either
  /// completing the associated completer in the [responseCompleters]
  /// or stashing it in [responseMap] if no completer exists.
  void processErrorResponse(String id, exception) {
    var result = exception;
    if (exception is UnimplementedError) {
      var message = exception.message;
      if (message!.startsWith(_errorPrefix)) {
        result = json.decode(message.substring(_errorPrefix.length));
      }
    }
    processResponseResult(id, result);
  }

  /// Process the expected response by completing the given completer
  /// with the result if it has already been received,
  /// or caching the completer to be completed when the server
  /// returns the associated result.
  /// Return a future that completes when the response is received
  /// or `null` if the response has already been received
  /// and the completer completed.
  Future<void>? processExpectedResponse(
    String id,
    Completer<Object?> completer,
  ) {
    if (responseMap.containsKey(id)) {
      logger.log(Level.INFO, 'processing cached response $id');
      completer.complete(responseMap.remove(id));
      return null;
    } else {
      logger.log(Level.INFO, 'waiting for response $id');
      responseCompleters[id] = completer;
      return completer.future;
    }
  }

  /// Process a success response result from the server by either
  /// completing the associated completer in the [responseCompleters]
  /// or stashing it in [responseMap] if no completer exists.
  /// The response result may be `null`.
  void processResponseResult(String id, result) {
    var completer = responseCompleters[id];
    if (completer != null) {
      logger.log(Level.INFO, 'processing response $id');
      completer.complete(result);
    } else {
      logger.log(Level.INFO, 'caching response $id');
      responseMap[id] = result;
    }
  }

  /// Recursively translate source paths in the specified JSON to reference
  /// the temporary source used during performance measurement rather than
  /// the original source when the instrumentation or log file was generated.
  Object? translateSrcPaths(Object? json) {
    if (json is String) {
      return srcPathMap.translate(json);
    }
    if (json is List) {
      var result = <Object?>[];
      for (var i = 0; i < json.length; ++i) {
        result.add(translateSrcPaths(json[i] as Object?));
      }
      return result;
    }
    if (json is Map) {
      var result = <String, Object?>{};
      json.forEach((origKey, value) {
        result[translateSrcPaths(origKey) as String] = translateSrcPaths(value);
      });
      return result;
    }
    return json;
  }
}

/// [InputConverter] converts an input stream
/// into a series of operations to be sent to the analysis server.
/// The input stream can be either an instrumentation or log file.
class InputConverter extends Converter<String, Operation?> {
  final Logger logger = Logger('InputConverter');

  /// A mapping of source path prefixes
  /// from location where instrumentation or log file was generated
  /// to the target location of the source using during performance measurement.
  final PathMap srcPathMap;

  /// The root directory for all source being modified
  /// during performance measurement.
  final String tmpSrcDirPath;

  /// The number of lines read before the underlying converter was determined
  /// or the end of file was reached.
  int _headerLineCount = 0;

  /// The underlying converter used to translate lines into operations
  /// or `null` if it has not yet been determined.
  Converter<String, Operation?>? _converter;

  /// [_active] is `true` if converting lines to operations
  /// or `false` if an exception has occurred.
  bool _active = true;

  InputConverter(this.tmpSrcDirPath, this.srcPathMap);

  @override
  Operation? convert(String line) {
    if (!_active) {
      return null;
    }
    try {
      var converter = _getConverter(line);
      if (converter == null) {
        logger.log(Level.INFO, 'skipped input line: $line');
        return null;
      }
      return converter.convert(line);
    } catch (_) {
      _active = false;
      rethrow;
    }
  }

  @override
  Sink<String> startChunkedConversion(outSink) {
    return _InputSink(this, outSink);
  }

  /// Return the previously determined converter, or determine it from the
  /// given [line]. Return `null` if cannot be determined yet. Throw an
  /// exception if could not be determined after some number of tries.
  Converter<String, Operation?>? _getConverter(String line) {
    var converter = _converter;
    if (converter != null) {
      return converter;
    }

    if (_headerLineCount++ == 20) {
      throw 'Failed to determine input file format';
    }

    if (InstrumentationInputConverter.isFormat(line)) {
      _converter = InstrumentationInputConverter(tmpSrcDirPath, srcPathMap);
    } else if (LogFileInputConverter.isFormat(line)) {
      _converter = LogFileInputConverter(tmpSrcDirPath, srcPathMap);
    }

    return _converter;
  }
}

/// A container of [PathMapEntry]s used to translate a source path in the log
/// before it is sent to the analysis server.
class PathMap {
  final List<PathMapEntry> entries = [];

  void add(String oldSrcPrefix, String newSrcPrefix) {
    entries.add(PathMapEntry(oldSrcPrefix, newSrcPrefix));
  }

  String translate(String original) {
    var result = original;
    for (var entry in entries) {
      result = entry.translate(result);
    }
    return result;
  }
}

/// An entry in [PathMap] used to translate a source path in the log
/// before it is sent to the analysis server.
class PathMapEntry {
  final String oldSrcPrefix;
  final String newSrcPrefix;

  PathMapEntry(this.oldSrcPrefix, this.newSrcPrefix);

  String translate(String original) {
    return original.startsWith(oldSrcPrefix)
        ? '$newSrcPrefix${original.substring(oldSrcPrefix.length)}'
        : original;
  }
}

class _InputSink implements ChunkedConversionSink<String> {
  final Converter<String, Operation?> converter;
  final Sink<Operation?> outSink;

  _InputSink(this.converter, this.outSink);

  @override
  void add(String line) {
    var op = converter.convert(line);
    if (op != null) {
      outSink.add(op);
    }
  }

  @override
  void close() {
    outSink.close();
  }
}
