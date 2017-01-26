import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/inference/binding.dart';
import 'package:kernel/inference/constraint_builder.dart';
import 'package:kernel/inference/constraint_extractor.dart';
import 'package:kernel/inference/hierarchy.dart';
import 'package:kernel/kernel.dart';

main(List<String> args) {
  args = ['micro.dill'];
  var program = loadProgramFromBinary(args[0]);
  // var coreTypes = new CoreTypes(program);
  // var baseHierarchy = new ClassHierarchy(program);
  // var binding = new Binding(coreTypes);
  // var augmentedHierarchy = new AugmentedHierarchy(baseHierarchy, binding);
  // var constraints = new ConstraintBuilder(augmentedHierarchy);
  new ConstraintExtractor().checkProgram(program);
}
