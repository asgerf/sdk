// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.value_source;

import '../key.dart';
import '../value.dart';

abstract class ValueSource {
  bool isBottom(int mask);

  Value get value;

  T acceptSource<T>(ValueSourceVisitor<T> visitor);
}

class ValueSourceWithNullability extends ValueSource {
  final ValueSource base, nullability;

  ValueSourceWithNullability(this.base, this.nullability);

  bool isBottom(int mask) => base.isBottom(mask) && nullability.isBottom(mask);

  Value get value {
    var baseValue = base.value;
    var nullabilityValue = nullability.value;
    if (baseValue.canBeNull || !nullabilityValue.canBeNull) return baseValue;
    return new Value(baseValue.baseClass, baseValue.flags | Flags.null_);
  }

  T acceptSource<T>(ValueSourceVisitor<T> visitor) {
    return visitor.visitValueSourceWithNullability(this);
  }
}

abstract class ValueSourceVisitor<T> {
  T visitKey(Key key);
  T visitValue(Value value);
  T visitValueSourceWithNullability(ValueSourceWithNullability source);
}
