// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.control_flow_state;

import '../../ast.dart';

/// Tracks control-flow reachability and variable initialization during an AST
/// traversal.
///
/// The current abstract state can be saved using [branchFrom], and later
/// restored using [resumeBranch], [mergeInto], or [mergeFinally].
class ControlFlowState {
  /// A stack entry contains either:
  /// - null, if the branch cannot complete normally, or
  /// - a set of variables that may be uninitialized at the end of the branch
  final List<Set<VariableDeclaration>> _stack = <Set<VariableDeclaration>>[
    new Set<VariableDeclaration>()
  ];

  /// Identifier for the current branch.
  int get current => _stack.length - 1;

  void declareUninitializedVariable(VariableDeclaration node) {
    _stack.last?.add(node);
  }

  void setInitialized(VariableDeclaration node) {
    _stack.last?.remove(node);
  }

  void terminateBranch() {
    _stack[current] = null;
  }

  bool isDefinitelyInitialized(VariableDeclaration variable) {
    var uninitializedSet = _stack.last;
    return uninitializedSet == null || !uninitializedSet.contains(variable);
  }

  /// Returns true if the end of the current branch is potentially reachable.
  bool get isReachable => _stack.last != null;

  /// Starts a new branch as a copy of [base].
  void branchFrom(int base) {
    var uninitializedSet = _stack[base];
    if (uninitializedSet != null) {
      uninitializedSet = new Set<VariableDeclaration>.from(uninitializedSet);
    }
    _stack.add(uninitializedSet);
  }

  /// Return to the [base] branch and merge the abstract state from its children
  /// assuming at least one of them has completed normally.
  void mergeInto(int base) {
    if (base == current) return;
    _stack[base]?.removeWhere((v) {
      // If the variable is still uninitialized in one of the branches, it
      // remains uninitialized in the parent.
      for (int i = base + 1; i < _stack.length; ++i) {
        var uninitialized = _stack[i];
        if (uninitialized != null && uninitialized.contains(v)) {
          return false;
        }
      }
      return true;
    });
    bool allTerminate = true;
    for (int i = base + 1; i < _stack.length; ++i) {
      if (_stack[i] != null) {
        allTerminate = false;
        break;
      }
    }
    if (allTerminate) {
      _stack[base] = null;
    }
    _stack.removeRange(base + 1, _stack.length);
  }

  /// Return to the [base] branch and merge the abstract state from its children
  /// assuming all of them have completed normally.
  ///
  /// This is used in try/finally blocks.
  void mergeFinally(int base) {
    if (base == current) return;
    _stack[base]?.removeWhere((v) {
      // If the variable was initialized in any branch, it is initialized after
      // finally.
      for (int i = base + 1; i < _stack.length; ++i) {
        var uninitialized = _stack[i];
        if (uninitialized == null || !uninitialized.contains(v)) {
          return true;
        }
      }
      return false;
    });
    // If one child cannot complete normally, neither can the parent.
    for (int i = base + 1; i < _stack.length; ++i) {
      if (_stack[i] == null) {
        _stack[base] = null;
        break;
      }
    }
    _stack.removeRange(base + 1, _stack.length);
  }

  /// Return to the [base] branch without merging any state from its children.
  void resumeBranch(int base) {
    if (base == current) return;
    _stack.removeRange(base + 1, _stack.length);
  }
}
