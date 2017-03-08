// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.report.writer;

import '../../ast.dart';
import '../../inference/constraints.dart';
import '../../inference/report/report.dart';
import '../../inference/storage_location.dart';
import '../../inference/value.dart';
import 'package:kernel/inference/solver/solver.dart';

class ReportWriter {
  ConstraintJsonConverter _constraintVisitor;

  final Map<CanonicalName, int> canonicalNameIndex = <CanonicalName, int>{};
  final List<CanonicalName> canonicalNames = <CanonicalName>[];

  ReportWriter() {
    _constraintVisitor = new ConstraintJsonConverter(this);
  }

  Object buildCanonicalNameTable() {
    return canonicalNames.map(convertCanonicalName).toList();
  }

  Object convertCanonicalName(CanonicalName name) {
    return {
      'parent': name.isRoot ? null : canonicalNameIndex[name.parent],
      'name': name.name,
    };
  }

  int getCanonicalNameId(CanonicalName name) {
    int index = canonicalNameIndex[name];
    if (index != null) return index;
    getCanonicalNameId(name.parent);
    index = canonicalNameIndex[name] = canonicalNames.length;
    canonicalNames.add(name);
    return index;
  }

  int getReferenceId(Reference node) {
    return getCanonicalNameId(node.canonicalName);
  }

  int getOptionalReferenceId(Reference node) {
    return node == null ? null : getReferenceId(node);
  }

  String getConstraintId(Constraint constraint) {
    int owner = getReferenceId(constraint.owner);
    return '$owner,constraints,${constraint.index}';
  }

  String getLocationId(StorageLocation location) {
    int owner = getReferenceId(location.owner.reference);
    return '$owner,locations,${location.index}';
  }

  Object convertReport(Report report) {
    return {
      'kind': 'Report',
      'events': report.allEvents.map(convertEvent).toList(),
    };
  }

  Object convertEvent(Event event) {
    if (event is ChangeEvent) {
      return convertChangeEvent(event);
    } else {
      return convertTransferEvent(event);
    }
  }

  Object convertChangeEvent(ChangeEvent event) {
    return {
      'kind': 'change',
      'location': getLocationId(event.location),
      'value': convertValue(event.value),
      'leadsToEscape': event.leadsToEscape
    };
  }

  Object convertTransferEvent(TransferEvent event) {
    return {
      'kind': 'transfer',
      'constraint': getConstraintId(event.constraint),
    };
  }

  Object convertValue(Value value) {
    return {
      'kind': 'Value',
      'baseClass': getOptionalReferenceId(value.baseClass?.reference),
      'flags': value.flags,
    };
  }

  Object convertConstraint(Constraint constraint) {
    return constraint.accept(_constraintVisitor);
  }

  Object buildJsonReport(
      Program program, ConstraintSolver solver, Report report) {
    canonicalNames.add(program.root);
    canonicalNameIndex[program.root] = 0;
    var json = {
      'constraints': solver.constraints.map(convertConstraint).toList(),
      'report': convertReport(report),
    };
    json['canonicalNames'] = buildCanonicalNameTable();
    return json;
  }
}

class ConstraintJsonConverter extends ConstraintVisitor<Object> {
  final ReportWriter writer;

  ConstraintJsonConverter(this.writer);

  @override
  Object visitEscapeConstraint(EscapeConstraint constraint) {
    return {
      'kind': 'escape',
      'escaping': writer.getLocationId(constraint.escaping),
    };
  }

  @override
  Object visitSubtypeConstraint(SubtypeConstraint constraint) {
    return {
      'kind': 'subtype',
      'source': writer.getLocationId(constraint.source),
      'destination': writer.getLocationId(constraint.destination),
      'mask': constraint.mask,
    };
  }

  @override
  Object visitTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    return {
      'kind': 'typeArg',
      'createdObject': writer.getLocationId(constraint.createdObject),
      'typeArgument': writer.getLocationId(constraint.typeArgument),
    };
  }

  @override
  Object visitValueConstraint(ValueConstraint constraint) {
    return {
      'kind': 'value',
      'destination': writer.getLocationId(constraint.destination),
      'value': writer.convertValue(constraint.value),
      'canEscape': constraint.canEscape,
    };
  }
}
