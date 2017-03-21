// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
part of kernel.inference;

class _InferenceResults extends InferenceResults {
  final Program program;
  CoreTypes coreTypes;
  ClassHierarchy hierarchy;

  Binding _binding;
  ConstraintExtractor _extractor;
  ConstraintSolver _solver;

  Value _top;

  Report _report;

  _InferenceResults(this.program,
      {this.coreTypes,
      this.hierarchy,
      List<ProgramRoot> programRoots,
      bool buildReport: false}) {
    coreTypes ??= new CoreTypes(program);
    hierarchy ??= new ClassHierarchy(program);

    _top = new Value(coreTypes.objectClass, ValueFlags.all);

    var externalModel = new VmExternalModel(program, coreTypes, programRoots);
    _extractor = new ConstraintExtractor(externalModel)
      ..extractFromProgram(program);
    _binding = _extractor.binding;
    if (buildReport) {
      _report = new Report();
    }
    _solver =
        new ConstraintSolver(hierarchy, _extractor.constraintSystem, _report);
    _solver.solve();
  }

  MemberInferenceResults getInferredValuesForMember(Member member) {
    return new _MemberInferenceResults(
        _binding.getMemberBank(member), _binding, _solver.lattice, _top);
  }

  Report get report => _report;
}

class _MemberInferenceResults implements MemberInferenceResults {
  final StorageLocationBank _bank;
  final Binding _binding;
  final ValueLattice _lattice;
  final Value _top;

  _MemberInferenceResults(this._bank, this._binding, this._lattice, this._top);

  Value _getStorageLocationValue(StorageLocation location) {
    Value value = location.value;
    // Build a value that summarizes all possible calling contexts.
    while (location.parameterLocation != null) {
      location = _binding.getBoundForParameter(location.parameterLocation);
      value = _lattice.joinValues(value, location.value);
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
