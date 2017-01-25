// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.atype;

import '../ast.dart';
import 'constraints.dart';
import 'value.dart';
import 'key.dart';

abstract class ConstraintBuilder {
  List<Bound> getClassAsInstanceOf(Class subclass, Class superclass);
  List<Bound> getTypeAsInstanceOf(InterfaceAType subtype, Class superclass);

  void addConstraint(Constraint constraint);

  void addImmediateSubtype(Key subtype, AType supertype) {
    assert(subtype != null);
    assert(supertype != null);
    if (!supertype.isAssignable) return;
    Key supertypeKey = supertype.key;
    Key supertypeNullability = supertype.nullability;
    if (supertypeKey != supertypeNullability) {
      addSubtypeConstraint(subtype, supertypeNullability, Flags.null_);
      addSubtypeConstraint(subtype, supertypeKey, Flags.notNull);
    } else {
      addSubtypeConstraint(subtype, supertypeKey);
    }
  }

  void addImmediateValue(Value value, AType supertype) {
    assert(value != null);
    assert(supertype != null);
    if (!supertype.isAssignable) return;
    Key supertypeKey = supertype.key;
    Key supertypeNullability = supertype.nullability;
    if (supertypeKey != supertypeNullability) {
      if (value.canBeNull) {
        addValueConstraint(value, supertypeNullability);
      }
      if (value.canBeNonNull) {
        addValueConstraint(value.masked(Flags.notNull), supertypeKey);
      }
    } else {
      addValueConstraint(value, supertypeKey);
    }
  }

  void addSubtypeConstraint(Key subtype, Key supertype,
      [int mask = Flags.all]) {
    assert(subtype != null);
    assert(supertype != null);
    addConstraint(new SubtypeConstraint(subtype, supertype, mask));
  }

  void addValueConstraint(Value value, Key destination) {
    assert(value != null);
    assert(destination != null);
    addConstraint(new ValueConstraint(destination, value));
  }

  Value get nullValue;

  AType getTypeParameterBound(TypeParameter parameter);
}

abstract class AType {
  Key get key;
  Key get nullability => key;

  bool get isAssignable => key != null;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder);
}

class InterfaceAType extends AType {
  final Key key;
  final Class classNode;
  final List<Bound> typeArguments;

  InterfaceAType(this.key, this.classNode, this.typeArguments);

  Constraint generateAssignmentTo(Key destination) {
    return new SubtypeConstraint(this.key, destination);
  }

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    builder.addImmediateSubtype(key, supertype);
    if (supertype is InterfaceAType) {
      List<Bound> upcastArguments =
          builder.getTypeAsInstanceOf(this, supertype.classNode);
      if (upcastArguments == null) return;
      for (int i = 0; i < typeArguments.length; ++i) {
        upcastArguments[i]
            .generateSubtypeConstraint(supertype.typeArguments[i], builder);
      }
    }
  }
}

class Bound {
  final AType upperBound;
  final Key lowerBound;

  Bound(this.upperBound, this.lowerBound);

  void generateSubtypeConstraint(Bound supertype, ConstraintBuilder builder) {
    upperBound.generateSubtypeConstraint(supertype.upperBound, builder);
    if (lowerBound != null && supertype.lowerBound != null) {
      builder.addSubtypeConstraint(supertype.lowerBound, this.lowerBound);
    }
  }
}

class ConstantAType extends AType {
  final Value value;

  ConstantAType(this.value);

  Key get key => null;
  Key get nullability => null;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    builder.addImmediateValue(value, supertype);
  }
}

class NullabilityType extends AType {
  final AType type;
  final Key nullability;

  NullabilityType(this.type, this.nullability);

  Key get key => type.key;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    if (supertype.isAssignable) {
      builder.addSubtypeConstraint(
          nullability, supertype.nullability, Flags.null_);
    }
    type.generateSubtypeConstraint(supertype, builder);
  }
}

class TypeParameterAType extends AType {
  final TypeParameter parameter;
  final Key key; // Refers to the key bound on the parameter.

  TypeParameterAType(this.parameter, this.key);

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    if (supertype is TypeParameterAType && supertype.parameter == parameter) {
      // No constraint is needed.
    } else {
      var bound = builder.getTypeParameterBound(parameter);
      bound.generateSubtypeConstraint(supertype, builder);
    }
  }
}
