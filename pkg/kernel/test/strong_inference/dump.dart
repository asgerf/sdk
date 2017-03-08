// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';

import 'package:kernel/core_types.dart';
import 'package:kernel/inference/extractor/constraint_extractor.dart';
import 'package:kernel/inference/extractor/external_model.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/report/writer.dart';
import 'package:kernel/inference/solver/solver.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/program_root_parser.dart';

Uri sdkCheckout = Platform.script.resolve('../../../../');
Uri runtimeBinDir = sdkCheckout.resolve('runtime/bin/');

List<Uri> entryPoints = <Uri>[
  runtimeBinDir.resolve('dart_entries.txt'),
  runtimeBinDir.resolve('dart_product_entries.txt'),
  runtimeBinDir.resolve('dart_io_entries.txt'),
];

main(List<String> args) {
  if (args.isEmpty) args = ['micro.dill'];
  var program = loadProgramFromBinary(args[0]);
  var roots =
      parseProgramRoots(entryPoints.map((uri) => uri.toFilePath()).toList());
  var extractor = new ConstraintExtractor(
      new VmExternalModel(program, new CoreTypes(program), roots))
    ..extractFromProgram(program);
  var constraints = extractor.builder.constraints;
  print('Extracted ${constraints.length} constraints');
  var watch = new Stopwatch()..start();
  var report = new Report();
  var solver =
      new ConstraintSolver(extractor.baseHierarchy, constraints, report);
  solver.solve();
  var solveTime = watch.elapsedMilliseconds;
  print('Solving took ${solveTime} ms');
  print('-------');
  for (var hook in extractor.analysisCompleteHooks) {
    hook();
  }
  writeProgramToText(program, path: 'dump.txt', binding: extractor.binding);

  var writer = new ReportWriter();
  var json = writer.buildJsonReport(program, solver, report);
  new File('report.json').writeAsString(JSON.encode(json));
}
