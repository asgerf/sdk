// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.solver.report;

import '../constraints.dart';
import '../storage_location.dart';
import '../value.dart';
import '../solver/solver.dart' show SolverListener;

class Report implements SolverListener {
  static const int beginningOfTime = -1;

  /// List of all transfer events, in the order they were emitted.
  final List<TransferEvent> transferEvents;

  /// Change events indexed by storage location and sorted by timestamp.
  final Map<StorageLocation, List<ChangeEvent>> locationChanges =
      <StorageLocation, List<ChangeEvent>>{};

  int get endOfTime => transferEvents.length + 1;

  Report() : transferEvents = <TransferEvent>[];

  Report.fromTransfers(this.transferEvents) {
    for (var event in transferEvents) {
      for (var change in event.changes) {
        _addChangeEventToIndex(change);
      }
    }
  }

  int get timestamp =>
      transferEvents.isEmpty ? beginningOfTime : transferEvents.length - 1;

  int get numberOfTransferEvents => transferEvents.length;

  int get numberOfChangeEvents {
    int sum = 0;
    for (var event in transferEvents) {
      sum += event.changes.length;
    }
    return sum;
  }

  @override
  void onBeginTransfer(Constraint constraint) {
    transferEvents.add(new TransferEvent(constraint, timestamp));
  }

  /// Called by the solver when the information associated with [location]
  /// changes.
  @override
  void onChange(StorageLocation location, Value value, bool leadsToEscape) {
    assert(transferEvents.isNotEmpty); // Must be called during a transfer.
    var event = new ChangeEvent(location, value, leadsToEscape, timestamp);
    transferEvents[event.timestamp].changes.add(event);
    _addChangeEventToIndex(event);
  }

  void _addChangeEventToIndex(ChangeEvent event) {
    locationChanges
        .putIfAbsent(
            event.location, () => _makeInitialEventList(event.location))
        .add(event);
  }

  List<ChangeEvent> _makeInitialEventList(StorageLocation location) {
    return <ChangeEvent>[ChangeEvent.beginning(location)];
  }

  ChangeEvent getMostRecentChange(StorageLocation location, int timestamp) {
    List<ChangeEvent> list = locationChanges[location];
    if (list == null) return ChangeEvent.beginning(location);
    int first = 0, last = list.length - 1;
    while (first < last) {
      int mid = last - ((last - first) >> 1); // Get middle, rounding up.
      var pivot = list[mid];
      int pivotTimestamp = pivot.timestamp;
      if (pivotTimestamp < timestamp) {
        first = mid; // first is still a candidate
      } else if (timestamp < pivotTimestamp) {
        last = mid - 1;
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
  final List<ChangeEvent> changes;

  TransferEvent(this.constraint, this.timestamp, [List<ChangeEvent> changes])
      : this.changes = changes ?? <ChangeEvent>[];
}
