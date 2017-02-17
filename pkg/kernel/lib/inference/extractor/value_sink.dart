// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.value_sink;

import 'constraint_builder.dart';
import 'value_source.dart';

abstract class ValueSink {
  static final ValueSink nowhere = new NowhereSink();
  static final ValueSink escape = new EscapingSink();

  static ValueSink error(String reason) => new ErrorSink(reason);

  void generateAssignmentFrom(
      ConstraintBuilder builder, ValueSource source, int mask);
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
