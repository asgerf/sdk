// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/extractor/augmented_type.dart';
import 'package:kernel/dataflow/extractor/binding.dart';
import 'package:kernel/dataflow/extractor/external_model.dart';
import 'package:kernel/dataflow/extractor/augmented_hierarchy.dart';
import 'package:kernel/kernel.dart';
import 'package:test/test.dart';

class NullExternalModel extends ExternalModel {
  bool forceCleanSupertypes(Class class_) => false;
  bool forceExternal(Member member) => false;
  bool isCleanExternal(Member member) => false;
  bool isEntryPoint(Member member) => false;
}

main(List<String> args) {
  var program = loadProgramFromBinary(args[0]);
  var hierarchy = new ClassHierarchy(program);
  var coreTypes = new CoreTypes(program);
  var constraintSystem = new ConstraintSystem();
  var externalModel = new NullExternalModel();
  var bindings = new Binding(constraintSystem, coreTypes, externalModel);
  var augmentedHierarchy = new AugmentedHierarchy(hierarchy, bindings);
  test('All-pairs augmented class hierarchy tests', () {
    for (Class class_ in hierarchy.classes) {
      for (Class superclass in hierarchy.classes) {
        var substitution =
            augmentedHierarchy.getClassAsInstanceOf(class_, superclass);
        var instance = hierarchy.getClassAsInstanceOf(class_, superclass);
        if (substitution == null && instance == null) continue;
        if (substitution == null) {
          fail('getClassAsInstanceOf($class_, $superclass) returned null\n'
              'but should be $instance');
        }
        if (instance == null) {
          fail(
              'getClassAsInstanceOf($class_, $superclass) did not return null');
        }
        if (class_ == superclass) continue;
        for (int i = 0; i < superclass.typeParameters.length; ++i) {
          var typeParameter = superclass.typeParameters[i];
          var argument = instance.typeArguments[i];
          var augmented = substitution.getRawSubstitute(typeParameter);
          if (augmented == null || !isSameType(argument, augmented)) {
            fail('getClassAsInstanceOf($class_, $superclass)\n'
                '       replaced: $typeParameter\n'
                '           with: $augmented\n'
                '  but should be: $argument');
          }
        }
      }
    }
  });
}

bool isSameType(DartType type, AType augmented) {
  if (type is VoidType && augmented is BottomAType) return true;
  if (type is BottomType && augmented is BottomAType) return true;
  if (type is DynamicType && augmented is InterfaceAType) {
    return augmented.classNode.supertype == null;
  }
  if (type is InterfaceType && augmented is InterfaceAType) {
    if (type.classNode != augmented.classNode) return false;
    for (int i = 0; i < type.typeArguments.length; ++i) {
      if (!isSameType(type.typeArguments[i], augmented.typeArguments[i])) {
        return false;
      }
    }
    return true;
  }
  if (type is FunctionType && augmented is FunctionAType) {
    if (type.requiredParameterCount != augmented.requiredParameterCount ||
        type.positionalParameters.length !=
            augmented.positionalParameters.length ||
        type.namedParameters.length != augmented.namedParameters.length ||
        type.typeParameters.length != augmented.typeParameterBounds.length) {
      return false;
    }
    for (int i = 0; i < type.positionalParameters.length; ++i) {
      if (!isSameType(
          type.positionalParameters[i], augmented.positionalParameters[i])) {
        return false;
      }
    }
    for (int i = 0; i < type.namedParameters.length; ++i) {
      var parameter = type.namedParameters[i];
      if (parameter.name != augmented.namedParameterNames[i]) return false;
      if (!isSameType(parameter.type, augmented.namedParameters[i])) {
        return false;
      }
    }
    return isSameType(type.returnType, augmented.returnType);
  }
  if (type is TypeParameterType && augmented is TypeParameterAType) {
    return type.parameter == augmented.parameter;
  }
  return false;
}
