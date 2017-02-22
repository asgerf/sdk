// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference;

import '../ast.dart';
import '../class_hierarchy.dart';
import '../core_types.dart';
import 'extractor/binding.dart';
import 'extractor/constraint_extractor.dart';
import 'solver/solver.dart';
import 'storage_location.dart';
import 'value.dart';

export 'value.dart' show Value;

part 'inference_impl.dart';

class Inference {
  /// Analyzes the whole program and returns the inferred type information.
  ///
  /// This invalidates any existing inference results for that program, since
  /// some of the information is stored directly on AST nodes.
  static GlobalInferenceResult analyzeWholeProgram(Program program,
      {CoreTypes coreTypes, ClassHierarchy hierarchy}) {
    return new _GlobalInferenceResult(program,
        coreTypes: coreTypes, hierarchy: hierarchy);
  }
}

/// Provides access to type information for the whole program.
///
/// This is partly backed by information stored on the AST nodes, so this object
/// should not be seen as a side table, but more as an API for accessing the
/// inferred types.
abstract class GlobalInferenceResult {
  /// Returns the values inferred for the given member.
  MemberInferenceResult getInferredValuesForMember(Member member);
}

/// Inferred type information for the body of a member.
abstract class MemberInferenceResult {
  /// The value of the member itself.
  ///
  /// For fields, this is the value of the field, for procedures and
  /// constructors it describes a function value.
  Value get value;

  Value getValueOfVariable(VariableDeclaration node);
  Value getValueOfFunctionReturn(FunctionNode node);
  Value getValueOfExpression(Expression node);
}
