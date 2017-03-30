// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.control_flow_state;

import '../../ast.dart';

class ControlFlowState {
  /// A stack entry contains either:
  /// - null, if the branch cannot complete normally, or
  /// - a set of variables that may be uninitialized at the end of the branch
  final List<Set<VariableDeclaration>> stack = <Set<VariableDeclaration>>[
    new Set<VariableDeclaration>()
  ];

  int get current => stack.length - 1;

  void declareUninitializedVariable(VariableDeclaration node) {
    stack.last?.add(node);
  }

  void setInitialized(VariableDeclaration node) {
    stack.last?.remove(node);
  }

  void terminateBranch() {
    stack[current] = null;
  }

  bool isDefinitelyInitialized(VariableDeclaration variable) {
    var uninitializedSet = stack.last;
    return uninitializedSet == null || !uninitializedSet.contains(variable);
  }

  bool get isReachable => stack.last != null;

  void branchFrom(int base) {
    var uninitializedSet = stack[base];
    if (uninitializedSet != null) {
      uninitializedSet = new Set<VariableDeclaration>.from(uninitializedSet);
    }
    stack.add(uninitializedSet);
  }

  /// Return to the [base] branch and merge the abstract state from its children
  /// assuming at least one of them has completed normally.
  void mergeInto(int base) {
    if (base == current) return;
    stack[base]?.removeWhere((v) {
      // If it is still uninitialized in one of the branches, keep it as
      // uninitialized in the parent.
      for (int i = base + 1; i < stack.length; ++i) {
        var uninitialized = stack[i];
        if (uninitialized != null && uninitialized.contains(v)) {
          return false;
        }
      }
      return true;
    });
    bool allTerminate = true;
    for (int i = base + 1; i < stack.length; ++i) {
      if (stack[i] != null) {
        allTerminate = false;
        break;
      }
    }
    if (allTerminate) {
      stack[base] = null;
    }
    stack.removeRange(base + 1, stack.length);
  }

  /// Return to the [base] branch and merge the abstract state from its children
  /// assuming all of them have completed normally.
  ///
  /// This is used try/finally blocks.
  void mergeFinally(int base) {
    if (base == current) return;
    stack[base]?.removeWhere((v) {
      // If the variable was initialized in any branch, it is initialized after
      // finally.
      for (int i = base + 1; i < stack.length; ++i) {
        var uninitialized = stack[i];
        if (uninitialized == null || !uninitialized.contains(v)) {
          return true;
        }
      }
      return false;
    });
    // If one child cannot complete normally, neither can the parent.
    for (int i = base + 1; i < stack.length; ++i) {
      if (stack[i] == null) {
        stack[base] = null;
        break;
      }
    }
    stack.removeRange(base + 1, stack.length);
  }

  /// Return to the [base] branch without merging any state from its children.
  void resumeBranch(int base) {
    if (base == current) return;
    stack.removeRange(base + 1, stack.length);
  }
}
