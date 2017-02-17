library kernel.inference.constraint_builder;

import 'package:kernel/ast.dart';

import '../constraints.dart';
import 'augmented_type.dart';
import 'hierarchy.dart';

class ConstraintBuilder {
  final List<Constraint> constraints = <Constraint>[];
  final AugmentedHierarchy hierarchy;
  TreeNode currentOwner;

  ConstraintBuilder(this.hierarchy);

  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return hierarchy.getTypeAsInstanceOf(subtype, superclass);
  }

  void addConstraint(Constraint constraint) {
    constraints.add(constraint..owner = currentOwner);
  }
}
