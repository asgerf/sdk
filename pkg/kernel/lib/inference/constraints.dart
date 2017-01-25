// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.constraints;

import 'key.dart';
import 'solver.dart';
import 'value.dart';

abstract class Constraint {
  void transfer(ConstraintSolver solver);
  void register(ConstraintSolver solver);
}

class TypeArgumentConstraint extends Constraint {
  final Key createdObject;
  final Key typeArgument;

  TypeArgumentConstraint(this.createdObject, this.typeArgument);

  void transfer(ConstraintSolver solver) {
    solver.transferTypeArgumentConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerTypeArgumentConstraint(this);
  }
}

class SubtypeConstraint extends Constraint {
  final Key source;
  final Key destination;
  final int mask;

  SubtypeConstraint(this.source, this.destination, [this.mask = Flags.all]);

  void transfer(ConstraintSolver solver) {
    solver.transferSubtypeConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerSubtypeConstraint(this);
  }
}

class ValueConstraint extends Constraint {
  final Key destination;
  final Value value;

  ValueConstraint(this.destination, this.value);

  void transfer(ConstraintSolver solver) {
    solver.transferValueConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerValueConstraint(this);
  }
}
