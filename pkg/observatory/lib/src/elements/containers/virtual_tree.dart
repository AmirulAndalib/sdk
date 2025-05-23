// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as Math;

import 'package:web/web.dart';

import 'virtual_collection.dart';
import '../helpers/custom_element.dart';
import '../helpers/rendering_scheduler.dart';

typedef HTMLElement VirtualTreeCreateCallback(
  toggle({bool autoToggleSingleChildNodes, bool autoToggleWholeTree}),
);
typedef void VirtualTreeUpdateCallback(HTMLElement el, dynamic item, int depth);
typedef Iterable<dynamic> VirtualTreeGetChildrenCallback(dynamic value);
typedef bool VirtualTreeSearchCallback(Pattern pattern, dynamic item);

void virtualTreeUpdateLines(HTMLSpanElement element, int n) {
  n = Math.max(0, n);
  while (element.children.length > n) {
    element.removeChild(element.lastChild!);
  }
  while (element.children.length < n) {
    element.appendChild(HTMLSpanElement());
  }
}

class VirtualTreeElement extends CustomElement implements Renderable {
  late RenderingScheduler<VirtualTreeElement> _r;

  Stream<RenderedEvent<VirtualTreeElement>> get onRendered => _r.onRendered;

  late VirtualTreeGetChildrenCallback _children;
  late List _items;
  late List _depths;
  final Set _expanded = new Set();

  List get items => _items;

  set items(Iterable value) {
    _items = new List.unmodifiable(value);
    _expanded.clear();
    _r.dirty();
  }

  factory VirtualTreeElement(
    VirtualTreeCreateCallback create,
    VirtualTreeUpdateCallback update,
    VirtualTreeGetChildrenCallback children, {
    Iterable items = const [],
    VirtualTreeSearchCallback? search,
    RenderingQueue? queue,
  }) {
    VirtualTreeElement e = new VirtualTreeElement.created();
    e._r = new RenderingScheduler<VirtualTreeElement>(e, queue: queue);
    e._children = children;
    e._collection = new VirtualCollectionElement(
      () {
        var element;
        return element = create(({
          bool autoToggleSingleChildNodes = false,
          bool autoToggleWholeTree = false,
        }) {
          var item = e._collection!.getItemFromElement(element);
          if (e.isExpanded(item)) {
            e.collapse(
              item,
              autoCollapseWholeTree: autoToggleWholeTree,
              autoCollapseSingleChildNodes: autoToggleSingleChildNodes,
            );
          } else {
            e.expand(
              item,
              autoExpandWholeTree: autoToggleWholeTree,
              autoExpandSingleChildNodes: autoToggleSingleChildNodes,
            );
          }
        });
      },
      (HTMLElement el, dynamic item, int index) {
        update(el, item, e._depths[index]);
      },
      search: search,
      queue: queue,
    );
    e._items = new List.unmodifiable(items);
    return e;
  }

  VirtualTreeElement.created() : super.created('virtual-tree');

  bool isExpanded(item) {
    return _expanded.contains(item);
  }

  void expand(
    item, {
    bool autoExpandSingleChildNodes = false,
    bool autoExpandWholeTree = false,
  }) {
    if (_expanded.add(item)) _r.dirty();
    if (autoExpandWholeTree) {
      // The tree is potentially very deep, simple recursion can produce a
      // Stack Overflow
      Queue pendingNodes = new Queue();
      pendingNodes.addAll(_children(item));
      while (pendingNodes.isNotEmpty) {
        final item = pendingNodes.removeFirst();
        if (_expanded.add(item)) _r.dirty();
        pendingNodes.addAll(_children(item));
      }
    } else if (autoExpandSingleChildNodes) {
      var children = _children(item);
      while (children.length == 1) {
        _expanded.add(children.first);
        children = _children(children.first);
      }
    }
  }

  void collapse(
    item, {
    bool autoCollapseSingleChildNodes = false,
    bool autoCollapseWholeTree = false,
  }) {
    if (_expanded.remove(item)) _r.dirty();
    if (autoCollapseWholeTree) {
      // The tree is potentially very deep, simple recursion can produce a
      // Stack Overflow
      Queue pendingNodes = new Queue();
      pendingNodes.addAll(_children(item));
      while (pendingNodes.isNotEmpty) {
        final item = pendingNodes.removeFirst();
        if (_expanded.remove(item)) _r.dirty();
        pendingNodes.addAll(_children(item));
      }
    } else if (autoCollapseSingleChildNodes) {
      var children = _children(item);
      while (children.length == 1) {
        _expanded.remove(children.first);
        children = _children(children.first);
      }
    }
  }

  @override
  attached() {
    super.attached();
    _r.enable();
  }

  @override
  detached() {
    super.detached();
    _r.disable(notify: true);
    children = const [];
  }

  VirtualCollectionElement? _collection;

  void render() {
    if (children.length == 0) {
      children = <HTMLElement>[_collection!.element];
    }

    final items = [];
    final depths = new List.filled(_items.length, 0, growable: true);

    {
      final toDo = new Queue();

      toDo.addAll(_items);
      while (toDo.isNotEmpty) {
        final item = toDo.removeFirst();

        items.add(item);
        if (isExpanded(item)) {
          final children = _children(item);
          children
              .toList(growable: false)
              .reversed
              .forEach((c) => toDo.addFirst(c));
          final depth = depths[items.length - 1];
          depths.insertAll(
            items.length,
            new List.filled(children.length, depth + 1),
          );
        }
      }
    }

    _depths = depths;
    _collection!.items = items;

    _r.waitFor([_collection!.onRendered.first]);
  }
}
