// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.key;

import '../ast.dart';
import 'extractor/value_sink.dart';
import 'extractor/value_source.dart';
import 'solver/solver.dart';
import 'value.dart';

class StorageLocation extends ValueSource implements ValueSink {
  final TreeNode owner; // Class or Member
  final int index;

  bool isNullabilityKey = false;

  // Used by solver
  Value value = new Value(null, Flags.none);
  WorkItem forward, backward;

  StorageLocation(this.owner, this.index) {
    forward = new WorkItem(this);
    backward = new WorkItem(this);
  }

  String toString() => '$owner:$index';

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitStorageLocation(this);
  }

  T acceptSource<T>(ValueSourceVisitor<T> visitor) {
    return visitor.visitStorageLocation(this);
  }

  @override
  bool isBottom(int mask) {
    return false;
  }
}
