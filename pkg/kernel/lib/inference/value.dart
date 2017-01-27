// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.value;

import '../ast.dart';
import 'constraint_builder.dart';
import 'constraints.dart';
import 'key.dart';

class Flags {
  static const int inexactBaseClass = 1 << 0;

  static const int null_ = 1 << 1;
  static const int integer = 1 << 2;
  static const int string = 1 << 3;
  static const int double_ = 1 << 4;
  static const int boolean = 1 << 5;
  static const int other = 1 << 6;

  static const int valueFlags =
      null_ | integer | string | double_ | boolean | other;
  static const int forward = inexactBaseClass | valueFlags;

  static const int escaping = 1 << 7;

  static const int backward = escaping;

  static const int numberOfFlags = 8;
  static const int all = (1 << numberOfFlags) - 1;
  static const int none = 0;

  static const int notNull = all & ~null_;
  static const int nonNullValue = valueFlags & ~null_;

  static const List<String> flagNames = const <String>[
    'inexactBaseClass',
    'Null', // Captialize to avoid confusion with null.toString().
    'integer',
    'string',
    'double',
    'boolean',
    'other',
    'escaping',
  ];

  static String flagsToString(int bitmask) {
    if (bitmask == all) return 'all';
    if (bitmask == none) return 'none';
    assert(flagNames.length == numberOfFlags);
    var names = <String>[];
    for (int i = 0; i < numberOfFlags; ++i) {
      if (bitmask & (1 << i) != 0) {
        names.add(flagNames[i]);
      }
    }
    return names.join(',');
  }
}

class Value implements ValueSource {
  Class baseClass;
  int flags;

  Value(this.baseClass, this.flags);

  Value get value => this;

  static final Value bottom = new Value(null, Flags.none);
  static final Value nullValue = new Value(null, Flags.null_);
  static final Value escaping = new Value(null, Flags.escaping);

  int get valueFlags => flags & Flags.valueFlags;
  bool get hasExactBaseClass => flags & Flags.inexactBaseClass == 0;
  bool get canBeNull => flags & Flags.null_ != 0;
  bool get canBeNonNull => flags & Flags.nonNullValue != 0;
  bool get isEscaping => flags & Flags.escaping != 0;

  Value masked(int mask) {
    int maskedFlags = flags & mask;
    if (maskedFlags == flags) return this;
    return new Value(baseClass, maskedFlags);
  }

  String toString() {
    if (baseClass == null) {
      if (flags == Flags.null_) return 'Null';
      if (flags == 0) return 'bottom';
      return 'bottom(${Flags.flagsToString(flags)})';
    }
    String nullability = canBeNull ? '?' : '';
    String baseClassSuffix = hasExactBaseClass ? '!' : '+';
    int otherFlags = flags & ~(Flags.null_ | Flags.inexactBaseClass);
    String suffix = Flags.flagsToString(otherFlags);
    return '$baseClass$baseClassSuffix$nullability($suffix)';
  }

  @override
  void generateAssignmentTo(
      ConstraintBuilder builder, Key destination, int mask) {
    if (flags & mask == 0) return;
    builder.addConstraint(new ValueConstraint(destination, masked(mask)));
  }

  bool isBottom(int mask) {
    return flags & mask == 0;
  }
}
