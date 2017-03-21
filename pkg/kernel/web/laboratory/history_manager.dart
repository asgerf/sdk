// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.history;

import 'dart:html';

import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/canonical_name.dart';

HistoryManager history;

/// Interacts with the browser's navigation history to make the back button
/// work.
///
/// UI components should call [push] with a [HistoryItem] to add an item to the
/// history.  This class will decode the history item when the back button
/// pressed, and update the UI accordingly.
///
/// When the back button is pressed, the top-most history item is discarded
/// and the second-from-top is used to restore the UI.
///
/// Best practices for pushing history items:
///
/// - Only push history items in a UI event handler.
///   This ensures the history reflects the user's actions and not a chain of
///   internal steps.
///
/// - Optionally push an item describing where we came from.
///
/// - Always push an item describing where we are going.
///
class HistoryManager {
  HistoryManager() {
    window.onPopState.listen(onPopState);
  }

  void onPopState(PopStateEvent event) {
    if (event.state == null) return;
    if (program == null) return;
    var item = HistoryItem.fromJson(event.state, program.root);
    event.stopPropagation();
    event.preventDefault();
    if (item.timestamp != -1) {
      ui.backtracker.currentTimestamp = item.timestamp;
    }
    if (item.reference != null) {
      if (item.constraintIndex != -1) {
        var constraint = constraintSystem.getConstraint(
            item.reference, item.constraintIndex);
        ui.codeView.showConstraint(constraint);
      } else {
        ui.codeView.showObject(item.reference);
      }
    }
  }

  void push(HistoryItem item) {
    if (item == null) return;
    window.history.pushState(item.toJson(), '', '#');
  }

  void replace(HistoryItem item) {
    if (item == null) return;
    window.history.replaceState(item.toJson(), '', '#');
  }
}

class HistoryItem {
  final Reference reference;

  /// The constraint focused by the backtracker.
  final int constraintIndex;

  final int timestamp;

  HistoryItem(this.reference, {this.constraintIndex: -1, this.timestamp: -1});

  Object toJson() => {
        'canonicalName': serializeCanonicalName(reference?.canonicalName),
        'constraintIndex': constraintIndex,
        'timestamp': timestamp,
      };

  String serializeCanonicalName(CanonicalName name) {
    if (name == null) return null;
    if (name.parent.isRoot) return name.name;
    return serializeCanonicalName(name.parent) + '::${name.name}';
  }

  static CanonicalName deserializeCanonicalName(
      String string, CanonicalName root) {
    if (string == null) return null;
    var name = root;
    for (var part in string.split('::')) {
      name = name.getChild(part);
    }
    return name;
  }

  static HistoryItem fromJson(Map map, CanonicalName root) {
    return new HistoryItem(
      deserializeCanonicalName(map['canonicalName'], root)?.reference,
      constraintIndex: map['constraintIndex'],
      timestamp: map['timestamp'],
    );
  }
}
