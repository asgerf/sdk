// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.source_sink_translator;

import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';

import '../constraints.dart';
import '../storage_location.dart';
import '../value.dart';
import 'augmented_hierarchy.dart';
import 'augmented_type.dart';
import 'common_values.dart';
import 'constraint_builder.dart';
import 'value_sink.dart';
import 'value_source.dart';

/// Generates constraints from [ValueSource]/[ValueSink] assignments.
///
/// The underlying constraint system does not understand sources and sinks,
/// it only deals with storage locations and values.
///
/// The translator handles any combination of source and sink by means of
/// a double dispatch.  It first dispatches over the sink, and if necessary,
/// then dispatches over the source with some contextual information obtained
/// from the sink.
class SourceSinkTranslator extends ConstraintBuilder {
  final AugmentedHierarchy hierarchy;
  final ValueLattice lattice;
  final CommonValues common;

  CoreTypes get coreTypes => lattice.coreTypes;

  SourceSinkTranslator(ConstraintSystem constraintSystem, this.hierarchy,
      this.lattice, this.common)
      : super(constraintSystem);

  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return hierarchy.getTypeAsInstanceOf(subtype, superclass);
  }

  void addAssignment(ValueSource source, ValueSink sink, [TypeFilter filter]) {
    sink.acceptSink(new _AssignmentSinkVisitor(
        this, source, filter?.mask ?? ValueFlags.all, filter?.interfaceClass));
  }

  /// Mark values coming from [source] as escaping.
  ///
  /// The the [guard] is given, only take effect if the [guard] contains a
  /// value with one of the flags defined by [guardMask].
  void addEscape(ValueSource source, {ValueSource guard, int guardMask: -1}) {
    if (guard != null) {
      assert(guardMask != -1);
      guard.acceptSource(new _EscapeGuardVisitor(this, source, guardMask));
    } else {
      source.acceptSource(new _EscapeSourceVisitor(this));
    }
  }

  /// Mark values coming from [source] as escaping if values flowing into
  /// [destination] can escape.
  void addEscapingAssignment(ValueSource source, ValueSink destination) {
    destination.acceptSink(new _EscapingAssignSinkVisitor(this, source));
  }

  /// Ensure that anything flowing out of [from] also flows out out of [to].
  ///
  /// This operation only supports value sources of [to] that have an underlying
  /// storage location to which the values of [from] can be assigned.
  ///
  /// This limitation exists because our type hierarchy does not express the
  /// invariant that type bounds in some contexts are known to carry a storage
  /// location as their upper bound.
  void addSourceToSourceAssignment(ValueSource from, ValueSource to,
      [TypeFilter filter]) {
    to.acceptSource(new _SourceToSourceVisitor(this, from, filter));
  }

  /// Ensure that anything that flows into [from] will also flow into [to].
  ///
  /// This operation only supports value sinks of [from] that have an underlying
  /// storage location from which the values can be obtained.
  ///
  /// This limitation exists because our type hierarchy does not express the
  /// invariant that type bounds in some contexts are known to carry a storage
  /// location as their lower bound.
  void addSinkToSinkAssignment(ValueSink from, ValueSink to,
      [TypeFilter filter]) {
    from.acceptSink(new _SinkToSinkVisitor(this, to, filter));
  }

  /// If the value in [guard] has one of the flags in [guardMask], then let
  /// [value] flow into [destination].
  void addGuardedValueAssignment(
      Value value, ValueSink destination, ValueSource guard, int guardMask) {
    destination.acceptSink(
        new _GuardedValueSinkVisitor(this, value, guard, guardMask));
  }
}

class _AssignmentSinkVisitor extends ValueSinkVisitor {
  final SourceSinkTranslator translator;
  final ValueSource source;
  final int mask;
  final Class interfaceClass;

  _AssignmentSinkVisitor(
      this.translator, this.source, this.mask, this.interfaceClass);

  @override
  visitEscapingSink(EscapingSink sink) {
    translator.addEscape(source);
  }

  @override
  visitStorageLocation(StorageLocation sink) {
    source.acceptSource(
        new _AssignmentSourceVisitor(translator, sink, mask, interfaceClass));
  }

  @override
  visitNowhereSink(NowhereSink sink) {}

  @override
  visitUnassignableSink(UnassignableSink sink) {
    throw new UnassignableSinkError(sink);
  }

  @override
  visitValueSinkWithEscape(ValueSinkWithEscape sink) {
    sink.base.acceptSink(this);
    sink.escaping
        .acceptSink(new _EscapingAssignSinkVisitor(translator, source));
  }
}

