// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.report.binary_writer;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/report/tags.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';
import 'package:kernel/util/writer.dart';

class BinaryReportWriter {
  final Writer writer;
  BinaryWriterConstraintVisitor _constraintVisitor;

  BinaryReportWriter(this.writer) {
    _constraintVisitor = new BinaryWriterConstraintVisitor(this);
  }

  void writeDebugTag(DebugTag tag) {
    writer.writeByte(tag.byte);
  }

  void finish() {
    writer.finish();
  }

  void writeByte(int byte) {
    writer.writeByte(byte);
  }

  void writeConstraintSystem(ConstraintSystem constraints) {
    writer.writeUInt(constraints.clusters.length);
    constraints.clusters.forEach((Reference owner, ConstraintCluster cluster) {
      writer.writeCanonicalName(owner.canonicalName);
      writer.writeUInt(cluster.locations.length);
    });
    writer.writeUInt(constraints.clusters.length);
    constraints.clusters.forEach((Reference owner, ConstraintCluster cluster) {
      writer.writeCanonicalName(owner.canonicalName);
      writeConstraintList(cluster.constraints);
    });
  }

  void writeConstraints(ConstraintSystem constraintSystem) {
    writer.writeUInt(constraintSystem.clusters.length);
    constraintSystem.clusters
        .forEach((Reference owner, ConstraintCluster cluster) {
      writer.writeCanonicalName(owner.canonicalName);
      writeConstraintList(cluster.constraints);
    });
  }

  void writeConstraintList(List<Constraint> constraints) {
    writer.writeUInt(constraints.length);
    constraints.forEach(writeConstraintDefinition);
  }

  void writeFileOffset(int offset) {
    writer.writeUInt(offset + 1);
  }

  void writeConstraintDefinition(Constraint constraint) {
    writeFileOffset(constraint.fileOffset);
    constraint.accept(_constraintVisitor);
  }

  void writeEventList(List<TransferEvent> events) {
    writer.writeUInt(events.length);
    events.forEach(writeTransferEvent);
  }

  void writeTransferEvent(TransferEvent event) {
    writeConstraintReference(event.constraint);
    writer.writeUInt(event.changes.length);
    event.changes.forEach(writeChangeEvent);
  }

  void writeChangeEvent(ChangeEvent event) {
    writeLocationReference(event.location);
    writeValue(event.value);
    writeByte(event.leadsToEscape ? 1 : 0);
  }

  void writeConstraintReference(Constraint constraint) {
    writer.writeCanonicalName(constraint.owner.canonicalName);
    writer.writeUInt(constraint.index);
  }

  void writeLocationReference(StorageLocation location) {
    writer.writeCanonicalName(location.owner.canonicalName);
    writer.writeUInt(location.index);
  }

  void writeValue(Value value) {
    writer.writeOptionalCanonicalName(value.baseClassReference?.canonicalName);
    writer.writeFixedUInt32(value.flags);
  }
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
