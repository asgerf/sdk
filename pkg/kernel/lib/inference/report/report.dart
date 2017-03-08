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

  /// Change events that affect a given storage location, in the order they
  /// were emitted.
  final Map<StorageLocation, List<ChangeEvent>> locationChanges = {};

  final List<Event> allEvents = <Event>[];

  /// List of all change events, in the order they were emitted.
  final List<ChangeEvent> changeEvents = <ChangeEvent>[];

  /// List of all transfer events, in the order they were emitted.
  final List<TransferEvent> transferEvents = <TransferEvent>[];

  int get timestamp =>
      transferEvents.isEmpty ? beginningOfTime : transferEvents.length - 1;

  void onBeginTransfer(Constraint constraint) {
    addTransferEvent(new TransferEvent(constraint, timestamp));
  }

  /// Called by the solver when the information associated with [location]
  /// changes.
  void onChange(StorageLocation location, Value value, bool leadsToEscape) {
    assert(transferEvents.isNotEmpty); // Must be called during a transfer.
    addChangeEvent(new ChangeEvent(location, value, leadsToEscape, timestamp));
  }

  void addTransferEvent(TransferEvent event) {
    allEvents.add(event);
    transferEvents.add(event);
  }

  void addChangeEvent(ChangeEvent event) {
    allEvents.add(event);
    transferEvents[event.timestamp].changes.add(event);
    changeEvents.add(event);
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

  void replayTo(SolverListener listener) {
    for (var event in allEvents) {
      event.replayTo(listener);
    }
  }
}

abstract class Event {
  void replayTo(SolverListener listener);
}

class ChangeEvent extends Event {
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

  void replayTo(SolverListener listener) {
    listener.onChange(location, value, leadsToEscape);
  }
}

class TransferEvent extends Event {
  final Constraint constraint;
  final int timestamp;

  /// Changes that occurred during this transfer.
  final List<ChangeEvent> changes = <ChangeEvent>[];

  TransferEvent(this.constraint, this.timestamp);

  void replayTo(SolverListener listener) {
    listener.onBeginTransfer(constraint);
  }
}
