// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.solver.report;

import 'constraints.dart';
import 'storage_location.dart';
import 'value.dart';
import 'solver/solver.dart' show SolverListener;

class Report implements SolverListener {
  static const int beginningOfTime = -1;

  /// Change events that affect a given storage location, in the order they
  /// were emitted.
  final Map<StorageLocation, List<ChangeEvent>> locationChanges = {};

  /// List of all change events, in the order they were emitted.
  final List<ChangeEvent> changeEvents = <ChangeEvent>[];

  /// List of all transfer events, in the order they were emitted.
  final List<TransferEvent> transferEvents = <TransferEvent>[];

  TransferEvent get _currentTransferEvent => transferEvents.last;

  int _timestamp = 0;

  int get lastTimestamp => _timestamp;

  void onBeginTransfer(Constraint constraint) {
    ++_timestamp;
    transferEvents.add(new TransferEvent(constraint, _timestamp));
  }

  /// Called by the solver when the information associated with [location]
  /// changes.
  void onChange(StorageLocation location, Value value, bool leadsToEscape) {
    assert(transferEvents.isNotEmpty); // Must be called during a transfer.
    var event = new ChangeEvent(location, value, leadsToEscape, _timestamp);
    _currentTransferEvent.changes.add(event);
    changeEvents.add(event);
    locationChanges
        .putIfAbsent(location, () => _makeInitialEventList(location))
        .add(event);
  }

  List<ChangeEvent> _makeInitialEventList(StorageLocation location) {
    return <ChangeEvent>[ChangeEvent.beginning(location)];
  }

  ChangeEvent getMostRecentChange(StorageLocation location, int timestamp) {
    List<ChangeEvent> list = locationChanges[location];
    if (list == null) return ChangeEvent.beginning(location);
    int first = 0, last = list.length - 1;
    while (first <= last) {
      int mid = first + ((last - first) >> 1);
      var pivot = list[mid];
      int pivotTimestamp = pivot.timestamp;
      if (pivotTimestamp < timestamp) {
        last = mid; // last is still a candidate
      } else if (timestamp < pivotTimestamp) {
        first = mid + 1;
      } else {
        return pivot;
      }
    }
    return list[first];
  }

  Value getValue(StorageLocation location, int timestamp) {
    return getMostRecentChange(location, timestamp).value;
  }

  bool leadsToEscape(StorageLocation location, int timestamp) {
    return getMostRecentChange(location, timestamp).leadsToEscape;
  }
}

class ChangeEvent {
  final StorageLocation location;
  final Value value;
  final bool leadsToEscape;
  final int timestamp;

  ChangeEvent(this.location, this.value, this.leadsToEscape, this.timestamp);

  static ChangeEvent beginning(StorageLocation location) {
    return new ChangeEvent(
        location, Value.bottom, false, Report.beginningOfTime);
  }

  bool get isAtBeginningOfTime => timestamp == Report.beginningOfTime;
}

class TransferEvent {
  final Constraint constraint;
  final int timestamp;

  /// Changes that occurred during this transfer.
  final List<ChangeEvent> changes = <ChangeEvent>[];

  TransferEvent(this.constraint, this.timestamp);
}
