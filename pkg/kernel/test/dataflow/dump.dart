// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/extractor/constraint_extractor.dart';
import 'package:kernel/dataflow/extractor/external_model.dart';
import 'package:kernel/dataflow/report/binary_reader.dart';
import 'package:kernel/dataflow/report/binary_writer.dart';
import 'package:kernel/dataflow/report/report.dart';
import 'package:kernel/dataflow/solver/solver.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/util/reader.dart';
import 'package:kernel/util/writer.dart';

Uri sdkCheckout = Platform.script.resolve('../../../../');
Uri runtimeBinDir = sdkCheckout.resolve('runtime/bin/');

main(List<String> args) async {
  if (args.isEmpty) args = ['micro.dill'];
  var program = loadProgramFromBinary(args[0]);
  var extractor = new ConstraintExtractor(
      new VmExternalModel(program, new CoreTypes(program)))
    ..extractFromProgram(program);
  var constraints = extractor.constraintSystem;
  print('Extracted ${constraints.numberOfConstraints} constraints');
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

  print('Number of changes = ${report.numberOfChangeEvents}');
  print('Number of transfers = ${report.numberOfTransferEvents}');

  program.computeCanonicalNames();
  var file = new File('report.bin').openWrite();
  var buffer = new Writer(file);
  var writer = new BinaryReportWriter(buffer);
  writer.writeConstraintSystem(extractor.constraintSystem);
  writer.writeEventList(report.transferEvents);
  writer.finish();
  await file.close();

  var reader = new BinaryReportReader(
      new Reader(new File('report.bin').readAsBytesSync()));
  reader.readConstraintSystem();
  reader.readEventList();

  writeProgramToBinary(program, 'report.dill');
}