class _AssignmentSourceVisitor extends ValueSourceVisitor {
  final SourceSinkTranslator translator;
  final StorageLocation sink;
  final int mask;
  final Class interfaceClass;

  CommonValues get common => translator.common;
  CoreTypes get coreTypes => translator.coreTypes;

  _AssignmentSourceVisitor(
      this.translator, this.sink, this.mask, this.interfaceClass);

  _AssignmentSourceVisitor get nullabilityVisitor {
    if (mask & ~ValueFlags.null_ == 0) return this;
    return new _AssignmentSourceVisitor(
        translator, sink, ValueFlags.null_, null);
  }

  @override
  visitStorageLocation(StorageLocation source) {
    if (interfaceClass != null && interfaceClass != coreTypes.objectClass) {
      // Type filters do not work well for 'int' and 'num' because the class
      // _GrowableArrayMarker implements 'int', so use a value filter constraint
      // for those two cases.
      // For the other built-in types we also use value filters, but this is
      // for performance and ensuring that the escape bit is set correctly.
      Value valueFilter;
      if (interfaceClass == coreTypes.intClass) {
        valueFilter = common.nullableIntValue;
      } else if (interfaceClass == coreTypes.numClass) {
        valueFilter = common.nullableNumValue;
      } else if (interfaceClass == coreTypes.doubleClass) {
        valueFilter = common.nullableDoubleValue;
      } else if (interfaceClass == coreTypes.stringClass) {
        valueFilter = common.nullableStringValue;
      } else if (interfaceClass == coreTypes.boolClass) {
        valueFilter = common.nullableBoolValue;
      } else if (interfaceClass == coreTypes.functionClass) {
        valueFilter = common.nullableEscapingFunctionValue;
      }
      if (valueFilter != null) {
        translator.addConstraint(
            new ValueFilterConstraint(source, sink, valueFilter));
      } else {
        translator.addConstraint(
            new TypeFilterConstraint(source, sink, interfaceClass, mask));
      }
    } else {
      translator.addConstraint(new AssignConstraint(source, sink, mask));
    }
  }

  @override
  visitValue(Value value) {
    if (value.flags & mask == 0) return;
    if (interfaceClass != null) {
      value = translator.lattice
          .restrictValueToInterface(value, interfaceClass, mask);
    } else {
      value = value.masked(mask);
    }
    translator.addConstraint(new ValueConstraint(sink, value));
  }

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.nullability.acceptSource(nullabilityVisitor);
    source.base.acceptSource(this);
  }
}

class _EscapingAssignSinkVisitor extends ValueSinkVisitor {
  final SourceSinkTranslator translator;
  final ValueSource source;

  _EscapingAssignSinkVisitor(this.translator, this.source);

  @override
  visitEscapingSink(EscapingSink sink) {
    source.acceptSource(new _EscapeSourceVisitor(translator));
  }

  @override
  visitNowhereSink(NowhereSink sink) {}

  @override
  visitStorageLocation(StorageLocation sink) {
    source.acceptSource(new _EscapingAssignSourceVisitor(translator, sink));
  }

  @override
  visitUnassignableSink(UnassignableSink sink) {}

  @override
  visitValueSinkWithEscape(ValueSinkWithEscape sink) {
    sink.base.acceptSink(this);
    sink.escaping.acceptSink(this);
  }
}

class _EscapingAssignSourceVisitor extends ValueSourceVisitor {
  final SourceSinkTranslator translator;
  final StorageLocation destination;

  _EscapingAssignSourceVisitor(this.translator, this.destination);

  @override
  visitStorageLocation(StorageLocation source) {
    translator.addConstraint(new EscapingAssignConstraint(source, destination));
  }

  @override
  visitValue(Value value) {}

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.base.acceptSource(this);
  }
}

class _EscapeGuardVisitor extends ValueSourceVisitor {
  final SourceSinkTranslator translator;
  final ValueSource source;
  final int guardMask;

  _EscapeGuardVisitor(this.translator, this.source, this.guardMask);

  @override
  visitStorageLocation(StorageLocation guard) {
    source.acceptSource(new _EscapeSourceVisitor(translator, guard, guardMask));
  }

  @override
  visitValue(Value value) {
    if (value.flags & guardMask != 0) {
      source.acceptSource(new _EscapeSourceVisitor(translator));
    }
  }

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.base.acceptSource(this);
    if (guardMask & ValueFlags.null_ != 0) {
      source.nullability.acceptSource(
          new _EscapeGuardVisitor(translator, source, ValueFlags.null_));
    }
  }
}

