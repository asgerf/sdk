// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.value_sink;

import 'constraint_builder.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/inference/key.dart';
import 'value_source.dart';

abstract class ValueSink {
  static final ValueSink nowhere = new NowhereSink();
  static final ValueSink escape = new EscapingSink();

  static ValueSink unassignable(String what, [TreeNode where]) {
    return new UnassignableSink(what, where);
  }

  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask);

  T acceptSink<T>(ValueSinkVisitor<T> visitor);
}

class NowhereSink extends ValueSink {
  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {}

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitNowhereSink(this);
  }
}

class UnassignableSink extends ValueSink {
  final String what;
  final TreeNode where;

  UnassignableSink(this.what, [this.where]);

  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {
    throw 'Cannot assign to $what (${where.location})';
  }

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitUnassignableSink(this);
  }
}

class EscapingSink extends ValueSink {
  @override
  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask) {
    source.generateEscape(builder);
  }

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitEscapingSink(this);
  }
}

abstract class ValueSinkVisitor<T> {
  T visitKey(Key key);
  T visitNowhereSink(NowhereSink sink);
  T visitUnassignableSink(UnassignableSink sink);
  T visitEscapingSink(EscapingSink sink);
}
