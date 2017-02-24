// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.transformations.check_inference;

import 'package:kernel/ast.dart';
import 'package:kernel/frontend/accessors.dart';
import 'package:kernel/inference/inference.dart';
import 'package:kernel/program_root.dart';

/// Inserts runtime checks to verify the results of the type inference.
///
/// This is for debugging the type inference, not intended for production.
class CheckInference {
  final List<ProgramRoot> programRoots;

  CheckInference(this.programRoots);

  InferenceResults inferenceResults;

  /// A synthetic field that keeps track of whether an error has been found
  /// and prevents further checks in the process of throwing an error.
  ///
  /// The error-handling code performs string interpolation and calls `toString`
  /// on an arbitrary value, which can lead to infinite recursion if we don't
  /// disable the checks.
  Field stopField;

  void transformProgram(Program program) {
    inferenceResults =
        InferenceEngine.analyzeWholeProgram(program, programRoots);
    addStopField(program);
    for (var library in program.libraries) {
      library.members.forEach(instrumentMember);
      for (var class_ in library.classes) {
        class_.members.forEach(instrumentMember);
      }
    }
  }

  void addStopField(Program program) {
    var library = new Library(Uri.parse('transformer:check_inference'));
    program.libraries.add(library..parent = library);
    stopField = new Field(new Name('_stopChecks', library),
        initializer: new BoolLiteral(false), isStatic: true);
    library.addMember(stopField);
  }

  void instrumentMember(Member member) {
    var function = member.function;
    var body = function?.body;
    if (body != null) {
      var inferredValues = inferenceResults.getInferredValuesForMember(member);
      List<Statement> checks = <Statement>[];
      for (int i = 0; i < function.positionalParameters.length; ++i) {
        var parameter = function.positionalParameters[i];
        var value = inferredValues.getValueOfVariable(parameter);
        checks.add(generateCheck(value, parameter, member));
      }
      if (body is Block) {
        checks.addAll(body.statements);
      } else {
        checks.add(body);
      }
      function.body = new Block(checks)..parent = function;
    }
  }

  Statement generateCheck(
      Value value, VariableDeclaration variable, Member where) {
    List<Expression> cases = <Expression>[];
    cases.add(new StaticGet(stopField));
    if (value.canBeNull) {
      cases.add(buildIsNull(new VariableGet(variable)));
    }
    if (value.baseClass != null) {
      // TODO: more precise check
      cases.add(
          new IsExpression(new VariableGet(variable), value.baseClass.rawType));
    }
    Throw throw_ = new Throw(new StringConcatenation([
      new StringLiteral(
          "Unexpected value of '${variable.name}' in $where.\nActual value: "),
      new VariableGet(variable),
      new StringLiteral('\nExpected values: $value')
    ]))..fileOffset = variable.fileOffset ?? where.fileOffset;
    Statement throwStmt = new ExpressionStatement(throw_);
    Block failStatement = new Block([
      new ExpressionStatement(new StaticSet(stopField, new BoolLiteral(true))),
      throwStmt
    ]);
    assert(cases.isNotEmpty);
    Expression condition =
        cases.reduce((e1, e2) => new LogicalExpression(e1, '||', e2));
    return new IfStatement(new Not(condition), failStatement, null);
  }
}
