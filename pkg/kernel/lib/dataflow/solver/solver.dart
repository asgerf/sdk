// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.solver.solver;

import '../../class_hierarchy.dart';
import '../constraints.dart';
import '../storage_location.dart';
import '../value.dart';
import 'package:kernel/core_types.dart';

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
  final ValueLattice lattice;
  final ConstraintSystem constraints;
  final List<WorkItem> worklist = <WorkItem>[];
  final SolverListener report;

  ConstraintSolver(
      CoreTypes coreTypes, ClassHierarchy hierarchy, this.constraints,
      {this.report, ValueLattice lattice})
      : this.lattice = lattice ?? new ValueLattice(coreTypes, hierarchy);

  void propagateValue(StorageLocation location, Value inputValue) {
    Value oldValue = location.value;
    Value newValue = lattice.joinValues(oldValue, inputValue);
    if (!identical(oldValue, newValue)) {
      location.value = newValue;
      enqueue(location.forward);
      report?.onChange(location, newValue, location.leadsToEscape);
    }
  }

  void propagateValueFlags(StorageLocation location, int inputFlags) {
    Value oldValue = location.value;
    int oldFlags = oldValue.flags;
    int newFlags = oldFlags | inputFlags;
    if (oldFlags != newFlags) {
      var newValue = new Value(oldValue.baseClass, newFlags);
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

  void transferGuardedValueConstraint(GuardedValueConstraint constraint) {
    if (constraint.guard.value.flags & constraint.guardMask != 0) {
      propagateValue(constraint.destination, constraint.value);
    }
  }

  void transferAssignConstraint(AssignConstraint constraint) {
    var source = constraint.source;
    var destination = constraint.destination;
    propagateValue(destination, source.value.masked(constraint.mask));
    if (constraint.canEscape && destination.leadsToEscape) {
      propagateEscapingLocation(source);
    }
  }

  void transferValueConstraint(ValueConstraint constraint) {
    propagateValue(constraint.destination, constraint.value);
    if (constraint.canEscape) {
      propagateEscapingValue(constraint.destination);
    }
  }

  void transferEscapeConstraint(EscapeConstraint constraint) {
    if (constraint.guard == null || constraint.guard.leadsToEscape) {
      propagateEscapingLocation(constraint.escaping);
    }
  }

  void transferTypeFilterConstraint(TypeFilterConstraint constraint) {
    var source = constraint.source;
    var interfaceClass = constraint.interfaceClass;
    var destination = constraint.destination;
    int mask = constraint.mask;
    var output =
        lattice.restrictValueToInterface(source.value, interfaceClass, mask);
    propagateValue(destination, output);
    if (destination.leadsToEscape && canEscape(output)) {
      propagateEscapingLocation(source);
    }
  }

  void transferValueFilterConstraint(ValueFilterConstraint constraint) {
    var source = constraint.source;
    var destination = constraint.destination;
    var guard = constraint.guard;
    var output = lattice.intersectValues(source.value, guard);
    propagateValue(destination, output);
    if (destination.leadsToEscape && canEscape(output)) {
      propagateEscapingLocation(source);
    }
  }

  void transferInstanceMembersConstraint(InstanceMembersConstraint constraint) {
    int mask = 0;
    if (constraint.hashCodeReturn.value.canBeNull) {
      mask |= ValueFlags.nullableHashCode;
    }
    if (constraint.toStringReturn.value.canBeNull) {
      mask |= ValueFlags.nullableToString;
    }
    if (constraint.equalsReturn.value.canBeNull) {
      mask |= ValueFlags.nullableEquals;
    }
    if (constraint.runtimeTypeReturn.value.canBeNull) {
      mask |= ValueFlags.nullableRuntimeType;
    }
    propagateValueFlags(constraint.destination, mask);
  }

  bool canEscape(Value value) {
    return value.flags & ValueFlags.other != 0;
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

  void registerGuardedValueConstraint(GuardedValueConstraint constraint) {
    addForwardDependency(constraint.guard, constraint);
  }

  void registerAssignConstraint(AssignConstraint constraint) {
    addForwardDependency(constraint.source, constraint);
    addBackwardDependency(constraint.destination, constraint);
  }

  void registerValueConstraint(ValueConstraint constraint) {
    if (constraint.canEscape) {
      addBackwardDependency(constraint.destination, constraint);
    }
  }

  void registerEscapeConstraint(EscapeConstraint constraint) {
    if (constraint.guard != null) {
      addForwardDependency(constraint.guard, constraint);
    }
  }

  void registerTypeFilterConstraint(TypeFilterConstraint constraint) {
    addForwardDependency(constraint.source, constraint);
    addBackwardDependency(constraint.destination, constraint);
  }

  void registerValueFilterConstraint(ValueFilterConstraint constraint) {
    addForwardDependency(constraint.source, constraint);
    addBackwardDependency(constraint.destination, constraint);
  }

  void registerInstanceMembersConstraint(InstanceMembersConstraint constraint) {
    addForwardDependency(constraint.hashCodeReturn, constraint);
    addForwardDependency(constraint.toStringReturn, constraint);
    addForwardDependency(constraint.equalsReturn, constraint);
    addForwardDependency(constraint.runtimeTypeReturn, constraint);
  }

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
