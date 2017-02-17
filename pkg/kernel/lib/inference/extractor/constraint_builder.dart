library kernel.inference.constraint_builder;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/extractor/value_sink.dart';
import 'package:kernel/inference/extractor/value_source.dart';
import 'package:kernel/inference/key.dart';
import 'package:kernel/inference/value.dart';

import '../constraints.dart';
import 'augmented_type.dart';
import 'hierarchy.dart';

class ConstraintBuilder {
  final List<Constraint> constraints = <Constraint>[];
  final AugmentedHierarchy hierarchy;
  TreeNode currentOwner;

  ConstraintBuilder(this.hierarchy);

  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return hierarchy.getTypeAsInstanceOf(subtype, superclass);
  }

  void addConstraint(Constraint constraint) {
    constraints.add(constraint..owner = currentOwner);
  }

  void addAssignment(ValueSource source, ValueSink sink, int mask) {
    sink.acceptSink(new AssignmentToValueSink(this, source, mask));
  }

  void addAssignmentToKey(ValueSource source, Key sink, int mask) {
    source.acceptSource(new AssignmentFromValueSource(this, sink, mask));
  }

  void addEscape(ValueSource source) {
    source.acceptSource(new EscapeVisitor(this));
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
  visitKey(Key key) {
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
  final Key sink;
  final int mask;

  AssignmentFromValueSource(this.builder, this.sink, this.mask);

  AssignmentFromValueSource get nullabilityVisitor {
    if (mask & ~Flags.null_ == 0) return this;
    return new AssignmentFromValueSource(builder, sink, Flags.null_);
  }

  @override
  visitKey(Key key) {
    builder.addConstraint(new SubtypeConstraint(key, sink, mask));
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

  EscapeVisitor(this.builder);

  @override
  visitKey(Key key) {
    builder.addConstraint(new EscapeConstraint(key));
  }

  @override
  visitValue(Value value) {}

  @override
  visitValueSourceWithNullability(ValueSourceWithNullability source) {
    source.base.acceptSource(this);
  }
}
