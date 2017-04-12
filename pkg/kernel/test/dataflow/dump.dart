// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/dataflow.dart';
import 'package:kernel/dataflow/report/binary_reader.dart';
import 'package:kernel/dataflow/report/binary_writer.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/util/reader.dart';
import 'package:kernel/util/writer.dart';

main(List<String> args) async {
  if (args.isEmpty) args = ['dartk.dill'];
  var program = loadProgramFromBinary(args[0]);
  var coreTypes = new CoreTypes(program);
  var reporter = new DataflowReporter();
  var results =
      DataflowEngine.analyzeWholeProgram(program, diagnostic: reporter);
  var constraints = reporter.constraintSystem;
  print('Extracted ${constraints.numberOfConstraints} constraints');
  var solveTime = reporter.solvingTime.inMilliseconds;
  print('Solving took ${solveTime} ms');
  print('-------');
  writeProgramToText(program, path: 'dump.txt', binding: reporter.binding);

  var report = reporter.report;
  print('Number of changes = ${report.numberOfChangeEvents}');
  print('Number of transfers = ${report.numberOfTransferEvents}');

  Map constraintTypes = {};
  constraints.forEachConstraint((c) {
    constraintTypes[c.runtimeType] ??= 0;
    constraintTypes[c.runtimeType]++;
  });
  print(constraintTypes);

  int numTop = 0, numNullable = 0, numOther = 0;
  for (var library in program.libraries) {
    var members = [library.members, library.classes.expand((c) => c.members)]
        .expand((c) => c);
    for (var member in members) {
      var memberResults = results.getResultsForMember(member);
      var value = member is Field
          ? memberResults.value
          : memberResults.getValueOfFunctionReturn(member.function);
      if (value.baseClass == coreTypes.objectClass) {
        ++numTop;
      } else if (value.canBeNull) {
        ++numNullable;
      } else {
        ++numOther;
      }
    }
  }
  print('Top: $numTop\nNullable: $numNullable\nOther: $numOther');

  // program.computeCanonicalNames();
  // var file = new File('report.bin').openWrite();
  // var buffer = new Writer(file);
  // var writer = new BinaryReportWriter(buffer);
  // writer.writeConstraintSystem(constraints);
  // writer.writeEventList(report.transferEvents);
  // writer.finish();
  // await file.close();
  //
  // var reader = new BinaryReportReader(
  //     new Reader(new File('report.bin').readAsBytesSync()));
  // reader.readConstraintSystem();
  // reader.readEventList();
  //
  // writeProgramToBinary(program, 'report.dill');
}
