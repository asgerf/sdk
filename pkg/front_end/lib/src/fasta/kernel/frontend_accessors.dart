// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Note: copied from package:kernel at revision 7346348.

/// A library to help transform compounds and null-aware accessors into
/// let expressions.
library kernel.frontend.accessors;

import 'package:kernel/ast.dart';

/// An [Accessor] represents a subexpression for which we can't yet build a
/// kernel [Expression] because we don't yet know the context in which it is
/// used.
///
/// Once the context is known, an [Accessor] can be converted into an
/// [Expression] by calling a "build" method.
///
/// For example, when building a kernel representation for `a[x] = b`, after
/// parsing `a[x]` but before parsing `= b`, we don't yet know whether to
/// generate an invocation of `operator[]` or `operator[]=`, so we generate an
/// [Accessor] object.  Later, after `= b` is parsed, [buildAssignment] will be
/// called.
abstract class Accessor {
  /// Builds an [Expression] representing a read from the accessor.
  Expression buildSimpleRead() {
    return _finish(_makeSimpleRead());
  }

  /// Builds an [Expression] representing an assignment with the accessor on
  /// the LHS and [value] on the RHS.
  ///
  /// The returned expression evaluates to the assigned value, unless
  /// [voidContext] is true, in which case it may evaluate to anything.
  Expression buildAssignment(Expression value, {bool voidContext: false}) {
    return _finish(_makeSimpleWrite(value, voidContext));
  }

  /// Returns an [Expression] representing a null-aware assignment (`??=`) with
  /// the accessor on the LHS and [value] on the RHS.
  ///
  /// The returned expression evaluates to the assigned value, unless
  /// [voidContext] is true, in which case it may evaluate to anything.
  ///
  /// [type] is the static type of the RHS.
  Expression buildNullAwareAssignment(Expression value, DartType type,
      {bool voidContext: false}) {
    if (voidContext) {
      return _finish(new ConditionalExpression(buildIsNull(_makeRead()),
          _makeWrite(value, false), new NullLiteral(), type));
    }
    var tmp = new VariableDeclaration.forValue(_makeRead());
    return _finish(makeLet(
        tmp,
        new ConditionalExpression(buildIsNull(new VariableGet(tmp)),
            _makeWrite(value, false), new VariableGet(tmp), type)));
  }

  /// Returns an [Expression] representing a compound assignment (e.g. `+=`)
  /// with the accessor on the LHS and [value] on the RHS.
  Expression buildCompoundAssignment(
      Name binaryOperator, Expression value, int charOffset,
      {bool voidContext: false, Procedure interfaceTarget}) {
    return _finish(_makeWrite(
        makeBinary(
            _makeRead(), binaryOperator, interfaceTarget, value, charOffset),
        voidContext));
  }

  /// Returns an [Expression] representing a pre-increment or pre-decrement
  /// of the accessor.
  Expression buildPrefixIncrement(Name binaryOperator, int charOffset,
      {bool voidContext: false, Procedure interfaceTarget}) {
    return buildCompoundAssignment(
        binaryOperator, new IntLiteral(1), charOffset,
        voidContext: voidContext, interfaceTarget: interfaceTarget);
  }

  /// Returns an [Expression] representing a post-increment or post-decrement
  /// of the accessor.
  Expression buildPostfixIncrement(Name binaryOperator, int charOffset,
      {bool voidContext: false, Procedure interfaceTarget}) {
    if (voidContext) {
      return buildPrefixIncrement(binaryOperator, charOffset,
          voidContext: true, interfaceTarget: interfaceTarget);
    }
    var value = new VariableDeclaration.forValue(_makeRead());
    valueAccess() => new VariableGet(value);
    var dummy = new VariableDeclaration.forValue(_makeWrite(
        makeBinary(valueAccess(), binaryOperator, interfaceTarget,
            new IntLiteral(1), charOffset),
        true));
    return _finish(makeLet(value, makeLet(dummy, valueAccess())));
  }

  Expression _makeSimpleRead() => _makeRead();

  Expression _makeSimpleWrite(Expression value, bool voidContext) {
    return _makeWrite(value, voidContext);
  }

  Expression _makeRead();