class _EscapeSourceVisitor extends ValueSourceVisitor {
  final SourceSinkTranslator translator;
  final StorageLocation guard;
  final int guardMask;

  _EscapeSourceVisitor(this.translator, [this.guard, this.guardMask = 0]);

  @override
  visitStorageLocation(StorageLocation source) {
    translator.addConstraint(new EscapeConstraint(source, guard, guardMask));
  }

  @override
  visitValue(Value value) {}

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.base.acceptSource(this);
  }
}

class _SourceToSourceVisitor extends ValueSourceVisitor {
  final SourceSinkTranslator translator;
  final ValueSource from;
  final TypeFilter filter;

  _SourceToSourceVisitor(this.translator, this.from, this.filter);

  @override
  visitStorageLocation(StorageLocation location) {
    translator.addAssignment(from, location, filter);
  }

  @override
  visitValue(Value to) {}

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability to) {
    to.base.acceptSource(this);
  }
}

class _SinkToSinkVisitor extends ValueSinkVisitor {
  final SourceSinkTranslator translator;
  final ValueSink to;
  final TypeFilter filter;

  _SinkToSinkVisitor(this.translator, this.to, this.filter);

  @override
  visitEscapingSink(EscapingSink sink) {}

  @override
  visitNowhereSink(NowhereSink sink) {}

  @override
  visitStorageLocation(StorageLocation location) {
    translator.addAssignment(location, to, filter);
  }

  @override
  visitUnassignableSink(UnassignableSink sink) {}

  @override
  visitValueSinkWithEscape(ValueSinkWithEscape sink) {
    sink.base.acceptSink(this);
  }
}

class _GuardedValueSinkVisitor extends ValueSinkVisitor {
  final SourceSinkTranslator translator;
  final Value value;
  final ValueSource guard;
  final int guardMask;

  _GuardedValueSinkVisitor(
      this.translator, this.value, this.guard, this.guardMask);

  @override
  visitEscapingSink(EscapingSink sink) {
    // We cannot cause [value] to escape.
  }

  @override
  visitNowhereSink(NowhereSink sink) {}

  @override
  visitStorageLocation(StorageLocation sink) {
    guard.acceptSource(
        new _GuardedValueSourceVisitor(translator, value, sink, guardMask));
  }

  @override
  visitUnassignableSink(UnassignableSink sink) {
    throw new UnassignableSinkError(sink);
  }

  @override
  visitValueSinkWithEscape(ValueSinkWithEscape sink) {
    sink.base.acceptSink(this);
  }
}

class _GuardedValueSourceVisitor extends ValueSourceVisitor {
  final SourceSinkTranslator translator;
  final Value value;
  final StorageLocation destination;
  final int guardMask;

  _GuardedValueSourceVisitor(
      this.translator, this.value, this.destination, this.guardMask);

  @override
  visitStorageLocation(StorageLocation guard) {
    // The [guard] location represents a type parameter T, and thus only
    // contains the nullability modifier on T.  In addition to its nullability
    // modifier, we need information from all possible calling contexts, so we
    // must take the value from its upper bound.
    while (guard.parameterLocation != null) {
      var parameter = guard.parameterLocation;
      if (guardMask & ValueFlags.null_ != 0) {
        translator.addConstraint(new GuardedValueConstraint(
            destination, value, guard, ValueFlags.null_));
      }
      guard = translator.constraintSystem.getBoundLocation(parameter);
    }
    translator.addConstraint(
        new GuardedValueConstraint(destination, value, guard, guardMask));
  }

  @override
  visitValue(Value value) {
    if (value.flags & guardMask != 0) {
      translator.addConstraint(new ValueConstraint(destination, value));
    }
  }

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.base.acceptSource(this);
    if (guardMask & ValueFlags.null_ != 0) {
      source.nullability.acceptSource(new _GuardedValueSourceVisitor(
          translator, value, destination, ValueFlags.null_));
    }
  }
}

class TypeFilter {
  final Class interfaceClass;
  final int valueSets;

  const TypeFilter(this.interfaceClass, this.valueSets);

  int get mask => valueSets | ValueFlags.nonValueSetFlags;

  static final TypeFilter none = new TypeFilter(null, ValueFlags.allValueSets);
  static final TypeFilter null_ = new TypeFilter(null, ValueFlags.null_);
  static final TypeFilter notNull =
      new TypeFilter(null, ValueFlags.nonNullValueSets);
}
