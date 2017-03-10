// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.report.binary_reader;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/raw_binding.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/report/tags.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';
import 'package:kernel/util/reader.dart';

class BinaryReportReader {
  final Reader reader;
  final ConstraintSystem constraintSystem = new ConstraintSystem();
  int eventTimestamp = 0;

  RawBinding get binding => constraintSystem.binding;

  BinaryReportReader(this.reader);

  void readDebugTag(DebugTag tag) {
    if (reader.readByte() != tag.byte) {
      throw 'Expected ${tag.name}';
    }
  }

  void readBindings() {
    int numberOfBindings = reader.readUInt();
    for (int i = 0; i < numberOfBindings; ++i) {
      var reference = reader.readCanonicalName().getReference();
      int numberOfStorageLocations = reader.readUInt();
      binding.setBinding(
          reference,
          new List<StorageLocation>.generate(numberOfStorageLocations,
              (i) => new StorageLocation(reference, i)));
    }
  }

  void readConstraints() {
    int numberOfClusters = reader.readUInt();
    for (int i = 0; i < numberOfClusters; ++i) {
      var owner = reader.readCanonicalName().getReference();
      constraintSystem.clusters[owner] =
          new ConstraintCluster(owner, readConstraintList(owner));
    }
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

  Constraint readConstraint() {
    int byte = reader.readByte();
    switch (byte) {
      case ConstraintTag.EscapeConstraint:
        return new EscapeConstraint(readLocationReference());

      case ConstraintTag.SubtypeConstraint:
        return new SubtypeConstraint(readLocationReference(),
            readLocationReference(), reader.readFixedUInt32());

      case ConstraintTag.TypeArgumentConstraint:
        return new TypeArgumentConstraint(
            readLocationReference(), readLocationReference(), readValue());

      case ConstraintTag.ValueConstraint:
        return new ValueConstraint(readLocationReference(), readValue());
    }
    throw 'Unexpected constraint tag: $byte';
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
    return binding.getStorageLocation(owner, index);
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
