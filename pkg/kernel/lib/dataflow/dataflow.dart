// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow;

import '../ast.dart';
import '../class_hierarchy.dart';
import '../core_types.dart';
import '../program_root.dart';
import 'extractor/binding.dart';
import 'extractor/constraint_extractor.dart';
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
  /// This invalidates any existing inference results for that program, since
  /// some of the information is stored directly on AST nodes.
  static DataflowResults analyzeWholeProgram(
      Program program, List<ProgramRoot> programRoots,
      {CoreTypes coreTypes,
      ClassHierarchy hierarchy,
      bool buildReport: false}) {
    return new _InferenceResults(program,
        coreTypes: coreTypes,
        hierarchy: hierarchy,
        programRoots: programRoots,
        buildReport: buildReport);
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

  Report get report;
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
