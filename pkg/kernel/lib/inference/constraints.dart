// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.constraints;

import '../ast.dart';
import 'storage_location.dart';
import 'solver/solver.dart';
import 'value.dart';

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
  Reference owner;
  int index;
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
  final int mask;

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

/// If [guard] is escaping, then [value] can flow into [destination].
///
/// This is generated for each type argument term inside an allocation site.
/// For instance, for the allocation
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

  GuardedValueConstraint(this.guard, this.destination, this.value) {
    assert(guard != null);
    assert(destination != null);
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
