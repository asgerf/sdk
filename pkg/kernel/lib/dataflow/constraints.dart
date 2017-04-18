// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.constraints;

import '../ast.dart';
import 'storage_location.dart';
import 'solver/solver.dart';
import 'value.dart';

/// Constraint system used for dataflow analysis.
///
/// A constraint system is divided into clusters, with each cluster owned by a
/// class or member.  Each cluster contains a list of storage locations and a
/// list of constraints.  Constraints can reference any storage location from
/// any cluster.
class ConstraintSystem {
  final Map<Reference, ConstraintCluster> clusters =
      <Reference, ConstraintCluster>{};

  ConstraintCluster getCluster(Reference owner) {
    return clusters[owner] ??= new ConstraintCluster(owner);
  }

  Constraint getConstraint(Reference owner, int index) {
    return clusters[owner].constraints[index];
  }

  StorageLocation getStorageLocation(Reference owner, int index) {
    var cluster = clusters[owner];
    if (cluster == null) {
      throw 'There are no bindings for $owner';
    }
    return cluster.locations[index];
  }

  StorageLocation getBoundLocation(TypeParameterStorageLocation typeParameter) {
    return getStorageLocation(typeParameter.owner, typeParameter.indexOfBound);
  }

  void addConstraint(Constraint constraint, Reference owner, int fileOffset) {
    var cluster = clusters[owner] ??= new ConstraintCluster(owner);
    cluster.addConstraint(constraint, fileOffset);
  }

  void forEachConstraint(void action(Constraint constraint)) {
    for (var cluster in clusters.values) {
      cluster.constraints.forEach(action);
    }
  }

  int get numberOfConstraints {
    int sum = 0;
    for (var group in clusters.values) {
      sum += group.constraints.length;
    }
    return sum;
  }
}

/// A constraint cluster is the part of a constraint system that is specific
/// to a class or member (called its [owner]).
///
/// It mainly consists of storage locations and constraints.
class ConstraintCluster {
  final Reference owner;
  List<TypeParameterStorageLocation> typeParameters =
      <TypeParameterStorageLocation>[];
  final List<StorageLocation> locations = <StorageLocation>[];
  final List<Constraint> constraints = <Constraint>[];

  ConstraintCluster(this.owner);

  void addConstraint(Constraint constraint, int fileOffset) {
    assert(constraint.owner == null);
    assert(constraint.index == null);
    assert(constraint.fileOffset == -1);
    constraint.owner = owner;
    constraint.index = constraints.length;
    constraint.fileOffset = fileOffset;
    constraints.add(constraint);
  }

  StorageLocation getStorageLocation(int index) => locations[index];
}

abstract class Constraint {
  /// The constraint cluster to which this constraint belongs.
  Reference owner;

  /// The index of the constraint in its cluster.
  int index;

  /// Source location of the code that gave rise to this constraint.
  ///
  /// This is not enough information to fully determine why a constraint was
  /// created, though it gives a good idea where it came from.
  int fileOffset = -1;

  void transfer(ConstraintSolver solver);
  void register(ConstraintSolver solver);
  T accept<T>(ConstraintVisitor<T> visitor);
}

abstract class ConstraintVisitor<T> {
  T visitAssignConstraint(AssignConstraint constraint);
  T visitValueConstraint(ValueConstraint constraint);
  T visitEscapeConstraint(EscapeConstraint constraint);
  T visitGuardedValueConstraint(GuardedValueConstraint constraint);
  T visitTypeFilterConstraint(TypeFilterConstraint constraint);
  T visitValueFilterConstraint(ValueFilterConstraint constraint);
  T visitInstanceMembersConstraint(InstanceMembersConstraint constraint);
}

/// Any value in [source] matching [mask] can flow into [destination].
///
/// If [destination] escapes, so does [source], unless [mask] does not contain
/// [ValueFlags.escaping].
///
/// In most cases, the [mask] contains all the flags in [ValueFlags.all], but in
/// some cases it is used to specifically propagate nullability.
class AssignConstraint extends Constraint {
  final StorageLocation source;
  final StorageLocation destination;
  final int mask; // TODO: Remove

  AssignConstraint(this.source, this.destination,
      [this.mask = ValueFlags.all]) {
    assert(source != null);
    assert(destination != null);
    assert(mask != null);
  }

  /// If true, any value in [source] escapes if [destination] leads to escape.
  bool get canEscape => mask & ValueFlags.escaping != 0;

  void transfer(ConstraintSolver solver) {
    solver.transferAssignConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerAssignConstraint(this);
  }

