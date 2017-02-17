library kernel.inference.constraint_builder;

import 'package:kernel/ast.dart';

import '../constraints.dart';
import 'augmented_type.dart';
import 'hierarchy.dart';
import 'package:kernel/inference/extractor/value_sink.dart';
import 'package:kernel/inference/extractor/value_source.dart';

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

  void addAssignment(ValueSource source, ValueSink sink, int mask) {
    sink.generateAssignmentFrom(this, source, mask);
  }
}
