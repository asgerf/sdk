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
  bool leadsToEscape = false;
  final WorkItem forward = new WorkItem();
  final WorkItem backward = new WorkItem();

  // TODO: We should try to avoid having two WorkItem objects per storage
  // location, as there are going to be a lot of these objects.
  // The three booleans leadsToEscape, and {foward,backward}.isInWorklist
  // can be stored in a single bitmask, the lists can be inlined, but then the
  // worklist needs to distinguish if the item is forward or backward use, or
  // it can just trigger both if both were marked as being in the worklist.
}

class WorkItem {
  final List<Constraint> dependencies = <Constraint>[];
  bool isInWorklist = false;
}

abstract class SolverListener {
  void onBeginTransfer(Constraint constraint);
  void onChange(StorageLocation location, Value value, bool leadsToEscape);
}

class ConstraintSolver {
  final ClassHierarchy hierarchy;
  final ConstraintSystem constraints;
  final List<WorkItem> worklist = <WorkItem>[];
  final SolverListener report;

  ConstraintSolver(this.hierarchy, this.constraints, [this.report]);

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
        newFlags |= ValueFlags.inexactBaseClass;
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
      report?.onChange(location, newValue, location.leadsToEscape);
    }
  }

  void propagateEscapingLocation(StorageLocation location) {
    if (!location.leadsToEscape) {
      location.leadsToEscape = true;
      enqueue(location.backward);
      report?.onChange(location, location.value, true);
    }
  }

  void propagateEscapingValue(StorageLocation location) {
    // The escaping bit on values propagate forward (i.e. the value has escaped)
    // whereas the escaping bit on locations propagate backwards (i.e. incoming
    // values will escape).  This method propagates the bit from an escaping
    // location to the value in that location.
    if (location.leadsToEscape) {
      Value oldValue = location.value;
      int oldFlags = oldValue.flags;
      int newFlags = oldFlags | ValueFlags.escaping;
      if (oldFlags != newFlags) {
        var newValue = new Value(oldValue.baseClass, newFlags);
        location.value = newValue;
        enqueue(location.forward);
        report?.onChange(location, newValue, location.leadsToEscape);
      }
    }
  }

  void enqueue(WorkItem work) {
    if (!work.isInWorklist) {
      work.isInWorklist = true;
      worklist.add(work);
    }
  }

  void transferTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    if (constraint.createdObject.leadsToEscape) {
      propagateValue(constraint.typeArgument, constraint.value);
    }
  }

  void transferSubtypeConstraint(SubtypeConstraint constraint) {
    var source = constraint.source;
    var destination = constraint.destination;
    propagateValue(destination, source.value.masked(constraint.mask));
    if (constraint.canEscape && destination.leadsToEscape) {
      propagateEscapingLocation(constraint.source);
    }
  }

  void transferValueConstraint(ValueConstraint constraint) {
    propagateValue(constraint.destination, constraint.value);
    if (constraint.canEscape) {
      propagateEscapingValue(constraint.destination);
    }
  }

  void transferEscapeConstraint(EscapeConstraint constraint) {
    propagateEscapingLocation(constraint.escaping);
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

  void doTransfer(Constraint constraint) {
    report?.onBeginTransfer(constraint);
    constraint.transfer(this);
  }

  void solve() {
    constraints.forEachConstraint((constraint) {
      constraint.register(this);
    });
    constraints.forEachConstraint((constraint) {
      doTransfer(constraint);
    });
    while (worklist.isNotEmpty) {
      WorkItem item = worklist.removeLast();
      item.isInWorklist = false;
      for (var constraint in item.dependencies) {
        doTransfer(constraint);
      }
    }
  }
}
