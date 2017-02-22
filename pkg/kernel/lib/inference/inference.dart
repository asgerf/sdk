// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference;

import '../ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/inference/extractor/binding.dart';
import 'package:kernel/inference/extractor/constraint_extractor.dart';
import 'package:kernel/inference/solver/solver.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';

export 'value.dart' show Value;

abstract class Inference {
  factory Inference(Program program,
      {CoreTypes coreTypes, ClassHierarchy hierarchy}) = _Inference;

  InferredValueBank getInferredValuesForMember(Member member);
}

abstract class InferredValueBank {
  Value getValueOfVariable(VariableDeclaration node);
  Value getValueOfFunctionReturn(FunctionNode node);
  Value getValueOfExpression(Expression node);
}

class _Inference implements Inference {
  final Program program;
  CoreTypes coreTypes;
  ClassHierarchy hierarchy;

  Binding _binding;
  ConstraintExtractor _extractor;
  ConstraintSolver _solver;

  Value _top;

  _Inference(this.program, {this.coreTypes, this.hierarchy}) {
    coreTypes ??= new CoreTypes(program);
    hierarchy ??= new ClassHierarchy(program);

    _top = new Value(coreTypes.objectClass, ValueFlags.all);

    _extractor = new ConstraintExtractor()..extractFromProgram(program);
    _binding = _extractor.binding;
    _solver = new ConstraintSolver(hierarchy, _extractor.builder.constraints);
    _solver.solve();
  }

  InferredValueBank getInferredValuesForMember(Member member) {
    return new _InferredValueBank(
        _binding.getMemberBank(member), _binding, _solver, _top);
  }
}

class _InferredValueBank implements InferredValueBank {
  final StorageLocationBank _bank;
  final Binding _binding;
  final ConstraintSolver _solver;
  final Value _top;

  _InferredValueBank(this._bank, this._binding, this._solver, this._top);

  Value _getStorageLocationValue(StorageLocation location) {
    Value value = location.value;
    // Build a value that summarizes all possible calling contexts.
    while (location.parameterLocation != null) {
      location = _binding.getBoundForParameter(location.parameterLocation);
      value = _solver.joinValues(value, location.value);
    }
    return value;
  }

  Value _getValueAtOffset(int offset) {
    if (offset == null || offset == -1) return _top;
    return _getStorageLocationValue(_bank.locations[offset]);
  }

  Value getValueOfVariable(VariableDeclaration node) {
    return _getValueAtOffset(node.inferredValueOffset);
  }

  Value getValueOfFunctionReturn(FunctionNode node) {
    return _getValueAtOffset(node.inferredReturnValueOffset);
  }

  Value getValueOfExpression(Expression node) {
    return _getValueAtOffset(node.inferredValueOffset);
  }
}
