// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:kernel/inference/extractor/constraint_extractor.dart';
import 'package:kernel/inference/solver/solver.dart';
import 'package:kernel/kernel.dart';

main(List<String> args) {
  if (args.isEmpty) args = ['micro.dill'];
  var program = loadProgramFromBinary(args[0]);
  var extractor = new ConstraintExtractor()..extractFromProgram(program);
  var constraints = extractor.builder.constraints;
  print('Extracted ${constraints.length} constraints');
  var watch = new Stopwatch()..start();
  var solver = new ConstraintSolver(extractor.baseHierarchy, constraints);
  solver.solve();
  var solveTime = watch.elapsedMilliseconds;
  print('Solving took ${solveTime} ms');
  print('-------');
  for (var hook in extractor.analysisCompleteHooks) {
    hook();
  }
  writeProgramToText(program, path: 'dump.txt', binding: extractor.binding);
}
