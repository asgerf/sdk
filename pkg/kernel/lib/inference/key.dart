// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.key;

import '../ast.dart';
import 'solver.dart';
import 'value.dart';

class Key {
  final TreeNode owner; // Class or Member
  final int index;

  // Used by solver
  Value value;
  WorkItem forward, backward;

  Key(this.owner, this.index) {
    forward = new WorkItem(this);
    backward = new WorkItem(this);
  }

  String toString() => '$owner:$index';
}
