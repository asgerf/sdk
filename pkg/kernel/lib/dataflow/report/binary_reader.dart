// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.report.binary_reader;

import 'package:kernel/ast.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/report/events.dart';
import 'package:kernel/dataflow/report/tags.dart';
import 'package:kernel/dataflow/storage_location.dart';
import 'package:kernel/dataflow/value.dart';
import 'package:kernel/util/reader.dart';

class BinaryReportReader {
  final Reader reader;
  ConstraintSystem constraintSystem;
  int eventTimestamp = 0;

  BinaryReportReader(this.reader);

  void readDebugTag(DebugTag tag) {
    if (reader.readByte() != tag.byte) {
      throw 'Expected ${tag.name}';
    }
  }

  ConstraintSystem readConstraintSystem() {
    constraintSystem = new ConstraintSystem();
    // Read type parameter storage locations
    int numberOfBindings = reader.readUInt();
    for (int i = 0; i < numberOfBindings; ++i) {
      var owner = reader.readCanonicalName().getReference();
      int numberOfTypeParameters = reader.readUInt();
      var cluster = constraintSystem.getCluster(owner);
      cluster.typeParameters.length = numberOfTypeParameters;
      for (int i = 0; i < numberOfTypeParameters; ++i) {
        int indexOfBound = reader.readUInt();
        cluster.typeParameters[i] = new TypeParameterStorageLocation(owner, i)
          ..indexOfBound = indexOfBound;
      }
    }
    // Read storage locations
    numberOfBindings = reader.readUInt();
    for (int i = 0; i < numberOfBindings; ++i) {
      var owner = reader.readCanonicalName().getReference();
      int numberOfStorageLocations = reader.readUInt();
      var cluster = constraintSystem.getCluster(owner);
      cluster.locations.length = numberOfStorageLocations;
      for (int i = 0; i < numberOfStorageLocations; ++i) {
        TypeParameterStorageLocation parameterLocation;
        var typeParameterOwner =
            reader.readOptionalCanonicalName()?.getReference();
        if (typeParameterOwner != null) {
          int index = reader.readUInt();
          parameterLocation = constraintSystem
              .getCluster(typeParameterOwner)
              .typeParameters[index];
        }
        cluster.locations[i] = new StorageLocation(owner, i)
          ..parameterLocation = parameterLocation;
      }
    }
    // Read constraints
    numberOfBindings = reader.readUInt();
    for (int i = 0; i < numberOfBindings; ++i) {
      var owner = reader.readCanonicalName().getReference();
      int numberOfConstraints = reader.readUInt();
      var cluster = constraintSystem.getCluster(owner);
      cluster.constraints.length = numberOfConstraints;
      for (int j = 0; j < numberOfConstraints; ++j) {
        cluster.constraints[j] = readConstraint()
          ..owner = owner
          ..index = j;
      }
    }
    return constraintSystem;
  }

  int readFileOffset() {
    return reader.readUInt() - 1;
  }

  Constraint readConstraint() {
    int fileOffset = readFileOffset();
    int tag = reader.readByte();
    switch (tag) {
      case ConstraintTag.EscapeConstraint:
        return new EscapeConstraint(readLocationReference(),
            guard: readOptionalLocationReference())..fileOffset = fileOffset;

      case ConstraintTag.AssignConstraint:
        return new AssignConstraint(
            readLocationReference(),
            readLocationReference(),
            reader.readFixedUInt32())..fileOffset = fileOffset;

      case ConstraintTag.GuardedValueConstraint:
        return new GuardedValueConstraint(
            readLocationReference(),
            readValue(),
            readLocationReference(),
            reader.readFixedUInt32())..fileOffset = fileOffset;

      case ConstraintTag.ValueConstraint:
        return new ValueConstraint(readLocationReference(), readValue())
          ..fileOffset = fileOffset;

      case ConstraintTag.FilterConstraint:
        return new TypeFilterConstraint(
            readLocationReference(),
            readLocationReference(),
            readClassReference(),
            reader.readFixedUInt32())..fileOffset = fileOffset;
    }
    throw 'Unexpected constraint tag: $tag';
  }

  Class readClassReference() {
    return reader.readOptionalCanonicalName()?.getReference()?.asClass;
  }

  Value readValue() {
    return new Value.fromReference(
        reader.readOptionalCanonicalName()?.getReference(),
        reader.readFixedUInt32());
  }

  Constraint readConstraintReference() {
    var owner = reader.readCanonicalName().getReference();
    int index = reader.readUInt();
    return constraintSystem.getConstraint(owner, index);
  }

  StorageLocation readLocationReference() {
    var owner = reader.readCanonicalName().getReference();
    int index = reader.readUInt();
    return constraintSystem.getStorageLocation(owner, index);
  }

  StorageLocation readOptionalLocationReference() {
    var owner = reader.readOptionalCanonicalName()?.getReference();
    if (owner == null) return null;
    int index = reader.readUInt();
    return constraintSystem.getStorageLocation(owner, index);
  }

  List<TransferEvent> readEventList() {
    int numberOfTransfers = reader.readUInt();
    var list = new List<TransferEvent>(numberOfTransfers);
    for (int i = 0; i < numberOfTransfers; ++i) {
      list[i] = readTransferEvent(i);
    }
    return list;
  }

  TransferEvent readTransferEvent(int timestamp) {
    var constraint = readConstraintReference();
    var changes = readChangeEventList(timestamp);
    return new TransferEvent(constraint, timestamp, changes);
  }

  List<ChangeEvent> readChangeEventList(int timestamp) {
    var length = reader.readUInt();
    var list = new List<ChangeEvent>(length);
    for (int i = 0; i < length; ++i) {
      list[i] = readChangeEvent(timestamp);
    }
    return list;
  }

  ChangeEvent readChangeEvent(int timestamp) {
    var location = readLocationReference();
    var value = readValue();
    var leadsToEscape = readBoolean();
    return new ChangeEvent(location, value, leadsToEscape, timestamp);
  }

  bool readBoolean() {
    return reader.readByte() != 0;
  }
}
