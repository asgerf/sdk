// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.value_sink;

import '../../ast.dart';
import '../../inference/key.dart';

abstract class ValueSink {
  static final ValueSink nowhere = new NowhereSink();
  static final ValueSink escape = new EscapingSink();

  static ValueSink unassignable(String what, [TreeNode where]) {
    return new UnassignableSink(what, where);
  }

  T acceptSink<T>(ValueSinkVisitor<T> visitor);
}

class NowhereSink extends ValueSink {
  T acceptSink<T>(ValueSinkVisitor<T> visitor) {
    return visitor.visitNowhereSink(this);
  }
}

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

class EscapingSink extends ValueSink {
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
