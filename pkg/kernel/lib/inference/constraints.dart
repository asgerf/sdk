// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.constraints;

import 'key.dart';
import 'package:kernel/ast.dart';
import 'solver/solver.dart';
import 'value.dart';

abstract class Constraint {
  TreeNode owner;
  void transfer(ConstraintSolver solver);
  void register(ConstraintSolver solver);
}

/// Any value in [source] matching [mask] can flow into [destination].
///
/// If [destination] escapes, so does [source], unless [mask] does not contain
/// [Flags.escaping].
///
/// In most cases, the [mask] contains all the flags in [Flags.all], but in
/// some cases it is used to specifically propagate nullability.
class SubtypeConstraint extends Constraint {
  final Key source;
  final Key destination;
  final int mask;

  SubtypeConstraint(this.source, this.destination, [this.mask = Flags.all]) {
    assert(source != null);
    assert(destination != null);
    assert(mask != null);
  }

  void transfer(ConstraintSolver solver) {
    solver.transferSubtypeConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerSubtypeConstraint(this);
  }

  String toString() {
    var suffix = (mask == Flags.all) ? '' : ' (${Flags.flagsToString(mask)})';
    return '$source <: $destination$suffix';
  }
}

/// The given [value] can flow into [destination].
class ValueConstraint extends Constraint {
  final Key destination;
  final Value value;

  ValueConstraint(this.destination, this.value) {
    assert(destination != null);
    assert(value != null);
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
}

class EscapeConstraint extends Constraint {
  final Key escaping;

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
  final Key createdObject;
  final Key typeArgument;

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
}
