// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.constraints;

import '../ast.dart';
import 'storage_location.dart';
import 'solver/solver.dart';
import 'value.dart';

abstract class Constraint {
  Reference owner;
  void transfer(ConstraintSolver solver);
  void register(ConstraintSolver solver);
  T accept<T>(ConstraintVisitor<T> visitor);
}

abstract class ConstraintVisitor<T> {
  T visitSubtypeConstraint(SubtypeConstraint constraint);
  T visitValueConstraint(ValueConstraint constraint);
  T visitEscapeConstraint(EscapeConstraint constraint);
  T visitTypeArgumentConstraint(TypeArgumentConstraint constraint);
}

/// Any value in [source] matching [mask] can flow into [destination].
///
/// If [destination] escapes, so does [source], unless [mask] does not contain
/// [ValueFlags.escaping].
///
/// In most cases, the [mask] contains all the flags in [ValueFlags.all], but in
/// some cases it is used to specifically propagate nullability.
class SubtypeConstraint extends Constraint {
  final StorageLocation source;
  final StorageLocation destination;
  final int mask;

  SubtypeConstraint(this.source, this.destination,
      [this.mask = ValueFlags.all]) {
    assert(source != null);
    assert(destination != null);
    assert(mask != null);
  }

  /// If true, any value in [source] escapes if [destination] leads to escape.
  bool get canEscape => mask & ValueFlags.escaping != 0;

  void transfer(ConstraintSolver solver) {
    solver.transferSubtypeConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerSubtypeConstraint(this);
  }

  String toString() {
    var suffix =
        (mask == ValueFlags.all) ? '' : ' (${ValueFlags.flagsToString(mask)})';
    return '$source <: $destination$suffix';
  }

  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitSubtypeConstraint(this);
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

  EscapeConstraint(this.escaping);

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

/// If [createdObject] is escaping, then [typeArgument] must be top.
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
class TypeArgumentConstraint extends Constraint {
  final StorageLocation createdObject;
  final StorageLocation typeArgument;

  /// The value to assign to [typeArgument] if [createdObject] escapes.
  final Value value;

  TypeArgumentConstraint(this.createdObject, this.typeArgument, this.value) {
    assert(createdObject != null);
    assert(typeArgument != null);
  }

  void transfer(ConstraintSolver solver) {
    solver.transferTypeArgumentConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerTypeArgumentConstraint(this);
  }

  String toString() {
    return '$createdObject<$typeArgument>';
  }

  T accept<T>(ConstraintVisitor<T> visitor) {
    return visitor.visitTypeArgumentConstraint(this);
  }
}
