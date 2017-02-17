// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.key;

import '../ast.dart';
import 'extractor/constraint_builder.dart';
import 'constraints.dart';
import 'solver/solver.dart';
import 'value.dart';
import 'extractor/value_source.dart';

abstract class ValueSink {
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask);

  static final ValueSink nowhere = new NowhereSink();
  static final ValueSink escape = new EscapingSink();

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

class EscapingSink extends ValueSink {
  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {
    source.generateEscape(builder);
  }
}

class Key extends ValueSource implements ValueSink {
  final TreeNode owner; // Class or Member
  final int index;

  bool isNullabilityKey = false;

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
  void generateEscape(ConstraintBuilder builder) {
    builder.addConstraint(new EscapeConstraint(this));
  }

  @override
  bool isBottom(int mask) {
    return false;
  }
}
