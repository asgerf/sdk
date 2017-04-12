// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.value_sink;

import '../../ast.dart';
import '../storage_location.dart';

/// Describes the effects of moving a value somewhere.
///
/// This abstraction is used by constraint generation to work with types that
/// do not have an associated [StorageLocation].
abstract class ValueSink {
  /// Sink that ignores incoming values.
  static final ValueSink nowhere = new NowhereSink();

  /// Sink that escapes incoming values.
  static final ValueSink escape = new EscapingSink();

  /// Sink that should never be used in an assignment.
  static ValueSink unassignable(String what, [TreeNode where]) {
    return new UnassignableSink(what, where);
  }

  T acceptSink<T>(ValueSinkVisitor<T> visitor);
}

/// A sink that ignores incoming values.
///
/// This is used to simplify constraint generation, since some helper methods
/// can return a type that can be assigned into, but it has no consequence.
///
/// For example, the condition to an `if` is assigned to the boolean type, but
/// it has no consequence that a given value flows into the `bool` type.
class NowhereSink extends ValueSink {
  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitNowhereSink(this);
  }
}

/// A sink to use for a type that should not be used as a sink.
///
/// For instance, the type of an expression, or the type of 'this', have
/// unassignable sinks because the constraint generator should not use
/// them as sinks.
///
/// Unassignable sinks carry some debugging information to help track down the
/// source of the error.
class UnassignableSink extends ValueSink {
  final String what;
  final TreeNode where;

  UnassignableSink(this.what, [this.where]);

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitUnassignableSink(this);
  }
}

class UnassignableSinkError {
  final UnassignableSink sink;
  Location assignmentLocation;

  UnassignableSinkError(this.sink, [this.assignmentLocation]);

  String toString() {
    var message = 'Cannot assign to ${sink.what} (${sink.where?.location})}';
    if (assignmentLocation != null) {
      message += '\nat $assignmentLocation';
    }
    return message;
  }
}

/// Sink that causes incoming values to escape but are otherwise not tracked
/// any further.
class EscapingSink extends ValueSink {
  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitEscapingSink(this);
  }
}

class ValueSinkWithEscape extends ValueSink {
  final ValueSink base, escaping;

  ValueSinkWithEscape(this.base, this.escaping);

  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitValueSinkWithEscape(this);
  }
}

abstract class ValueSinkVisitor<T> {
  T visitStorageLocation(StorageLocation sink);
  T visitNowhereSink(NowhereSink sink);
  T visitUnassignableSink(UnassignableSink sink);
  T visitEscapingSink(EscapingSink sink);
  T visitValueSinkWithEscape(ValueSinkWithEscape sink);
}
