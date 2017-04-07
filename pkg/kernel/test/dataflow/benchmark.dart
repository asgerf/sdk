// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extract_bench;

import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/extractor/constraint_extractor.dart';
import 'package:kernel/dataflow/extractor/external_model.dart';
import 'package:kernel/dataflow/solver/solver.dart';
import 'package:kernel/kernel.dart';

main(List<String> args) {
  var program = loadProgramFromBinary(args[0]);
  var coreTypes = new CoreTypes(program);
  var hierarchy = new ClassHierarchy(program);

  ConstraintSystem extractConstraints() {
    var externalModel = new VmExternalModel(program, coreTypes, hierarchy);
    var extractor = new ConstraintExtractor(externalModel);
    extractor.extractFromProgram(program);
    return extractor.constraintSystem;
  }

  var watch = new Stopwatch()..start();
  var constraints = extractConstraints();
  num extractionTime = watch.elapsedMilliseconds;
  print('Extraction: $extractionTime ms');

  watch.reset();

  var solver = new ConstraintSolver(coreTypes, hierarchy, constraints);
  solver.solve();
  num solvingTime = watch.elapsedMilliseconds;
  print('Solving:    $solvingTime ms');
  print('Total:      ${extractionTime + solvingTime} ms');
}
