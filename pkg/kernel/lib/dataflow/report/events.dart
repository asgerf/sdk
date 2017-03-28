// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.report.events;

import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/storage_location.dart';
import 'package:kernel/dataflow/value.dart';

class TransferEvent {
  final Constraint constraint;
  final int timestamp;

  /// Changes that occurred during this transfer.
  final List<ChangeEvent> changes;

  TransferEvent(this.constraint, this.timestamp, [List<ChangeEvent> changes])
      : this.changes = changes ?? <ChangeEvent>[];
}

class ChangeEvent {
  final StorageLocation location;
  final Value value;
  final bool leadsToEscape;
  final int timestamp;

  ChangeEvent(this.location, this.value, this.leadsToEscape, this.timestamp);
}
