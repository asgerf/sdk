// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory;

import 'codeview.dart';
import 'dart:async';
import 'dart:html';
import 'dart:typed_data';
import 'package:kernel/ast.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/inference/report/binary_reader.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/library_index.dart';
import 'package:kernel/util/reader.dart';

import 'laboratory_ui.dart' show ui;
export 'laboratory_ui.dart' show ui;

Program program;
ConstraintSystem constraintSystem;
Report report;
LibraryIndex libraryIndex;

info(message) {
  print(message);
}

main() {
  ui.kernelFileInput.onChange.listen((_) => loadKernelFile());
  ui.reportFileInput.onChange.listen((_) => loadReportFile());
  ui.reloadButton.onClick.listen((_) {
    if (ui.kernelFileInput.files.isEmpty || ui.reportFileInput.files.isEmpty) {
      return;
    }
    loadKernelFile();
    loadReportFile();
  });
}

void onProgramLoaded() {
  libraryIndex = new LibraryIndex.all(program);
  ui.searchBox.onProgramLoaded();
  ui.codeView.showMember(program.mainMethod);
}

void onReportFileLoaded() {}

Future<Uint8List> readBytesFromFileInput(FileUploadInputElement input) async {
  if (input.files.isEmpty) return null;
  var file = input.files.first;
  if (file == null) return null;
  FileReader reader = new FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoadEnd.first;
  return reader.result as Uint8List;
}

loadKernelFile() async {
  var bytes = await readBytesFromFileInput(ui.kernelFileInput);
  if (bytes == null) return;
  program = new Program();
  new BinaryBuilder(bytes).readProgram(program);
  info('Read kernel file with ${program.libraries.length} libraries');
  onProgramLoaded();
}

loadReportFile() async {
  if (program == null) {
    info('Load the program first');
    return;
  }
  var bytes = await readBytesFromFileInput(ui.reportFileInput);
  if (bytes == null) return;
  var reader = new BinaryReportReader(new Reader(bytes, program.root));
  program.computeCanonicalNames();
  constraintSystem = reader.readConstraintSystem();
  var events = reader.readEventList();
  report = new Report.fromTransfers(events);
  info('Read report with '
      '${reader.constraintSystem.numberOfConstraints} constraints and '
      '${events.length} transfer events');
  onReportFileLoaded();
}
