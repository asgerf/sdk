// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.report.binary_writer;

import 'package:kernel/ast.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/report/events.dart';
import 'package:kernel/dataflow/report/tags.dart';
import 'package:kernel/dataflow/storage_location.dart';
import 'package:kernel/dataflow/value.dart';
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
      writeTypeParameterStorageLocations(cluster.typeParameters);
    });
    writer.writeUInt(constraints.clusters.length);
    constraints.clusters.forEach((Reference owner, ConstraintCluster cluster) {
      writer.writeCanonicalName(owner.canonicalName);
      writeStorageLocations(cluster.locations);
    });
    writer.writeUInt(constraints.clusters.length);
    constraints.clusters.forEach((Reference owner, ConstraintCluster cluster) {
      writer.writeCanonicalName(owner.canonicalName);
      writeConstraintList(cluster.constraints);
    });
  }

  void writeTypeParameterStorageLocations(
      List<TypeParameterStorageLocation> typeParameters) {
    writer.writeUInt(typeParameters.length);
    for (var typeParameter in typeParameters) {
      writer.writeUInt(typeParameter.indexOfBound);
    }
  }

  void writeStorageLocations(List<StorageLocation> locations) {
    writer.writeUInt(locations.length);
    for (var location in locations) {
      var parameter = location.parameterLocation;
      if (location.parameterLocation == null) {
        writer.writeOptionalCanonicalName(null);
      } else {
        writer.writeCanonicalName(parameter.owner.canonicalName);
        writer.writeUInt(parameter.typeParameterIndex);
      }
    }
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

  void writeOptionalLocationReference(StorageLocation location) {
    if (location == null) {
      writer.writeOptionalCanonicalName(null);
    } else {
      writeLocationReference(location);
    }
  }

  void writeValue(Value value) {
    writer.writeOptionalCanonicalName(value.baseClassReference?.canonicalName);
    writer.writeFixedUInt32(value.flags);
  }

  void writeClassReference(Class class_) {
    writer.writeOptionalCanonicalName(class_?.canonicalName);
  }
}

class BinaryWriterConstraintVisitor extends ConstraintVisitor {
  final BinaryReportWriter writer;

  BinaryWriterConstraintVisitor(this.writer);

  @override
  visitEscapeConstraint(EscapeConstraint constraint) {
    writer.writeByte(ConstraintTag.EscapeConstraint);
    writer.writeLocationReference(constraint.escaping);
    writer.writeOptionalLocationReference(constraint.guard);
    writer.writer.writeFixedUInt32(constraint.guardMask);
  }

  @override
  visitAssignConstraint(AssignConstraint constraint) {
    writer.writeByte(ConstraintTag.AssignConstraint);
    writer.writeLocationReference(constraint.source);
    writer.writeLocationReference(constraint.destination);
    writer.writer.writeFixedUInt32(constraint.mask);
  }

  @override
  visitGuardedValueConstraint(GuardedValueConstraint constraint) {
    writer.writeByte(ConstraintTag.GuardedValueConstraint);
    writer.writeLocationReference(constraint.destination);
    writer.writeValue(constraint.value);
    writer.writeLocationReference(constraint.guard);
    writer.writer.writeFixedUInt32(constraint.guardMask);
  }

  @override
  visitValueConstraint(ValueConstraint constraint) {
    writer.writeByte(ConstraintTag.ValueConstraint);
    writer.writeLocationReference(constraint.destination);
    writer.writeValue(constraint.value);
  }

  @override
  visitTypeFilterConstraint(TypeFilterConstraint constraint) {
    writer.writeByte(ConstraintTag.TypeFilterConstraint);
    writer.writeLocationReference(constraint.source);
    writer.writeLocationReference(constraint.destination);
    writer.writeClassReference(constraint.interfaceClass);
    writer.writer.writeFixedUInt32(constraint.mask);
  }

  @override
  visitValueFilterConstraint(ValueFilterConstraint constraint) {
    writer.writeByte(ConstraintTag.ValueFilterConstraint);
    writer.writeLocationReference(constraint.source);
    writer.writeLocationReference(constraint.destination);
    writer.writeValue(constraint.guard);
  }

  @override
  visitAllocationConstraint(AllocationConstraint constraint) {
    writer.writeByte(ConstraintTag.AllocationConstraint);
    writer.writeLocationReference(constraint.destination);
    writer.writeLocationReference(constraint.toStringReturn);
    writer.writeLocationReference(constraint.hashCodeReturn);
    writer.writeLocationReference(constraint.runtimeTypeReturn);
    writer.writeLocationReference(constraint.equalsReturn);
    writer.writeLocationReference(constraint.equalsArgument);
  }

  @override
  visitEscapingAssignConstraint(EscapingAssignConstraint constraint) {
    writer.writeByte(ConstraintTag.EscapingAssignConstraint);
    writer.writeLocationReference(constraint.source);
    writer.writeLocationReference(constraint.destination);
  }
}