  Expression _makeWrite(Expression value, bool voidContext);

  Expression _finish(Expression body) => body;

  /// Returns an [Expression] representing a compile-time error.
  ///
  /// At runtime, an exception will be thrown.
  makeInvalidRead() => new InvalidExpression();

  /// Returns an [Expression] representing a compile-time error wrapping
  /// [value].
  ///
  /// At runtime, [value] will be evaluated before throwing an exception.
  makeInvalidWrite(Expression value) => wrapInvalid(value);
}

class VariableAccessor extends Accessor {
  VariableDeclaration variable;
  int charOffset;
  DartType promotedType;

  VariableAccessor(this.variable, [this.promotedType]);

  VariableAccessor.internal(this.variable, this.charOffset, this.promotedType);

  _makeRead() =>
      new VariableGet(variable, promotedType)..fileOffset = charOffset;

  _makeWrite(Expression value, bool voidContext) {
    return variable.isFinal || variable.isConst
        ? makeInvalidWrite(value)
        : new VariableSet(variable, value)..fileOffset = charOffset;
  }
}

class PropertyAccessor extends Accessor {
  VariableDeclaration _receiverVariable;
  Expression receiver;
  Name name;
  Member getter, setter;
  int charOffset;

  static Accessor make(Expression receiver, Name name, Member getter,
      Member setter, int charOffset) {
    if (receiver is ThisExpression) {
      return new ThisPropertyAccessor(name, getter, setter);
    } else {
      return new PropertyAccessor.internal(
          receiver, name, getter, setter, charOffset);
    }
  }

  PropertyAccessor.internal(
      this.receiver, this.name, this.getter, this.setter, this.charOffset);

  _makeSimpleRead() =>
      new PropertyGet(receiver, name, getter)..fileOffset = charOffset;
  _makeSimpleWrite(Expression value, bool voidContext) {
    return new PropertySet(receiver, name, value, setter)
      ..fileOffset = charOffset;
  }

  receiverAccess() {
    _receiverVariable ??= new VariableDeclaration.forValue(receiver);
    return new VariableGet(_receiverVariable)..fileOffset = charOffset;
  }

  _makeRead() =>
      new PropertyGet(receiverAccess(), name, getter)..fileOffset = charOffset;

  _makeWrite(Expression value, bool voidContext) {
    return new PropertySet(receiverAccess(), name, value, setter)
      ..fileOffset = charOffset;
  }

  _finish(Expression body) => makeLet(_receiverVariable, body);
}

/// Special case of [PropertyAccessor] to avoid creating an indirect access to
/// 'this'.
class ThisPropertyAccessor extends Accessor {
  Name name;
  Member getter, setter;

  ThisPropertyAccessor(this.name, this.getter, this.setter);

  _makeRead() => new PropertyGet(new ThisExpression(), name, getter);

  _makeWrite(Expression value, bool voidContext) {
    return new PropertySet(new ThisExpression(), name, value, setter);
  }
}

class NullAwarePropertyAccessor extends Accessor {
  VariableDeclaration receiver;
  Name name;
  Member getter, setter;
  DartType type;

  NullAwarePropertyAccessor(
      Expression receiver, this.name, this.getter, this.setter, this.type)
      : this.receiver = makeOrReuseVariable(receiver);

  receiverAccess() => new VariableGet(receiver);

  _makeRead() => new PropertyGet(receiverAccess(), name, getter);

  _makeWrite(Expression value, bool voidContext) {
    return new PropertySet(receiverAccess(), name, value, setter);
  }

  _finish(Expression body) => makeLet(
      receiver,
      new ConditionalExpression(
          buildIsNull(receiverAccess()), new NullLiteral(), body, type));
}

class SuperPropertyAccessor extends Accessor {
  Name name;
  Member getter, setter;

  SuperPropertyAccessor(this.name, this.getter, this.setter);

  _makeRead() {
    if (getter == null) return makeInvalidRead();
    // TODO(ahe): Use [DirectPropertyGet] when possible.
    Expression result = new DirectPropertyGet(new ThisExpression(), getter);
    result = new SuperPropertyGet(name, getter);
    return result;
  }

