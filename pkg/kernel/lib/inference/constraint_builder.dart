library kernel.inference.constraint_builder;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/augmented_type.dart';
import 'package:kernel/inference/constraints.dart';

abstract class ConstraintBuilder {
  InterfaceAType getTypeAsInstanceOf(InterfaceAType type, Class superclass);
  void addConstraint(Constraint constraint);
}