  String toString() {
    var suffix =
        (mask == ValueFlags.all) ? '' : ' (${ValueFlags.flagsToString(mask)})';
    return '$source <: $destination$suffix';
  }

  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitAssignConstraint(this);
  }
}

/// The given [value] can flow into [destination], possibly escaping if
/// [canEscape] is set.
class ValueConstraint extends Constraint {
  final StorageLocation destination;
  final Value value;

  /// If [canEscape] is set, the value will be marked as escaping if the
  /// [destination] can lead to escape.  If the value is unaffected by escaping,
  /// e.g. if the value is null or a number, then [canEscape] should be false.
  final bool canEscape;

  ValueConstraint(this.destination, this.value, {this.canEscape: false}) {
    assert(destination != null);
    assert(value != null);
    assert(canEscape != null);
  }

  void transfer(ConstraintSolver solver) {
    solver.transferValueConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerValueConstraint(this);
  }

  String toString() {
    return '$value -> $destination';
  }

  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitValueConstraint(this);
  }
}

/// If the value in [guard] has one of the flags in [guardMask], then [value]
/// can flow into [destination].
///
/// This is generated at object allocation sites, to handle the consequence of
/// the object escaping.  For instance, for the allocation
///
///     new Map<String, List<Uri>>()
///
/// three of these constraints are generated: one for `String`, one for `List`,
/// and one for `Uri`.  So if the map escapes, the type becomes something like
///
///     Map<String+?, List+?<Uri+?>>
///
class GuardedValueConstraint extends Constraint {
  final StorageLocation destination;
  final Value value;

  /// The constraint is triggers if the value in [guard] escapes.
  final StorageLocation guard;
  final int guardMask;

  GuardedValueConstraint(
      this.destination, this.value, this.guard, this.guardMask) {
    assert(destination != null);
    assert(guard != null);
  }

  void transfer(ConstraintSolver solver) {
    solver.transferGuardedValueConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerGuardedValueConstraint(this);
  }

  String toString() {
    return '$value -> $destination (if $guard escapes)';
  }

  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitGuardedValueConstraint(this);
  }
}

/// The value in [escaping] can escape if the value in [guard] escapes.
class EscapeConstraint extends Constraint {
  final StorageLocation escaping;
  final StorageLocation guard; // May be null.

  EscapeConstraint(this.escaping, {this.guard});

  void transfer(ConstraintSolver solver) {
    solver.transferEscapeConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerEscapeConstraint(this);
  }

  String toString() {
    return 'escape $escaping';
  }

  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitEscapeConstraint(this);
  }
}

/// Values in [source] that match [interfaceClass] and [mask] can flow into
/// [destination].
class TypeFilterConstraint extends Constraint {
  final StorageLocation source;
  final StorageLocation destination;
  final Class interfaceClass;
  final int mask;

  TypeFilterConstraint(
      this.source, this.destination, this.interfaceClass, this.mask);

  @override
  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitTypeFilterConstraint(this);
  }

  @override
  void register(ConstraintSolver solver) {
    solver.registerTypeFilterConstraint(this);
  }

  @override
  void transfer(ConstraintSolver solver) {
    solver.transferTypeFilterConstraint(this);
  }
}

/// Values in [source] that match [guard] can flow into [destination].
class ValueFilterConstraint extends Constraint {
  final StorageLocation source;
  final StorageLocation destination;
  final Value guard;

  ValueFilterConstraint(this.source, this.destination, this.guard);

  @override
  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitValueFilterConstraint(this);
  }

  @override
  void register(ConstraintSolver solver) {
    solver.registerValueFilterConstraint(this);
  }

  @override
  void transfer(ConstraintSolver solver) {
    solver.transferValueFilterConstraint(this);
  }
}

class InstanceMembersConstraint extends Constraint {
  final StorageLocation destination;
  final StorageLocation toStringReturn;
  final StorageLocation hashCodeReturn;
  final StorageLocation equalsReturn;
  final StorageLocation runtimeTypeReturn;

  InstanceMembersConstraint(this.destination, this.toStringReturn,
      this.hashCodeReturn, this.equalsReturn, this.runtimeTypeReturn);

  @override
  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitInstanceMembersConstraint(this);
  }

  @override
  void register(ConstraintSolver solver) {
    solver.registerInstanceMembersConstraint(this);
  }

  @override
  void transfer(ConstraintSolver solver) {
    solver.transferInstanceMembersConstraint(this);
  }
}