  _makeWrite(Expression value, bool voidContext) {
    if (setter == null) return makeInvalidWrite(value);
    // TODO(ahe): Use [DirectPropertySet] when possible.
    Expression result =
        new DirectPropertySet(new ThisExpression(), setter, value);
    result = new SuperPropertySet(name, value, setter);
    return result;
  }
}

final Name _indexGet = new Name('[]');
final Name _indexSet = new Name('[]=');

class IndexAccessor extends Accessor {
  Expression receiver;
  Expression index;
  VariableDeclaration receiverVariable;
  VariableDeclaration indexVariable;
  Procedure getter, setter;
  int charOffset;

  static Accessor make(Expression receiver, Expression index, Procedure getter,
      Procedure setter, int charOffset) {
    if (receiver is ThisExpression) {
      return new ThisIndexAccessor(index, getter, setter);
    } else {
      return new IndexAccessor.internal(
          receiver, index, getter, setter, charOffset);
    }
  }

  IndexAccessor.internal(
      this.receiver, this.index, this.getter, this.setter, this.charOffset);

  _makeSimpleRead() => new MethodInvocation(
      receiver, _indexGet, new Arguments(<Expression>[index]), getter)
    ..fileOffset = charOffset;

  _makeSimpleWrite(Expression value, bool voidContext) {
    if (!voidContext) return _makeWriteAndReturn(value);
    return new MethodInvocation(
        receiver, _indexSet, new Arguments(<Expression>[index, value]), setter)
      ..fileOffset = charOffset;
  }

  receiverAccess() {
    // We cannot reuse the receiver if it is a variable since it might be
    // reassigned in the index expression.
    receiverVariable ??= new VariableDeclaration.forValue(receiver);
    return new VariableGet(receiverVariable)..fileOffset = charOffset;
  }

  indexAccess() {
    indexVariable ??= new VariableDeclaration.forValue(index);
    return new VariableGet(indexVariable)..fileOffset = charOffset;
  }

  _makeRead() {
    return new MethodInvocation(
        receiverAccess(),
        _indexGet,
        new Arguments(<Expression>[indexAccess()]),
        getter)..fileOffset = charOffset;
  }

  _makeWrite(Expression value, bool voidContext) {
    if (!voidContext) return _makeWriteAndReturn(value);
    return new MethodInvocation(
        receiverAccess(),
        _indexSet,
        new Arguments(<Expression>[indexAccess(), value]),
        setter)..fileOffset = charOffset;
  }

  _makeWriteAndReturn(Expression value) {
    // The call to []= does not return the value like direct-style assignments
    // do.  We need to bind the value in a let.
    var valueVariable = new VariableDeclaration.forValue(value);
    var dummy = new VariableDeclaration.forValue(new MethodInvocation(
        receiverAccess(),
        _indexSet,
        new Arguments(
            <Expression>[indexAccess(), new VariableGet(valueVariable)]),
        setter)..fileOffset = charOffset);
    return makeLet(
        valueVariable, makeLet(dummy, new VariableGet(valueVariable)));
  }

  Expression _finish(Expression body) {
    return makeLet(receiverVariable, makeLet(indexVariable, body));
  }
}

/// Special case of [IndexAccessor] to avoid creating an indirect access to
/// 'this'.
class ThisIndexAccessor extends Accessor {
  Expression index;
  VariableDeclaration indexVariable;
  Procedure getter, setter;

  ThisIndexAccessor(this.index, this.getter, this.setter);

  _makeSimpleRead() {
    return new MethodInvocation(new ThisExpression(), _indexGet,
        new Arguments(<Expression>[index]), getter);
  }

  _makeSimpleWrite(Expression value, bool voidContext) {
    if (!voidContext) return _makeWriteAndReturn(value);
    return new MethodInvocation(new ThisExpression(), _indexSet,
        new Arguments(<Expression>[index, value]), setter);
  }

  indexAccess() {
    indexVariable ??= new VariableDeclaration.forValue(index);
    return new VariableGet(indexVariable);
  }

  _makeRead() => new MethodInvocation(new ThisExpression(), _indexGet,
      new Arguments(<Expression>[indexAccess()]), getter);

