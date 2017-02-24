// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.value;

import '../ast.dart';
import '../text/printable.dart';
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
class Value extends ValueSource implements Printable {
  static final Value bottom = new Value(null, ValueFlags.none);
  static final Value null_ = new Value(null, ValueFlags.null_);

  final Class baseClass;
  final int flags;

  Value(this.baseClass, this.flags);

  bool get canBeNull => flags & ValueFlags.null_ != 0;
  bool get canBeInteger => flags & ValueFlags.integer != 0;
  bool get canBeDouble => flags & ValueFlags.double_ != 0;
  bool get canBeString => flags & ValueFlags.string != 0;

  bool get isAlwaysNull => valueSets == ValueFlags.null_;
  bool get isAlwaysInteger => valueSets == ValueFlags.integer;
  bool get isAlwaysDouble => valueSets == ValueFlags.double_;
  bool get isAlwaysString => valueSets == ValueFlags.string;

  bool get isNothing => valueSets == 0;

  bool get hasExactBaseClass => flags & ValueFlags.inexactBaseClass == 0;
  bool get isEscaping => flags & ValueFlags.escaping != 0;

  int get valueSets => flags & ValueFlags.allValueSets;

  Value masked(int mask) {
    int maskedFlags = flags & mask;
    if (maskedFlags == flags) return this;
    if (maskedFlags == 0) return bottom;
    if (maskedFlags == ValueFlags.null_) return null_;
    return new Value(baseClass, maskedFlags);
  }

  bool isBottom([int mask = ValueFlags.allValueSets]) {
    return flags & mask == 0;
  }

  Value get value => this;

  @override
  T acceptSource<T>(ValueSourceVisitor<T> visitor) {
    return visitor.visitValue(this);
  }

  @override
  void printTo(Printer printer) {
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

  String toString() => Printable.show(this);
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

  /// Set if the value can escape.
  static const int escaping = 1 << 7;

  // -------- Utility stuff ----------

  static const int numberOfFlags = 8;
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
    'escaped',
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
