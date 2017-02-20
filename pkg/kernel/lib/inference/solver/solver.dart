// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.solver.solver;

import '../../ast.dart';
import '../../class_hierarchy.dart';
import '../constraints.dart';
import '../storage_location.dart';
import '../value.dart';

/// A base class for [StorageLocation] with some fields that are owned by the
/// constraint solver.
class StorageLocationBaseClass {
  Value value = Value.bottom;
  int escapeFlags = EscapeFlags.none;
  WorkItem forward, backward;

  StorageLocationBaseClass() {
    forward = new WorkItem(this);
    backward = new WorkItem(this);
  }

  bool get isEscaping {
    return escapeFlags & EscapeFlags.escaping != 0;
  }
}

class WorkItem {
  final StorageLocation key;
  final List<Constraint> dependencies = <Constraint>[];
  bool isInWorklist = false;

  WorkItem(this.key);
}

class ConstraintSolver {
  final ClassHierarchy hierarchy;
  final List<Constraint> constraints;
  final List<WorkItem> worklist = <WorkItem>[];

  ConstraintSolver(this.hierarchy, this.constraints);

  Class get rootClass => hierarchy.classes[0];

  /// Returns the least upper bound of the two values, and reuses the [oldValue]
  /// object if it is equal to the result.
  ///
  /// The caller may check if the result is `identical` to [oldValue] to detect
  /// if the value has changed.
  Value joinValues(Value oldValue, Value inputValue) {
    int oldFlags = oldValue.flags;
    int inputFlags = inputValue.flags;
    int newFlags = oldFlags | inputFlags;
    Class oldBaseClass = oldValue.baseClass;
    Class inputBaseClass = inputValue.baseClass;
    Class newBaseClass = oldBaseClass;
    if (inputBaseClass != null && oldBaseClass != inputBaseClass) {
      if (oldBaseClass != null) {
        newFlags |= Flags.inexactBaseClass;
      }
      newBaseClass = getCommonBaseClass(oldBaseClass, inputBaseClass);
    }
    if (newBaseClass != oldBaseClass || newFlags != oldFlags) {
      return new Value(newBaseClass, newFlags);
    }
    return oldValue;
  }

  /// Returns the least upper bound of two base classes, where `null` represents
  /// bottom.
  Class getCommonBaseClass(Class first, Class second) {
    if (first == null) return second;
    if (second == null) return first;
    return hierarchy.getCommonBaseClass(first, second);
  }

  void propagateValue(StorageLocation location, Value inputValue) {
    Value oldValue = location.value;
    Value newValue = joinValues(oldValue, inputValue);
    if (!identical(oldValue, newValue)) {
      location.value = newValue;
      enqueue(location.forward);
    }
  }

  void propagateEscape(StorageLocation location, int escapeFlags) {
    int oldFlags = location.escapeFlags;
    var newFlags = oldFlags | escapeFlags;
    if (oldFlags != newFlags) {
      location.escapeFlags = newFlags;
      enqueue(location.backward);
    }
  }

  void enqueue(WorkItem work) {
    if (!work.isInWorklist) {
      work.isInWorklist = true;
      worklist.add(work);
    }
  }

  void transferTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    if (constraint.createdObject.isEscaping) {
      propagateValue(constraint.typeArgument, constraint.value);
    }
  }

  void transferSubtypeConstraint(SubtypeConstraint constraint) {
    propagateValue(constraint.destination,
        constraint.source.value.masked(constraint.mask));
    propagateEscape(constraint.source, constraint.destination.escapeFlags);
  }

  void transferValueConstraint(ValueConstraint constraint) {
    propagateValue(constraint.destination, constraint.value);
  }

  void transferEscapeConstraint(EscapeConstraint constraint) {
    propagateEscape(constraint.escaping, EscapeFlags.escaping);
  }

  /// The [constraint] must be executed whenever the forward properties of
  /// the given [key] changes.
  void addForwardDependency(StorageLocation key, Constraint constraint) {
    key.forward.dependencies.add(constraint);
  }

  /// The [constraint] must be executed whenever the backward properties of
  /// the given [key] changes.
  void addBackwardDependency(StorageLocation key, Constraint constraint) {
    key.backward.dependencies.add(constraint);
  }

  void registerTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    addBackwardDependency(constraint.createdObject, constraint);
  }

  void registerSubtypeConstraint(SubtypeConstraint constraint) {
    addForwardDependency(constraint.source, constraint);
    addBackwardDependency(constraint.destination, constraint);
  }

  void registerValueConstraint(ValueConstraint constraint) {}

  void registerEscapeConstraint(EscapeConstraint constraint) {}

  void solve() {
    for (var constraint in constraints) {
      constraint.register(this);
    }
    for (var constraint in constraints) {
      constraint.transfer(this);
    }
    while (worklist.isNotEmpty) {
      WorkItem item = worklist.removeLast();
      item.isInWorklist = false;
      for (var constraint in item.dependencies) {
        constraint.transfer(this);
      }
    }
  }
}

class EscapeFlags {
  static const int none = 0;
  static const int escaping = 1 << 0;
}
