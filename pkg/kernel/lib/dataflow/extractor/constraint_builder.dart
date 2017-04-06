// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.constraint_builder;

import '../../ast.dart';
import '../../dataflow/extractor/value_sink.dart';
import '../../dataflow/extractor/value_source.dart';
import '../../dataflow/storage_location.dart';
import '../../dataflow/value.dart';
import '../constraints.dart';
import 'augmented_type.dart';
import 'hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/extractor/common_values.dart';

class ConstraintBuilder {
  final ConstraintSystem constraintSystem;
  final AugmentedHierarchy hierarchy;
  final ValueLattice lattice;
  final CommonValues common;

  CoreTypes get coreTypes => lattice.coreTypes;

  NamedNode currentOwner;
  int currentFileOffset = -1;

  ConstraintBuilder(
      this.hierarchy, this.constraintSystem, this.lattice, this.common);

  void setOwner(NamedNode owner) {
    currentOwner = owner;
  }

  void setFileOffset(int fileOffset) {
    currentFileOffset = fileOffset;
  }

  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return hierarchy.getTypeAsInstanceOf(subtype, superclass);
  }

  void addConstraint(Constraint constraint) {
    constraintSystem.addConstraint(
        constraint, currentOwner.reference, currentFileOffset);
  }

  void addAssignmentWithFilter(
      ValueSource source, ValueSink sink, TypeFilter filter) {
    addAssignment(source, sink, filter.mask, filter.interfaceClass);
  }

  void addAssignment(ValueSource source, ValueSink sink, int mask,
      [Class interfaceClass]) {
    sink.acceptSink(
        new AssignmentToValueSink(this, source, mask, interfaceClass));
  }

  void addAssignmentToKey(ValueSource source, StorageLocation sink, int mask,
      [Class interfaceClass]) {
    source.acceptSource(
        new AssignmentFromValueSource(this, sink, mask, interfaceClass));
  }

  void addEscape(ValueSource source, {StorageLocation guard}) {
    source.acceptSource(new EscapeVisitor(this, guard));
  }
}

class AssignmentToValueSink extends ValueSinkVisitor {
  final ConstraintBuilder builder;
  final ValueSource source;
  final int mask;
  final Class interfaceClass;

  AssignmentToValueSink(
      this.builder, this.source, this.mask, this.interfaceClass);

  @override
  visitEscapingSink(EscapingSink sink) {
    builder.addEscape(source);
  }

  @override
  visitStorageLocation(StorageLocation key) {
    builder.addAssignmentToKey(source, key, mask, interfaceClass);
  }

  @override
  visitNowhereSink(NowhereSink sink) {}

  @override
  visitUnassignableSink(UnassignableSink sink) {
    throw new UnassignableSinkError(sink);
  }
}

class AssignmentFromValueSource extends ValueSourceVisitor {
  final ConstraintBuilder builder;
  final StorageLocation sink;
  final int mask;
  final Class interfaceClass;

  AssignmentFromValueSource(
      this.builder, this.sink, this.mask, this.interfaceClass);

  AssignmentFromValueSource get nullabilityVisitor {
    if (mask & ~ValueFlags.null_ == 0) return this;
    return new AssignmentFromValueSource(builder, sink, ValueFlags.null_, null);
  }

  @override
  visitStorageLocation(StorageLocation key) {
    if (interfaceClass != null) {
      // Type filters do not work well for 'int' and 'num' because the class
      // _GrowableArrayMarker implements 'int', so use an intersection
      // constraint for those two cases.
      if (interfaceClass == builder.coreTypes.intClass) {
        builder.addConstraint(new IntersectionConstraint(
            key, sink, builder.common.nullableIntValue));
      } else if (interfaceClass == builder.coreTypes.numClass) {
        builder.addConstraint(new IntersectionConstraint(
            key, sink, builder.common.nullableNumValue));
      } else {
        builder.addConstraint(
            new FilterConstraint(key, sink, interfaceClass, mask));
      }
    } else {
      builder.addConstraint(new AssignConstraint(key, sink, mask));
    }
  }

  @override
  visitValue(Value value) {
    if (value.flags & mask == 0) return;
    if (interfaceClass != null) {
      value =
          builder.lattice.restrictValueToInterface(value, interfaceClass, mask);
    } else {
      value = value.masked(mask);
    }
    builder.addConstraint(new ValueConstraint(sink, value));
  }

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.nullability.acceptSource(nullabilityVisitor);
    source.base.acceptSource(this);
  }
}

class EscapeVisitor extends ValueSourceVisitor {
  final ConstraintBuilder builder;
  final StorageLocation guard;

  EscapeVisitor(this.builder, this.guard);

  @override
  visitStorageLocation(StorageLocation key) {
    builder.addConstraint(new EscapeConstraint(key, guard: guard));
  }

  @override
  visitValue(Value value) {}

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.base.acceptSource(this);
  }
}
