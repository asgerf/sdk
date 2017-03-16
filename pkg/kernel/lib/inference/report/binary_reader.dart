// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.report.binary_reader;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/report/tags.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';
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
    int numberOfBindings = reader.readUInt();
    for (int i = 0; i < numberOfBindings; ++i) {
      var owner = reader.readCanonicalName().getReference();
      int numberOfStorageLocations = reader.readUInt();
      var cluster = constraintSystem.getCluster(owner);
      cluster.locations.length = numberOfStorageLocations;
      for (int i = 0; i < numberOfStorageLocations; ++i) {
        cluster.locations[i] = new StorageLocation(owner, i);
      }
    }
    numberOfBindings = reader.readUInt();
    for (int i = 0; i < numberOfBindings; ++i) {
      var owner = reader.readCanonicalName().getReference();
      int numberOfConstraints = reader.readUInt();
      var cluster = constraintSystem.getCluster(owner);
      cluster.constraints.length = numberOfConstraints;
      for (int i = 0; i < numberOfConstraints; ++i) {
        cluster.constraints[i] = readConstraint()
          ..owner = owner
          ..index = i;
      }
    }
    return constraintSystem;
  }

  List<Constraint> readConstraintList(Reference owner) {
    int length = reader.readUInt();
    var list = new List<Constraint>(length);
    for (int i = 0; i < length; ++i) {
      list[i] = readConstraint()
        ..owner = owner
        ..index = i;
    }
    return list;
  }

  int readFileOffset() {
    return reader.readUInt() - 1;
  }

  Constraint readConstraint() {
    int fileOffset = readFileOffset();
    int tag = reader.readByte();
    switch (tag) {
      case ConstraintTag.EscapeConstraint:
        return new EscapeConstraint(readLocationReference())
          ..fileOffset = fileOffset;

      case ConstraintTag.SubtypeConstraint:
        return new SubtypeConstraint(
            readLocationReference(),
            readLocationReference(),
            reader.readFixedUInt32())..fileOffset = fileOffset;

      case ConstraintTag.TypeArgumentConstraint:
        return new TypeArgumentConstraint(
            readLocationReference(), readLocationReference(), readValue())
          ..fileOffset = fileOffset;

      case ConstraintTag.ValueConstraint:
        return new ValueConstraint(readLocationReference(), readValue())
          ..fileOffset = fileOffset;
    }
    throw 'Unexpected constraint tag: $tag';
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
