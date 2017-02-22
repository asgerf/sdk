// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
part of kernel.inference;

class _GlobalInferenceResult extends GlobalInferenceResult {
  final Program program;
  CoreTypes coreTypes;
  ClassHierarchy hierarchy;

  Binding _binding;
  ConstraintExtractor _extractor;
  ConstraintSolver _solver;

  Value _top;

  _GlobalInferenceResult(this.program, {this.coreTypes, this.hierarchy}) {
    coreTypes ??= new CoreTypes(program);
    hierarchy ??= new ClassHierarchy(program);

    _top = new Value(coreTypes.objectClass, ValueFlags.all);

    _extractor = new ConstraintExtractor()..extractFromProgram(program);
    _binding = _extractor.binding;
    _solver = new ConstraintSolver(hierarchy, _extractor.builder.constraints);
    _solver.solve();
  }

  MemberInferenceResult getInferredValuesForMember(Member member) {
    return new _MemberInferenceResult(
        _binding.getMemberBank(member), _binding, _solver, _top);
  }
}

class _MemberInferenceResult implements MemberInferenceResult {
  final StorageLocationBank _bank;
  final Binding _binding;
  final ConstraintSolver _solver;
  final Value _top;

  _MemberInferenceResult(this._bank, this._binding, this._solver, this._top);

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

  Value get value => _getValueAtOffset(0);

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
