// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
part of kernel.dataflow;

class _DataflowResults extends DataflowResults {
  final Program program;
  CoreTypes coreTypes;
  ClassHierarchy hierarchy;

  ExtractionResult _extractionResult;
  ConstraintSolver _solver;

  Value _top;

  _DataflowResults(this.program,
      {this.coreTypes, this.hierarchy, DataflowDiagnosticListener diagnostic}) {
    coreTypes ??= new CoreTypes(program);
    hierarchy ??= new ClassHierarchy(program);
    var externalModel = new VmExternalModel(program, coreTypes, hierarchy);
    var backendCoreTypes = new VmCoreTypes(coreTypes);
    var lattice = new ValueLattice(coreTypes, hierarchy);
    var common = new CommonValues(coreTypes, backendCoreTypes, lattice);

    _top = common.anyValue;

    var extractor = new ConstraintExtractor(
        externalModel: externalModel,
        backendCoreTypes: backendCoreTypes,
        typeErrorCallback: diagnostic?._onTypeError,
        coreTypes: coreTypes,
        hierarchy: hierarchy,
        lattice: lattice);
    _extractionResult = extractor.extractFromProgram(program);
    diagnostic?._constraintSystem = _extractionResult.constraintSystem;
    diagnostic?._binding = _extractionResult.binding;
    _solver = new ConstraintSolver(
        coreTypes, hierarchy, _extractionResult.constraintSystem,
        report: diagnostic?._solverListener, lattice: lattice);
    diagnostic?._onBeginSolve();
    _solver.solve();
    diagnostic?._onEndSolve();
  }

  MemberDataflowResults getResultsForMember(Member member) {
    var binding = _extractionResult.binding;
    return new _MemberDataflowResults(
        binding.getMemberBank(member), binding, _solver.lattice, _top);
  }
}

class _MemberDataflowResults extends MemberDataflowResults {
  final MemberBank _bank;
  final Binding _binding;
  final ValueLattice _lattice;
  final Value _top;

  _MemberDataflowResults(this._bank, this._binding, this._lattice, this._top);

  Value _getStorageLocationValue(StorageLocation location) {
    Value value = location.value;
    // Build a value that summarizes all possible calling contexts.
    while (location.parameterLocation != null) {
      location = _binding.getBoundForParameter(location.parameterLocation);
      value = _lattice.joinValues(value, location.value);
    }
    return value;
  }

  Value getValueAtStorageLocation(int offset) {
    if (offset == null || offset == -1) return _top;
    return _getStorageLocationValue(_bank.locations[offset]);
  }

  bool isStorageLocationLeadingToEscape(int offset) {
    if (offset == null || offset == -1) return true;
    return _bank.locations[offset].leadsToEscape;
  }

  Value get value => getValueAtStorageLocation(0);

  int get concreteReturn {
    var bank = _bank;
    StorageLocation location = bank is FunctionMemberBank
        ? bank.concreteReturnType.source
        : bank.concreteType.source;
    return location.index;
  }

  int getConcretePositionalParameter(int n) {
    FunctionMemberBank bank = _bank;
    StorageLocation location = bank.concretePositionalParameters[n].source;
    return location.index;
  }

  int getConcreteNamedParameter(String name) {
    FunctionMemberBank bank = _bank;
    StorageLocation location =
        bank.concreteType.getNamedParameterType(name).source;
    return location.index;
  }
}

class _DataflowReporter extends DataflowReporter {
  final Report report = new Report();
  ConstraintSystem _constraintSystem;
  Stopwatch _stopwatch;
  Duration _solvingTime;
  Binding _binding;
  final List<ErrorMessage> errorMessages = <ErrorMessage>[];

  _DataflowReporter() : super._();

  ConstraintSystem get constraintSystem => _constraintSystem;
  SolverListener get _solverListener => report;
  Duration get solvingTime => _solvingTime;
  Binding get binding => _binding;

  @override
  void _onBeginSolve() {
    _stopwatch = new Stopwatch()..start();
  }

  @override
  void _onEndSolve() {
    _solvingTime = _stopwatch.elapsed;
    _stopwatch.stop();
  }

  @override
  void _onTypeError(TreeNode where, String message) {
    errorMessages.add(new ErrorMessage(where, message));
  }
}
