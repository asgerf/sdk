// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.timeline;

import 'dart:html';
import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/storage_location.dart';
import 'type_view.dart';

class Timeline {
  final Element containerElement;
  final ProgressElement progressElement;
  final ButtonElement resetButton;

  int currentTimestamp = 0;

  Timeline(this.containerElement, this.progressElement, this.resetButton) {
    resetButton.onClick.listen(onResetButtonClick);
    hide();
  }

  void onResetButtonClick(MouseEvent ev) {
    reset();
  }

  void reset() {
    currentTimestamp = report?.endOfTime;
    updateUI();
  }

  void hide() {
    containerElement.style.visibility = 'hidden';
  }

  void updateUI() {
    if (report == null ||
        report.endOfTime == 0 ||
        currentTimestamp == report.endOfTime) {
      hide();
      return;
    }
    progressElement.max = report.endOfTime;
    progressElement.value = currentTimestamp;
    containerElement.style.visibility = 'visible';
  }

  MouseEventListener investigateStorageLocationOnEvent(
      StorageLocation location) {
    return (MouseEvent ev) {
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
    currentTimestamp = changeEvent.timestamp - 1;
    var constraint = transferEvent.constraint;
    var owner = constraint.owner;
    ui.codeView.showObject(owner.node);
    ui.typeView.showStorageLocation(location);
    updateUI();
  }
}
