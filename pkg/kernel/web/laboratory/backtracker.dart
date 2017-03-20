// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.backtracker;

import 'dart:html';
import 'history_manager.dart';
import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/storage_location.dart';
import 'type_view.dart';
import 'ui_component.dart';

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

  /// Returns an event listener which will investigate the given storage location
  /// when fired.
  ///
  /// If the [referee] is given, this constraint will be registered as the point
  /// of origin to which we should return when the browser's back button is
  /// pressed.
  MouseEventListener investigateStorageLocationOnEvent(
      StorageLocation location, Constraint referee) {
    return (MouseEvent ev) {
      ev.stopPropagation();
      // Register the location we came from.
      // Note that investigateStorageLocation always registers the destination,
      // so to avoid duplicate history items, avoid registering the currently
      // focused constraint again.
      if (referee != null && referee != ui.constraintView.focusedConstraint) {
        history.push(new HistoryItem(referee.owner,
            constraintIndex: referee.index, timestamp: currentTimestamp));
      }
      investigateStorageLocation(location);
    };
  }

  /// Rewinds time to the most recent change that affected [location] and
  /// focuses the UI on the constraint that caused the change.
  ///
  /// This will push a history item with the new UI location.
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
