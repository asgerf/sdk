// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.atype;

import '../ast.dart';
import 'constraints.dart';
import 'value.dart';
import 'key.dart';

abstract class ConstraintBuilder {
  InterfaceAType getClassAsInstanceOf(Class subclass, Class superclass);
  InterfaceAType getTypeAsInstanceOf(InterfaceAType subtype, Class superclass);

  void addConstraint(Constraint constraint);

  void addImmediateSubtype(Key subtype, AType supertype) {
    if (!supertype.isAssignable) return;
    Key supertypeKey = supertype.key;
    Key supertypeNullability = supertype.nullability;
    if (supertypeKey != supertypeNullability) {
      addSubtypeConstraint(subtype, supertypeNullability, Flags.null_);
      addSubtypeConstraint(subtype, supertypeKey, Flags.all & ~Flags.null_);
    } else {
      addSubtypeConstraint(subtype, supertypeKey);
    }
  }

  void addSubtypeConstraint(Key subtype, Key supertype,
      [int mask = Flags.all]) {
    addConstraint(new SubtypeConstraint(subtype, supertype, mask));
  }

  void addNullableSubtypeConstraint(Key subtype, Key supertype) {
    addConstraint(new SubtypeConstraint(subtype, supertype, Flags.null_));
  }

  void addValueConstraint(Value value, Key destination) {
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
    if (supertype is InterfaceAType) {
      var casted = builder.getTypeAsInstanceOf(this, supertype.classNode);
      if (casted == null) return;
      builder.addImmediateSubtype(key, supertype);
      for (int i = 0; i < typeArguments.length; ++i) {
        typeArguments[i]
            .generateSubtypeConstraint(casted.typeArguments[i], builder);
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
    builder.addSubtypeConstraint(supertype.lowerBound, this.lowerBound);
  }
}

class NullAType extends AType {
  Key get key => null;
  Key get nullability => null;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    if (supertype.isAssignable) {
      builder.addValueConstraint(builder.nullValue, supertype.nullability);
    }
  }
}

class NullabilityType extends AType {
  final AType type;
  final Key nullability;

  NullabilityType(this.type, this.nullability);

  Key get key => type.key;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    if (supertype.isAssignable) {
      builder.addNullableSubtypeConstraint(nullability, supertype.nullability);
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
      builder.addSubtypeConstraint(this.key, supertype.key);
    } else {
      var bound = builder.getTypeParameterBound(parameter);
      bound.generateSubtypeConstraint(supertype, builder);
    }
  }
}
