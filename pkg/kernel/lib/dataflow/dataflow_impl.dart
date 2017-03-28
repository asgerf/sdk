// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
part of kernel.dataflow;

class _DataflowResults extends DataflowResults {
  final Program program;
  CoreTypes coreTypes;
  ClassHierarchy hierarchy;

  Binding _binding;
  ConstraintExtractor _extractor;
  ConstraintSolver _solver;

  Value _top;

  _DataflowResults(this.program,
      {this.coreTypes, this.hierarchy, DataflowDiagnosticListener diagnostic}) {
    coreTypes ??= new CoreTypes(program);
    hierarchy ??= new ClassHierarchy(program);

    _top = new Value(coreTypes.objectClass, ValueFlags.all);

    var externalModel = new VmExternalModel(program, coreTypes);
    _extractor = new ConstraintExtractor(externalModel)
      ..extractFromProgram(program);
    diagnostic?._constraintSystem = _extractor.constraintSystem;
    diagnostic?._binding = _extractor.binding;
    _solver = new ConstraintSolver(
        hierarchy, _extractor.constraintSystem, diagnostic?._solverListener);
    diagnostic?._onBeginSolve();
    _solver.solve();
    diagnostic?._onEndSolve();
    // Run debugging hooks after solving.  These are exclusively for debugging
    // convenience in the extractor, and there should never be any hooks
    // registered in production.
    for (var hook in _extractor.analysisCompleteHooks) {
      hook();
    }
  }

  MemberDataflowResults getResultsForMember(Member member) {
    return new _MemberDataflowResults(
        _binding.getMemberBank(member), _binding, _solver.lattice, _top);
  }
}

class _MemberDataflowResults extends MemberDataflowResults {
  final StorageLocationBank _bank;
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

  Value get value => getValueAtStorageLocation(0);
}

class _DataflowReporter extends DataflowReporter {
  final Report report = new Report();
  ConstraintSystem _constraintSystem;
  Stopwatch _stopwatch;
  Duration _solvingTime;
  Binding _binding;

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
}
