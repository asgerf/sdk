// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.value;

import '../ast.dart';
import '../class_hierarchy.dart';
import '../text/ast_to_text.dart';
import 'extractor/value_source.dart';

/// An abstract value, denoting a set of possible concrete values.
///
/// This consists of a [baseClass] and a fixed-size bitmask, [flags].
///
/// The base class denotes the best known superclass of the concrete values,
/// or `null` if set of concrete values is empty or contains only null.
/// Nullability is ignored when determining the base class, and interface types
/// are not considered base class candidates (interface types can be generally
/// be derived by type checking anyway).
///
/// The [flags] are a bitmask with the flags defined in [ValueFlags]. By
/// convention, a 1-bit is always imprecise but safe, whereas a 0-bit is
/// precise but potentially unsafe.
///
/// If the bit [ValueFlags.inexactBaseClass] is 0, then the base class is exact,
/// that is, all non-null concrete values are exact instances of the base class.
///
/// See [ValueFlags] for more details about the flags.
class Value extends ValueSource {
  final Class baseClass;
  final int flags;

  Value(this.baseClass, this.flags);

  static final Value bottom = new Value(null, ValueFlags.none);
  static final Value null_ = new Value(null, ValueFlags.null_);

  int get valueSets => flags & ValueFlags.allValueSets;
  bool get hasExactBaseClass => flags & ValueFlags.inexactBaseClass == 0;
  bool get canBeNull => flags & ValueFlags.null_ != 0;
  bool get canBeNonNull => flags & ValueFlags.nonNullValueSets != 0;

  Value masked(int mask) {
    int maskedFlags = flags & mask;
    if (maskedFlags == flags) return this;
    return new Value(baseClass, maskedFlags);
  }

  String toString() {
    if (baseClass == null) {
      if (flags == ValueFlags.null_) return 'Null';
      if (flags == 0) return 'bottom';
      return 'bottom(${ValueFlags.flagsToString(flags)})';
    }
    String nullability = canBeNull ? '?' : '';
    String baseClassSuffix = hasExactBaseClass ? '!' : '+';
    int otherFlags = flags & ~(ValueFlags.null_ | ValueFlags.inexactBaseClass);
    String suffix = ValueFlags.flagsToString(otherFlags);
    return '$baseClass$baseClassSuffix$nullability($suffix)';
  }

  T acceptSource<T>(ValueSourceVisitor<T> visitor) {
    return visitor.visitValue(this);
  }

  bool isBottom([int mask = ValueFlags.allValueSets]) {
    return flags & mask == 0;
  }

  Value get value => this;

  Value concreteJoin(Value other, ClassHierarchy hierarchy) {
    var base = baseClass == null
        ? other.baseClass
        : other.baseClass == null
            ? this.baseClass
            : hierarchy.getCommonBaseClass(baseClass, other.baseClass);
    int newFlags = flags | other.flags;
    if (baseClass != null && baseClass != base ||
        other.baseClass != null && other.baseClass != base) {
      newFlags |= ValueFlags.inexactBaseClass;
    }
    return new Value(base, newFlags);
  }

  void print(Printer printer) {
    if (value.baseClass == null) {
      if (value.canBeNull) {
        printer.write('Null');
      } else {
        printer.write('Bottom');
      }
    } else {
      printer.writeClassReference(value.baseClass);
      if (value.hasExactBaseClass) {
        printer.write('!');
      } else {
        printer.write('+');
      }
      if (value.canBeNull) {
        printer.write('?');
      }
    }
  }
}

/// Defines the flags tracked by [Value.flags].
///
/// By convention, a 1-bit is always imprecise but safe, whereas a 0-bit is
/// precise but potentially unsafe.
///
/// A subset of these flags are the "value-set flags", which partions the space
/// of possible Dart values into disjoint sets, such that all concrete values
/// belong to exactly one of these sets.  These flags are [null_], [integer],
/// [string], [double], [boolean], and [other].  If the corresponding flag is
/// zero, then the value cannot be anything from that set.
///
/// For example, if the [integer] flag is 0, then the value can't be an integer.
/// Conversely, if [integer] is the only value-set flag that is 1, then the
/// value must be an integer.
///
/// The remaining flags are orthogonal to the value-set flags, i.e. they further
/// restrict the set of possible values (if zero).
class ValueFlags {
  // -------- Value-set flags ----------
  static const int null_ = 1 << 0;
  static const int integer = 1 << 1;
  static const int string = 1 << 2;
  static const int double_ = 1 << 3;
  static const int boolean = 1 << 4;

  /// Denotes any value not included by the other value-set flags.  This ensures
  /// the value-set denotes a complete partition of the value space.
  static const int other = 1 << 5;

  static const int numberOfValueSets = 6;
  static const int allValueSets = (1 << numberOfValueSets) - 1;

  // -------- Flags that are not part of the value-set partition ----------

  /// Set if the [Value.baseClass] is a superclass of the concrete values,
  /// not necessarily the exact class.
  static const int inexactBaseClass = 1 << 6;


  // -------- Utility stuff ----------

  static const int numberOfFlags = 7;
  static const int all = (1 << numberOfFlags) - 1;
  static const int none = 0;

  static const int notNull = all & ~null_;
  static const int nonNullValueSets = allValueSets & ~null_;

  static const List<String> flagNames = const <String>[
    'Null', // Capitalize to avoid confusion with null.toString().
    'integer',
    'string',
    'double',
    'boolean',
    'other',
    'inexactBaseClass',
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
