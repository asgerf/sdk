library kernel.inference.report.binary_reader;

import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/binary_writer.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/util/reader.dart';

class BinaryReportReader {
  final Reader reader;
  int eventTimestamp = 0;
  List<List<Constraint>> constraints;

  BinaryReportReader(this.reader);

  Constraint readConstraintReference() {
    int ownerIndex = reader.readUInt();
    int constraintIndex = reader.readUInt();
    return constraints[ownerIndex][constraintIndex];
  }

  List<Event> readEventList() {
    int numberOfEvents = reader.readUInt();
    var events = new List<Event>(numberOfEvents);
    for (int i = 0; i < numberOfEvents; ++i) {
      events[i] = readEvent();
    }
    return events;
  }

  StorageLocation readLocationReference() {}

  Event readEvent() {
    int tag = reader.readByte();
    if (tag == EventTag.OnBeginTransfer) {
      return new TransferEvent(readConstraintReference(), eventTimestamp++);
    } else {
      return new ChangeEvent(
          readLocationReference(), readValue(), readBoolean(), eventTimestamp);
    }
  }
}
