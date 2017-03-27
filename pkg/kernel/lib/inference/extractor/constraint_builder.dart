// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.constraint_builder;

import '../../ast.dart';
import '../../inference/extractor/value_sink.dart';
import '../../inference/extractor/value_source.dart';
import '../../inference/storage_location.dart';
import '../../inference/value.dart';
import '../constraints.dart';
import 'augmented_type.dart';
import 'hierarchy.dart';

class ConstraintBuilder {
  final ConstraintSystem constraintSystem;
  final AugmentedHierarchy hierarchy;

  NamedNode currentOwner;
  int currentFileOffset = -1;

  ConstraintBuilder(this.hierarchy, this.constraintSystem);

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

  void addAssignment(ValueSource source, ValueSink sink, int mask) {
    sink.acceptSink(new AssignmentToValueSink(this, source, mask));
  }

  void addAssignmentToKey(ValueSource source, StorageLocation sink, int mask) {
    source.acceptSource(new AssignmentFromValueSource(this, sink, mask));
  }

  void addEscape(ValueSource source, {StorageLocation guard}) {
    source.acceptSource(new EscapeVisitor(this, guard));
  }
}

class AssignmentToValueSink extends ValueSinkVisitor {
  final ConstraintBuilder builder;
  final ValueSource source;
  final int mask;

  AssignmentToValueSink(this.builder, this.source, this.mask);

  @override
  visitEscapingSink(EscapingSink sink) {
    builder.addEscape(source);
  }

  @override
  visitStorageLocation(StorageLocation key) {
    builder.addAssignmentToKey(source, key, mask);
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

  AssignmentFromValueSource(this.builder, this.sink, this.mask);

  AssignmentFromValueSource get nullabilityVisitor {
    if (mask & ~ValueFlags.null_ == 0) return this;
    return new AssignmentFromValueSource(builder, sink, ValueFlags.null_);
  }

  @override
  visitStorageLocation(StorageLocation key) {
    builder.addConstraint(new AssignConstraint(key, sink, mask));
  }

  @override
  visitValue(Value value) {
    if (value.flags & mask == 0) return;
    builder.addConstraint(new ValueConstraint(sink, value.masked(mask)));
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
