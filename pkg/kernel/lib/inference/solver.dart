// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.solver;

import '../ast.dart';
import '../class_hierarchy.dart';
import 'constraints.dart';
import 'key.dart';
import 'value.dart';

class WorkItem {
  final Key key;
  final List<Constraint> dependencies = <Constraint>[];

  WorkItem(this.key);

  bool isInWorklist = false;
}

class ConstraintSolver {
  final ClassHierarchy hierarchy;
  final List<Constraint> constraints;
  final List<WorkItem> worklist = <WorkItem>[];

  ConstraintSolver(this.hierarchy, this.constraints);

  Class get rootClass => hierarchy.classes[0];

  /// Update [supertype] to contain the values of [subtype].
  bool mergeForward(Value subtype, Value supertype) {
    int oldFlags = supertype.flags;
    int inputFlags = subtype.flags & Flags.forward;
    int newFlags = oldFlags | inputFlags;
    bool changed = false;
    if (supertype.baseClass != subtype.baseClass) {
      newFlags |= Flags.inexactBaseClass;
      Class newBaseClass =
          hierarchy.getCommonBaseClass(supertype.baseClass, subtype.baseClass);
      if (newBaseClass != supertype.baseClass) {
        supertype.baseClass = newBaseClass;
        changed = true;
      }
    }
    if (newFlags != oldFlags) {
      supertype.flags = newFlags;
      changed = true;
    }
    return changed;
  }

  /// Update [subtype] to contain the escape information of [supertype].
  bool mergeBackward(Value subtype, Value supertype) {
    int oldFlags = supertype.flags;
    int inputFlags = subtype.flags & Flags.backward;
    int newFlags = oldFlags | inputFlags;
    if (newFlags != oldFlags) {
      supertype.flags = newFlags;
      return true;
    }
    return false;
  }

  void propagateForward(Value subtype, Key supertype) {
    if (mergeForward(subtype, supertype.value)) {
      enqueue(supertype.forward);
    }
  }

  void propagateBackward(Key subtype, Value supertype) {
    if (mergeBackward(subtype.value, supertype)) {
      enqueue(subtype.backward);
    }
  }

  void enqueue(WorkItem work) {
    if (!work.isInWorklist) {
      work.isInWorklist = true;
      worklist.add(work);
    }
  }

  void transferTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    Value createdObject = constraint.createdObject.value;
    if (createdObject.isEscaping) {
      Value worstCase =
          new Value(rootClass, Flags.all); // TODO: exploit interface type
      propagateForward(worstCase, constraint.typeArgument);
    }
  }

  void transferSubtypeConstraint(SubtypeConstraint constraint) {
    propagateForward(constraint.source.value.masked(constraint.mask),
        constraint.destination);
    propagateBackward(constraint.source, constraint.destination.value);
  }

  void transferValueConstraint(ValueConstraint constraint) {
    propagateForward(constraint.value, constraint.destination);
  }

  /// The [constraint] must be executed whenever the forward properties of
  /// the given [key] changes.
  void addForwardDependency(Key key, Constraint constraint) {
    key.forward.dependencies.add(constraint);
  }

  /// The [constraint] must be executed whenever the backward properties of
  /// the given [key] changes.
  void addBackwardDependency(Key key, Constraint constraint) {
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
