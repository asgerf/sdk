// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.transformations.check_inference;

import 'package:kernel/ast.dart';
import 'package:kernel/frontend/accessors.dart';
import 'package:kernel/inference/extractor/augmented_type.dart';
import 'package:kernel/inference/extractor/binding.dart';
import 'package:kernel/inference/extractor/constraint_extractor.dart';
import 'package:kernel/inference/solver/solver.dart';

class CheckInference {
  Binding binding;

  void transformProgram(Program program) {
    var extractor = new ConstraintExtractor()..extractFromProgram(program);
    binding = extractor.binding;
    var constraints = extractor.builder.constraints;
    var solver = new ConstraintSolver(extractor.baseHierarchy, constraints);
    solver.solve();
    for (var library in program.libraries) {
      if (library.importUri.scheme == 'dart') continue;
      library.members.forEach(instrumentMember);
      for (var class_ in library.classes) {
        class_.members.forEach(instrumentMember);
      }
    }
  }

  void instrumentMember(Member member) {
    var function = member.function;
    var body = function?.body;
    if (body != null) {
      var bank = binding.getFunctionBank(member);
      List<Statement> checks = <Statement>[];
      for (int i = 0; i < function.positionalParameters.length; ++i) {
        var parameter = function.positionalParameters[i];
        var type = bank.positionalParameters[i];
        checks.add(generateCheck(type, parameter, member));
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
      AType type, VariableDeclaration variable, Member where) {
    List<Expression> cases = <Expression>[];
    var value = type.source.value;
    print('Value of ${variable.name} in $where is $value');
    if (value.canBeNull) {
      cases.add(buildIsNull(new VariableGet(variable)));
    }
    if (value.baseClass != null) {
      // TODO: more precise check
      cases.add(
          new IsExpression(new VariableGet(variable), value.baseClass.rawType));
    }
    Throw throw_ = new Throw(new StringConcatenation([
      new StringLiteral("'${variable.name}' in $where has unexpected value: "),
      new VariableGet(variable)
    ]))..fileOffset = variable.fileOffset ?? where.fileOffset;
    Statement throwStmt = new ExpressionStatement(throw_);
    if (cases.isEmpty) {
      return throwStmt;
    }
    Expression condition =
        cases.reduce((e1,e2) => new LogicalExpression(e1, '||', e2));
    return new IfStatement(new Not(condition), throwStmt, null);
  }
}
