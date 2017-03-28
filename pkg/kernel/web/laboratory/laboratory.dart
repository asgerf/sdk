// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory;

import 'dart:async';
import 'dart:html';
import 'dart:typed_data';

import 'package:kernel/ast.dart';
import 'package:kernel/binary/ast_from_binary.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/dataflow.dart';
import 'package:kernel/dataflow/value.dart';
import 'package:kernel/library_index.dart';

import 'history_manager.dart';
import 'key_codes.dart';
import 'laboratory_data.dart';
import 'laboratory_ui.dart' show ui;

export 'laboratory_data.dart';
export 'laboratory_ui.dart' show ui;

info(message) {
  print(message);
}

final Map<int, Element> hotkeys = <int, Element>{
  KeyCodes.q: ui.searchBox.inputElement
};

main() {
  ui.kernelFileInput.onChange.listen((_) async {
    try {
      await loadKernelFile();
    } catch (e) {
      showError('Crash.\n$e');
    }
  });
  ui.body.onKeyPress.listen(onBodyKeyPressed);
}

void startMainUI() {
  history = new HistoryManager();
  history.replace(new HistoryItem(program.mainMethodName));
  ui.codeView.showObject(program.mainMethodName);
  ui.mainContentDiv.style.visibility = 'visible';
  ui.fileSelectDiv.style.display = 'none';
  ui.loadingScreenContainer.style.display = 'none';
}

void onBodyKeyPressed(KeyboardEvent ev) {
  if (ev.target != ui.body) return;
  var target = hotkeys[ev.which];
  if (target != null) {
    ev.preventDefault();
    ev.stopPropagation();
    target.focus();
  }
}

Future onProgramLoaded() async {
  await showProgress('Indexing program...');
  program.computeCanonicalNames();
  libraryIndex = new LibraryIndex.all(program);
  coreTypes = new CoreTypes(program);
  classHierarchy = new ClassHierarchy(program);
  valueLattice = new ValueLattice(classHierarchy);
  await showProgress('Running dataflow analysis...');
  var reporter = new DataflowReporter();
  DataflowEngine.analyzeWholeProgram(program, diagnostic: reporter);
  report = reporter.report;
  constraintSystem = reporter.constraintSystem;
  ui.backtracker.reset();
  if (report != null && program != null) {
    startMainUI();
  }
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

void showLoadingScreen() {
  ui.fileSelectDiv.style.display = 'none';
  ui.loadingScreenContainer.style.display = 'block';
}

Element progressLoadingDiv;
Stopwatch progressStopwatch = new Stopwatch();

Future showProgress(String message) async {
  finishLastLoadingMessage();
  var row = new TableRowElement();
  row.append(new TableCellElement()..text = message);
  progressLoadingDiv = new TableCellElement();
  row.append(progressLoadingDiv);
  ui.loadingScreenTable.append(row);
  progressStopwatch
    ..reset()
    ..start();
  var completer = new Completer();
  window.requestAnimationFrame(completer.complete);
  return completer.future;
}

void showError(Object error) {
  finishLastLoadingMessage();
  var row = new TableRowElement();
  row.append(new TableCellElement()
    ..text = '$error'
    ..style.color = 'red'
    ..colSpan = 2);
  ui.loadingScreenTable.append(row);
}

void finishLastLoadingMessage() {
  var milliseconds = progressStopwatch.elapsedMilliseconds;
  progressLoadingDiv?.appendText(' [$milliseconds ms]');
  progressLoadingDiv = null;
}

Future loadKernelFile() async {
  showLoadingScreen();
  await showProgress('Loading kernel file ${ui.kernelFileInput}...');
  var bytes = await readBytesFromFileInput(ui.kernelFileInput);
  if (bytes == null) {
    await showProgress('Error: Could not load file');
    return null;
  }
  await showProgress('Deserializing kernel program...');
  finishLastLoadingMessage();
  program = new Program();
  new BinaryBuilder(bytes).readProgram(program);
  return onProgramLoaded();
}
