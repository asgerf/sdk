library kernel.inference.constraints;

import 'package:kernel/inference/solver.dart';
import 'package:kernel/inference/key.dart';
import 'package:kernel/inference/value.dart';

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