  _makeWrite(Expression value, bool voidContext) {
    if (!voidContext) return _makeWriteAndReturn(value);
    return new MethodInvocation(new ThisExpression(), _indexSet,
        new Arguments(<Expression>[indexAccess(), value]), setter);
  }

  _makeWriteAndReturn(Expression value) {
    var valueVariable = new VariableDeclaration.forValue(value);
    var dummy = new VariableDeclaration.forValue(new MethodInvocation(
        new ThisExpression(),
        _indexSet,
        new Arguments(
            <Expression>[indexAccess(), new VariableGet(valueVariable)]),
        setter));
    return makeLet(
        valueVariable, makeLet(dummy, new VariableGet(valueVariable)));
  }

  Expression _finish(Expression body) => makeLet(indexVariable, body);
}

class SuperIndexAccessor extends Accessor {
  Expression index;
  VariableDeclaration indexVariable;
  Member getter, setter;

  SuperIndexAccessor(this.index, this.getter, this.setter);

  indexAccess() {
    indexVariable ??= new VariableDeclaration.forValue(index);
    return new VariableGet(indexVariable);
  }

  _makeSimpleRead() => new SuperMethodInvocation(
      _indexGet, new Arguments(<Expression>[index]), getter);

  _makeSimpleWrite(Expression value, bool voidContext) {
    if (!voidContext) return _makeWriteAndReturn(value);
    return new SuperMethodInvocation(
        _indexSet, new Arguments(<Expression>[index, value]), setter);
  }

  _makeRead() {
    return new SuperMethodInvocation(
        _indexGet, new Arguments(<Expression>[indexAccess()]), getter);
  }

  _makeWrite(Expression value, bool voidContext) {
    if (!voidContext) return _makeWriteAndReturn(value);
    return new SuperMethodInvocation(
        _indexSet, new Arguments(<Expression>[indexAccess(), value]), setter);
  }

  _makeWriteAndReturn(Expression value) {
    var valueVariable = new VariableDeclaration.forValue(value);
    var dummy = new VariableDeclaration.forValue(new SuperMethodInvocation(
        _indexSet,
        new Arguments(
            <Expression>[indexAccess(), new VariableGet(valueVariable)]),
        setter));
    return makeLet(
        valueVariable, makeLet(dummy, new VariableGet(valueVariable)));
  }

  Expression _finish(Expression body) {
    return makeLet(indexVariable, body);
  }
}

class StaticAccessor extends Accessor {
  Member readTarget;
  Member writeTarget;

  StaticAccessor(this.readTarget, this.writeTarget);

  _makeRead() =>
      readTarget == null ? makeInvalidRead() : new StaticGet(readTarget);

  _makeWrite(Expression value, bool voidContext) {
    return writeTarget == null
        ? makeInvalidWrite(value)
        : new StaticSet(writeTarget, value);
  }
}

class ReadOnlyAccessor extends Accessor {
  Expression expression;
  VariableDeclaration value;

  ReadOnlyAccessor(this.expression);

  _makeSimpleRead() => expression;

  _makeRead() {
    value ??= new VariableDeclaration.forValue(expression);
    return new VariableGet(value);
  }

  _makeWrite(Expression value, bool voidContext) => makeInvalidWrite(value);

  Expression _finish(Expression body) => makeLet(value, body);
}

Expression makeLet(VariableDeclaration variable, Expression body) {
  if (variable == null) return body;
  return new Let(variable, body);
}

Expression makeBinary(Expression left, Name operator, Procedure interfaceTarget,
    Expression right, int charOffset) {
  return new MethodInvocation(
      left, operator, new Arguments(<Expression>[right]), interfaceTarget)
    ..fileOffset = charOffset;
}

final Name _equalOperator = new Name('==');

Expression buildIsNull(Expression value) {
  return makeBinary(
      value, _equalOperator, null, new NullLiteral(), TreeNode.noOffset);
}

VariableDeclaration makeOrReuseVariable(Expression value) {
  // TODO: Devise a way to remember if a variable declaration was reused
  // or is fresh (hence needs a let binding).
  return new VariableDeclaration.forValue(value);
}

Expression wrapInvalid(Expression e) {
  return new Let(new VariableDeclaration.forValue(e), new InvalidExpression());
}
