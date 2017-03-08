// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.report.binary_writer;

import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/solver/solver.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';
import 'package:kernel/util/writer.dart';

class BinaryReportWriter implements SolverListener {
  final Writer writer;
  BinaryWriterConstraintVisitor _constraintVisitor;

  BinaryReportWriter(this.writer) {
    _constraintVisitor = new BinaryWriterConstraintVisitor(this);
  }

  void finish() {
    writer.finish();
  }

  void writeByte(int byte) {
    writer.writeByte(byte);
  }

  void writeEventList(List<Event> events) {
    writer.writeUInt(events.length);
    events.forEach(writeEvent);
  }

  void writeEvent(Event event) {
    event.replayTo(this);
  }

  void writeConstraintReference(Constraint constraint) {
    writer.writeReference(constraint.owner.canonicalName);
    writer.writeUInt(constraint.index);
  }

  void writeLocationReference(StorageLocation location) {
    writer.writeReference(location.owner.canonicalName);
    writer.writeUInt(location.index);
  }

  void writeValue(Value value) {
    writer.writeOptionalReference(value.baseClassReference?.canonicalName);
    writer.writeFixedUInt32(value.flags);
  }

  @override
  void onBeginTransfer(Constraint constraint) {
    writer.writeByte(EventTag.OnBeginTransfer);
    writeConstraintReference(constraint);
  }

  @override
  void onChange(StorageLocation location, Value value, bool leadsToEscape) {
    writer.writeByte(EventTag.OnChange);
    writeLocationReference(location);
    writeValue(value);
    writer.writeByte(leadsToEscape ? 1 : 0);
  }

  void writeConstraintDefinition(Constraint constraint) {
    constraint.accept(_constraintVisitor);
  }
}

class EventTag {
  static const int OnBeginTransfer = 0;
  static const int OnChange = 1;
}

class ConstraintTag {
  static const int EscapeConstraint = 0;
  static const int SubtypeConstraint = 1;
  static const int TypeArgumentConstraint = 2;
  static const int ValueConstraint = 3;
}

class BinaryWriterConstraintVisitor extends ConstraintVisitor {
  final BinaryReportWriter writer;

  BinaryWriterConstraintVisitor(this.writer);

  @override
  visitEscapeConstraint(EscapeConstraint constraint) {
    writer.writeByte(ConstraintTag.EscapeConstraint);
    writer.writeLocationReference(constraint.escaping);
  }

  @override
  visitSubtypeConstraint(SubtypeConstraint constraint) {
    writer.writeByte(ConstraintTag.SubtypeConstraint);
    writer.writeLocationReference(constraint.source);
    writer.writeLocationReference(constraint.destination);
    writer.writer.writeFixedUInt32(constraint.mask);
  }

  @override
  visitTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    writer.writeByte(ConstraintTag.TypeArgumentConstraint);
    writer.writeLocationReference(constraint.createdObject);
    writer.writeLocationReference(constraint.typeArgument);
    writer.writeValue(constraint.value);
  }

  @override
  visitValueConstraint(ValueConstraint constraint) {
    writer.writeByte(ConstraintTag.ValueConstraint);
    writer.writeLocationReference(constraint.destination);
    writer.writeValue(constraint.value);
  }
}
