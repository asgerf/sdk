library kernel.inference.constraint_builder;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/augmented_type.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/hierarchy.dart';

class ConstraintBuilder {
  final List<Constraint> constraints = <Constraint>[];
  final AugmentedHierarchy hierarchy;

  ConstraintBuilder(this.hierarchy);

  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return hierarchy.getTypeAsInstanceOf(subtype, superclass);
  }

  void addConstraint(Constraint constraint) {
    constraints.add(constraint);
  }
}
