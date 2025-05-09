// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library;

// ignore: implementation_imports
import 'package:js_ast/src/precedence.dart' as js_precedence;

import '../common.dart';
import '../deferred_load/output_unit.dart' show OutputUnit;

import '../elements/types.dart';
import '../js/js.dart' as js_ast;
import '../js_backend/runtime_types_new.dart' show RecipeEncoder;
import '../js_model/type_recipe.dart' show TypeExpressionRecipe;

import 'js_emitter.dart' show ModularEmitter;

/// Represents an entry's position in one of the global metadata arrays.
///
/// [_rc] is used to count the number of references of the token in the
/// ast for a program.
/// [value] is the actual position, once they have been finalized.
abstract class MetadataEntry extends js_ast.DeferredNumber
    implements Comparable<MetadataEntry>, js_ast.ReferenceCountedAstNode {
  js_ast.Expression get entry;
  @override
  int get value;
  int get _rc;

  // Mark this entry as seen. On the first time this is seen, the visitor
  // will be applied to the [entry] to also mark potential [_MetadataEntry]
  // instances in the [entry] as seen.
  @override
  void markSeen(js_ast.TokenCounter visitor);
}

class BoundMetadataEntry extends MetadataEntry {
  int _value = -1;
  @override
  int _rc = 0;
  @override
  final js_ast.Expression entry;

  BoundMetadataEntry(this.entry);

  @override
  bool get isFinalized => _value != -1;

  void finalize(int value) {
    assert(!isFinalized);
    _value = value;
  }

  @override
  int get value {
    assert(isFinalized);
    return _value;
  }

  bool get isUsed => _rc > 0;

  @override
  void markSeen(js_ast.TokenCounter visitor) {
    _rc++;
    if (_rc == 1) entry.accept(visitor);
  }

  @override
  int compareTo(MetadataEntry other) => other._rc - _rc;

  @override
  String toString() => 'BoundMetadataEntry($hashCode,rc=$_rc,_value=$_value)';
}

class _MetadataList extends js_ast.DeferredExpression {
  late final js_ast.Expression _value;

  void setExpression(js_ast.Expression value) {
    assert(value.precedenceLevel == precedenceLevel);
    _value = value;
  }

  @override
  js_ast.Expression get value {
    return _value;
  }

  @override
  js_precedence.Precedence get precedenceLevel =>
      js_precedence.Precedence.primary;
}

class MetadataCollector implements js_ast.TokenFinalizer {
  final DiagnosticReporter reporter;
  final ModularEmitter _emitter;
  final RecipeEncoder _rtiRecipeEncoder;

  /// A map used to canonicalize the entries of metadata.
  final Map<OutputUnit, Map<String, List<BoundMetadataEntry>>> _metadataMap =
      {};

  /// A map with a token for a lists of JS expressions, one token for each
  /// output unit. Once finalized, the entries represent types including
  /// function types and typedefs.
  final Map<OutputUnit, _MetadataList> _typesTokens = {};

  /// A map used to canonicalize the entries of types.
  final Map<OutputUnit, Map<DartType, List<BoundMetadataEntry>>> _typesMap = {};

  MetadataCollector(this.reporter, this._emitter, this._rtiRecipeEncoder);

  js_ast.Expression getTypesForOutputUnit(OutputUnit outputUnit) {
    return _typesTokens.putIfAbsent(outputUnit, () => _MetadataList());
  }

  void mergeOutputUnitMetadata(OutputUnit target, OutputUnit source) {
    assert(target != source);

    // Merge _metadataMap
    var sourceMetadataMap = _metadataMap[source];
    if (sourceMetadataMap != null) {
      var targetMetadataMap = _metadataMap[target] ??= {};
      _metadataMap.remove(source);
      sourceMetadataMap.forEach((str, entries) {
        var targetMetadataMapList = targetMetadataMap[str] ??= [];
        targetMetadataMapList.addAll(entries);
      });
    }

    // Merge _typesMap
    var sourceTypesMap = _typesMap[source];
    if (sourceTypesMap != null) {
      var targetTypesMap = _typesMap[target] ??= {};
      _typesMap.remove(source);
      sourceTypesMap.forEach((type, entries) {
        var targetTypesMapList = targetTypesMap[type] ??= [];
        targetTypesMapList.addAll(entries);
      });
    }
  }

  js_ast.Expression reifyType(DartType type, OutputUnit outputUnit) {
    return _addTypeInOutputUnit(type, outputUnit);
  }

  js_ast.Expression _computeTypeRepresentation(DartType type) {
    return _rtiRecipeEncoder.encodeGroundRecipe(
      _emitter,
      TypeExpressionRecipe(type),
    );
  }

  js_ast.Expression _addTypeInOutputUnit(DartType type, OutputUnit outputUnit) {
    final typeMap = _typesMap[outputUnit] ??= {};
    final metadataEntryList = (typeMap[type] ??= [
      BoundMetadataEntry(_computeTypeRepresentation(type)),
    ]);
    return metadataEntryList.single;
  }

  @override
  void finalizeTokens() {
    void countTokensInTypes(Iterable<BoundMetadataEntry> entries) {
      js_ast.TokenCounter counter = js_ast.TokenCounter();
      entries
          .where((BoundMetadataEntry e) => e._rc > 0)
          .map((BoundMetadataEntry e) => e.entry)
          .forEach(counter.countTokens);
    }

    js_ast.ArrayInitializer finalizeMap(
      Map<dynamic, List<BoundMetadataEntry>> map,
    ) {
      List<BoundMetadataEntry> entries = [
        for (var entriesList in map.values)
          for (var entry in entriesList)
            if (entry.isUsed) entry,
      ];
      entries.sort();

      // TODO(herhut): Bucket entries by index length and use a stable
      //               distribution within buckets.
      int count = 0;
      for (BoundMetadataEntry entry in entries) {
        entry.finalize(count++);
      }

      final values = entries.map((BoundMetadataEntry e) => e.entry).toList();

      return js_ast.ArrayInitializer(values);
    }

    _typesTokens.forEach((OutputUnit outputUnit, _MetadataList token) {
      final typesMap = _typesMap[outputUnit];
      if (typesMap != null) {
        typesMap.values.forEach(countTokensInTypes);
        token.setExpression(finalizeMap(typesMap));
      } else {
        token.setExpression(js_ast.ArrayInitializer([]));
      }
    });
  }
}
