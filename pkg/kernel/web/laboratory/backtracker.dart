// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.backtracker;

import 'dart:html';
import 'history.dart';
import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/storage_location.dart';
import 'type_view.dart';
import 'ui_component.dart';
import 'view.dart';

class Backtracker extends UIComponent {
  final Element containerElement;
  final ProgressElement progressElement;
  final ButtonElement resetButton;

  int _currentTimestamp = 0;

  Backtracker(this.containerElement, this.progressElement, this.resetButton) {
    resetButton.onClick.listen(onResetButtonClick);
  }

  int get currentTimestamp => _currentTimestamp;

  void set currentTimestamp(int time) {
    _currentTimestamp = time;
    invalidate();
  }

  bool get isBacktracking => currentTimestamp < report.endOfTime;

  void onResetButtonClick(MouseEvent ev) {
    reset();
  }

  void reset() {
    currentTimestamp = report?.endOfTime;
    ui.constraintView.unfocusConstraint();
    invalidate();
  }

  @override
  void buildHtml() {
    if (report == null ||
        report.endOfTime == 0 ||
        currentTimestamp == report.endOfTime) {
      containerElement.style.visibility = 'hidden';
      return;
    }
    progressElement.max = report.endOfTime;
    progressElement.value = currentTimestamp;
    containerElement.style.visibility = 'visible';
  }

  MouseEventListener investigateStorageLocationOnEvent(
      StorageLocation location, Constraint referee) {
    return (MouseEvent ev) {
      ev.stopPropagation();
      if (referee != null && referee != ui.constraintView.focusedConstraint) {
        history.push(new HistoryItem(referee.owner,
            constraintIndex: referee.index, timestamp: currentTimestamp));
      }
      investigateStorageLocation(location);
    };
  }

  void investigateStorageLocation(StorageLocation location) {
    if (report == null) return;
    var changeEvent =
        report.getMostRecentChange(location, currentTimestamp - 1);
    if (changeEvent.timestamp == Report.beginningOfTime) return;
    var transferEvent =
        report.getTransferEventFromTimestamp(changeEvent.timestamp);
    currentTimestamp = changeEvent.timestamp;
    var constraint = transferEvent.constraint;
    ui.codeView.showConstraint(constraint);
    invalidate();
    history.push(new HistoryItem(constraint.owner,
        constraintIndex: constraint.index, timestamp: currentTimestamp));
  }
}
