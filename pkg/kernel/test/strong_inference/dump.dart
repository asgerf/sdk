// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:kernel/core_types.dart';
import 'package:kernel/inference/extractor/constraint_extractor.dart';
import 'package:kernel/inference/extractor/external_model.dart';
import 'package:kernel/inference/report/binary_reader.dart';
import 'package:kernel/inference/report/binary_writer.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/solver/solver.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/program_root_parser.dart';
import 'package:kernel/util/reader.dart';
import 'package:kernel/util/writer.dart';

Uri sdkCheckout = Platform.script.resolve('../../../../');
Uri runtimeBinDir = sdkCheckout.resolve('runtime/bin/');

List<Uri> entryPoints = <Uri>[
  runtimeBinDir.resolve('dart_entries.txt'),
  runtimeBinDir.resolve('dart_product_entries.txt'),
  runtimeBinDir.resolve('dart_io_entries.txt'),
];

main(List<String> args) async {
  if (args.isEmpty) args = ['micro.dill'];
  var program = loadProgramFromBinary(args[0]);
  var roots =
      parseProgramRoots(entryPoints.map((uri) => uri.toFilePath()).toList());
  var extractor = new ConstraintExtractor(
      new VmExternalModel(program, new CoreTypes(program), roots))
    ..extractFromProgram(program);
  var constraints = extractor.builder.constraints;
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

  print('Number of events = ${report.allEvents.length}');
  print('Number of changes = ${report.changeEvents.length}');
  print('Number of transfers = ${report.transferEvents.length}');

  program.computeCanonicalNames();
  var file = new File('report.bin').openWrite();
  var buffer = new Writer(file);
  var writer = new BinaryReportWriter(buffer);
  writer.writeBinding(extractor.binding.rawBinding);
  writer.writeConstraints(constraints);
  writer.writeEventList(report.transferEvents);
  writer.finish();
  await file.close();

  var reader = new BinaryReportReader(
      new Reader(new File('report.bin').readAsBytesSync()));
  var binding2 = reader.readBindings();
  var constraints2 = reader.readConstraints();
  var events2 = reader.readEventList();
}
