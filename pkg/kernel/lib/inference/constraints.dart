// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.constraints;

import '../inference/solver.dart';
import '../inference/key.dart';
import '../inference/value.dart';

abstract class Constraint {
  void transfer(ConstraintSolver solver);
  void register(ConstraintSolver solver);
}

class TypeArgumentConstraint extends Constraint {
  Key createdObject;
  Key typeArgument;

  void transfer(ConstraintSolver solver) {
    solver.transferTypeArgumentConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerTypeArgumentConstraint(this);
  }
}

class SubtypeConstraint extends Constraint {
  Key source;
  Key destination;

  void transfer(ConstraintSolver solver) {
    solver.transferSubtypeConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerSubtypeConstraint(this);
  }
}

class ValueConstraint extends Constraint {
  Key destination;
  Value value;

  void transfer(ConstraintSolver solver) {
    solver.transferValueConstraint(this);
  }

  void register(ConstraintSolver solver) {
    solver.registerValueConstraint(this);
  }
}
