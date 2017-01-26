// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.key;

import '../ast.dart';
import 'package:kernel/inference/constraint_builder.dart';
import 'package:kernel/inference/constraints.dart';
import 'solver.dart';
import 'value.dart';

abstract class ValueSource {
  void generateAssignmentTo(
      ConstraintBuilder builder, Key destination, int mask);

  bool isBottom(int mask);

  Value get value;
}

abstract class ValueSink {
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask);

  static final ValueSink nowhere = new NowhereSink();

  static ValueSink error(String reason) => new ErrorSink(reason);
}

class NowhereSink extends ValueSink {
  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {}
}

class ErrorSink extends ValueSink {
  final String what;

  ErrorSink(this.what);

  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {
    throw 'Cannot assign to $what';
  }
}

class Key extends ValueSource implements ValueSink {
  final TreeNode owner; // Class or Member
  final int index;

  // Used by solver
  Value value = new Value(null, Flags.none);
  WorkItem forward, backward;

  Key(this.owner, this.index) {
    forward = new WorkItem(this);
    backward = new WorkItem(this);
  }

  String toString() => '$owner:$index';

  @override
  void generateAssignmentTo(
      ConstraintBuilder builder, Key destination, int mask) {
    builder.addConstraint(new SubtypeConstraint(this, destination, mask));
  }

  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {
    source.generateAssignmentTo(builder, this, mask);
  }

  @override
  bool isBottom(int mask) {
    return false;
  }
}
