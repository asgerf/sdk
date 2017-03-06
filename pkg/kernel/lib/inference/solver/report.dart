// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.solver.report;

import '../constraints.dart';
import '../storage_location.dart';
import '../value.dart';

class Report {
  static const int beginningOfTime = -1;

  /// Events indexed by the storage location that changed, sorted by timestamp.
  ///
  /// All lists start with an initial event mapping all values to bottom with
  /// a special timestamp of -1.
  final Map<StorageLocation, List<ChangeEvent>> _locationChanges = {};

  final List<ChangeEvent> _changeEvents = <ChangeEvent>[];
  final List<TransferEvent> _transferEvents = <TransferEvent>[];

  TransferEvent get _currentTransferEvent => _transferEvents.last;

  int _timestamp = 0;

  void onBeginTranfer(Constraint constraint) {
    ++_timestamp;
    _transferEvents.add(new TransferEvent(constraint, _timestamp));
  }

  /// Called by the solver when the information associated with [location]
  /// changes.
  void onChange(StorageLocation location, Value value, bool leadsToEscape) {
    assert(_transferEvents.isNotEmpty); // Must be called during a transfer.
    var event = new ChangeEvent(location, value, leadsToEscape, _timestamp);
    _currentTransferEvent.changes.add(event);
    _changeEvents.add(event);
    _locationChanges
        .putIfAbsent(location, () => _makeInitialEventList(location))
        .add(event);
  }

  List<ChangeEvent> _makeInitialEventList(StorageLocation location) {
    return <ChangeEvent>[ChangeEvent.beginning(location)];
  }

  ChangeEvent getMostRecentChange(StorageLocation location, int timestamp) {
    List<ChangeEvent> list = _locationChanges[location];
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
