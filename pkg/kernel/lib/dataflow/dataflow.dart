// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow;

import '../ast.dart';
import '../class_hierarchy.dart';
import '../core_types.dart';
import 'extractor/binding.dart';
import 'extractor/constraint_extractor.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/extractor/external_model.dart';
import 'package:kernel/dataflow/report/report.dart';
import 'solver/solver.dart';
import 'storage_location.dart';
import 'value.dart';

export 'value.dart' show Value;
export 'report/report.dart' show Report;

part 'dataflow_impl.dart';

class DataflowEngine {
  /// Analyzes the whole program and returns the inferred type information.
  ///
  /// This invalidates any existing dataflow results for that program, since
  /// some of the information is stored directly on AST nodes.
  static DataflowResults analyzeWholeProgram(Program program,
      {CoreTypes coreTypes,
      ClassHierarchy hierarchy,
      DataflowDiagnosticListener diagnostic}) {
    return new _DataflowResults(program,
        coreTypes: coreTypes, hierarchy: hierarchy, diagnostic: diagnostic);
  }
}

/// Provides access to dataflow results for the whole program.
///
/// This is partly backed by information stored on the AST nodes, so this object
/// should not be seen as a side table, but as an API for accessing the stored
/// values.
abstract class DataflowResults {
  /// Returns the values inferred for the given member.
  MemberDataflowResults getResultsForMember(Member member);
}

/// Inferred type information for the body of a member.
abstract class MemberDataflowResults {
  /// The value of the member itself.
  ///
  /// For fields, this is the value of the field, for procedures and
  /// constructors it describes a function value.
  Value get value;

  Value getValueAtStorageLocation(int storageLocationOffset);

  Value getValueOfVariable(VariableDeclaration node) {
    return getValueAtStorageLocation(node.inferredValueOffset);
  }

  Value getValueOfFunctionReturn(FunctionNode node) {
    return getValueAtStorageLocation(node.inferredReturnValueOffset);
  }

  Value getValueOfExpression(Expression node) {
    return getValueAtStorageLocation(node.inferredValueOffset);
  }
}

/// An object given to the dataflow analysis, which will collect information
/// for diagnstic purposes but which is too expensive to retain in production.
///
/// Clients should not instantiate or implement this but instead create a
/// [DataflowReporter].
///
/// This interface exists to enable a (yet unimplemented) diagnostic listener
/// that streams the data directly to a file without exposing analysis internals
/// to clients (hence all its members are private).
abstract class DataflowDiagnosticListener {
  SolverListener get _solverListener;
  void set _constraintSystem(ConstraintSystem constraintSystem);
  void set _binding(Binding binding);
  void _onBeginSolve();
  void _onEndSolve();
}

/// Dataflow diagnostic listener that builds an indexed report in memory.
///
/// Note: This class exposes analysis internal details and breaking changes are
/// to be expected.
///
/// Example usage:
///
///     var reporter = new DataflowReporter();
///     var results = DataflowEngine.analyzeWholeProgram(
///         program,
///         diagnostic: reporter);
///     var report = reporter.report;
///     print('Number of transfers: ${report.numberOfTransferEvents}');
///
/// The memory overhead is quite significant and this should absolutely not be
/// used in production.
abstract class DataflowReporter implements DataflowDiagnosticListener {
  Binding get binding;
  ConstraintSystem get constraintSystem;
  Report get report;
  Duration get solvingTime;

  factory DataflowReporter() = _DataflowReporter;
  DataflowReporter._();
}
