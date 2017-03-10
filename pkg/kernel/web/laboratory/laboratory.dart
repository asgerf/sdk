import 'dart:async';
import 'dart:html';
import 'dart:typed_data';
import 'package:kernel/ast.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/inference/report/binary_reader.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/util/reader.dart';

FileUploadInputElement reportFileInput =
    document.getElementById('report-file-input');

FileUploadInputElement kernelFileInput =
    document.getElementById('kernel-file-input');

ButtonElement reloadButton = document.getElementById('reload-button');

DivElement debugBox = document.getElementById('debug-box');

Program program;
ConstraintSystem constraintSystem;
Report report;

info(message) {
  print(message);
}

main() {
  kernelFileInput.onChange.listen((_) => loadKernelFile());
  reportFileInput.onChange.listen((_) => loadReportFile());
  reloadButton.onClick.listen((_) {
    if (kernelFileInput.files.isEmpty || reportFileInput.files.isEmpty) return;
    loadKernelFile();
    loadReportFile();
  });
}

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
  var bytes = await readBytesFromFileInput(kernelFileInput);
  if (bytes == null) return;
  program = new Program();
  new BinaryBuilder(bytes).readProgram(program);
  info('Read kernel file with ${program.libraries.length} libraries');
}

loadReportFile() async {
  if (program == null) {
    info('Load the program first');
    return;
  }
  var bytes = await readBytesFromFileInput(reportFileInput);
  if (bytes == null) return;
  var reader = new BinaryReportReader(new Reader(bytes, program.root));
  constraintSystem = reader.readConstraintSystem();
  var events = reader.readEventList();
  report = new Report.fromTransfers(events);
  info('Read report with '
      '${reader.constraintSystem.numberOfConstraints} constraints and '
      '${events.length} transfer events');
}
