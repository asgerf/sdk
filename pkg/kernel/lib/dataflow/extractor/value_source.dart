// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.value_source;

import '../storage_location.dart';
import '../value.dart';

/// Denotes a value that is either immediately known or must be determined by
/// the constraint solver.
///
/// This is used by constraint generation to work with types that represent a
/// source of values that are not just a [StorageLocation].
///
/// This can be a [Value] or [StorageLocation], wrapped in any number of
/// [ValueSourceWithNullability] objects.
abstract class ValueSource {
  bool isBottom(int mask);

  Value get value;

  T acceptSource<T>(ValueSourceVisitor<T> visitor);
}

/// Denotes the value of [base], with the additional `null` value if
/// [nullability] is nullable.
///
/// That is, this is nullable if either [base] or [nullability] is nullable.
///
/// To motivate why this is needed, consider this example (we use Greek letters
/// to denote storage locations):
///
///     class Foo<T> {
///       T_β value() { [body hidden]; }
///     }
///     void doSomething(Foo<String_α> foo) {
///       String_γ value = foo.value();
///     }
///
/// The call to `foo.value()` has a nullable return type in two cases:
///
///    - The type of foo is actually `Foo<String?>`, i.e `α` is nullable.
///    - The `Foo.value()` method actually returns `T?`, i.e. `β` is nullable.
///
/// We therefore build an intermediate return type for `foo.value()` that
/// references both storage locations, `String_αβ`.  This is represented by
/// [ValueSourceWithNullability], which `α` being the base and `β` being
/// the nullability.
///
class ValueSourceWithNullability extends ValueSource {
  final ValueSource base, nullability;

  ValueSourceWithNullability(this.base, this.nullability);

  bool isBottom(int mask) => base.isBottom(mask) && nullability.isBottom(mask);

  Value get value {
    var baseValue = base.value;
    var nullabilityValue = nullability.value;
    if (baseValue.canBeNull || !nullabilityValue.canBeNull) return baseValue;
    return new Value(baseValue.baseClass, baseValue.flags | ValueFlags.null_);
  }

  T acceptSource<T>(ValueSourceVisitor<T> visitor) {
    return visitor.visitValueSourceWithNullability(this);
  }
}

abstract class ValueSourceVisitor<T> {
  T visitStorageLocation(StorageLocation key);
  T visitValue(Value value);
  T visitValueSourceWithNullability(ValueSourceWithNullability source);
}
