// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.atype;

import '../ast.dart';
import 'constraints.dart';
import 'package:kernel/inference/augmented_checker.dart';
import 'package:kernel/inference/substitution.dart';
import 'value.dart';
import 'key.dart';

abstract class ConstraintBuilder {
  final AugmentedTypeChecker generator;
  final TypeParameterScope scope;

  ConstraintBuilder(this.generator, this.scope);

  List<Bound> getTypeAsInstanceOf(InterfaceAType subtype, Class superclass) {
    return generator.hierarchy
        .getTypeAsInstanceOf(subtype, superclass)
        .typeArguments;
  }

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

class ASupertype {
  final Class classNode;
  final List<AType> typeArguments;

  ASupertype(this.classNode, this.typeArguments);
}

abstract class AType {
  Key get key;
  Key get nullability => key;

  bool get isAssignable => key != null;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder);

  AType substitute(Substitution substitution, bool covariant, int offset);

  static List<AType> substituteList(
      List<AType> list, Substitution substitution, bool covariant, int offset) {
    return list
        .map((t) => t.substitute(substitution, covariant, offset))
        .toList(growable: false);
  }

  bool checkIsClosed(List<TypeParameter> typeParameters) {}
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

  InterfaceAType substitute(
      Substitution substitution, bool covariant, int offset) {
    return new InterfaceAType(key, classNode,
        Bound.substituteList(typeArguments, substitution, covariant, offset));
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

  Bound substitute(Substitution substitution, bool covariant, int offset) {
    return new Bound(
        upperBound.substitute(substitution, covariant, offset), lowerBound);
  }

  static List<Bound> substituteList(List<Bound> bounds,
      Substitution substitution, bool covariant, int offset) {
    return bounds
        .map((b) => b.substitute(substitution, covariant, offset))
        .toList(growable: false);
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

  ConstantAType substitute(
      Substitution substitution, bool covariant, int offset) {
    return this;
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

  NullabilityType substitute(
      Substitution substitution, bool covariant, int offset) {
    return new NullabilityType(
        type.substitute(substitution, covariant, offset), nullability);
  }
}

class FunctionAType extends AType {
  final Key key;
  final List<Bound> typeParameters;
  final int requiredParameterCount;
  final List<AType> positionalParameters;
  final List<String> namedParameterNames;
  final List<AType> namedParameters;
  final AType returnType;

  FunctionAType(
      this.key,
      this.typeParameters,
      this.requiredParameterCount,
      this.positionalParameters,
      this.namedParameterNames,
      this.namedParameters,
      this.returnType);

  @override
  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    builder.addImmediateSubtype(key, supertype);
    if (supertype is FunctionAType) {
      for (int i = 0; i < typeParameters.length; ++i) {
        if (i < supertype.typeParameters.length) {
          supertype.typeParameters[i]
              .generateSubtypeConstraint(typeParameters[i], builder);
        }
      }
      for (int i = 0; i < positionalParameters.length; ++i) {
        if (i < supertype.positionalParameters.length) {
          supertype.positionalParameters[i]
              .generateSubtypeConstraint(positionalParameters[i], builder);
        }
      }
      for (int i = 0; i < namedParameters.length; ++i) {
        String name = namedParameterNames[i];
        int j = supertype.namedParameterNames.indexOf(name);
        if (j != -1) {
          supertype.namedParameters[j]
              .generateSubtypeConstraint(namedParameters[i], builder);
        }
      }
      returnType.generateSubtypeConstraint(supertype.returnType, builder);
    }
  }

  FunctionAType substitute(
      Substitution substitution, bool covariant, int offset) {
    offset += typeParameters.length;
    return new FunctionAType(
        key,
        Bound.substituteList(typeParameters, substitution, !covariant, offset),
        requiredParameterCount,
        AType.substituteList(
            positionalParameters, substitution, !covariant, offset),
        namedParameterNames,
        AType.substituteList(namedParameters, substitution, !covariant, offset),
        returnType.substitute(substitution, covariant, offset));
  }
}

class TypeParameterAType extends AType {
  final TypeParameter parameter;

  TypeParameterAType(this.parameter);

  Key get key => null;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    if (supertype is TypeParameterAType && supertype.parameter == parameter) {
      // No constraint is needed.
    } else {
      var bound = builder.getTypeParameterBound(parameter);
      bound.generateSubtypeConstraint(supertype, builder);
    }
  }

  AType substitute(Substitution substitution, bool covariant, int offset) {
    return substitution.getOuterSubstitute(parameter, covariant, offset) ??
        this;
  }
}

class FunctionTypeParameterAType extends AType {
  final int index;

  FunctionTypeParameterAType(this.index);

  Key get key => null;

  @override
  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {}

  AType substitute(Substitution substitution, bool covariant, int offset) {
    return substitution.getInnerSubstitute(index, covariant, offset) ?? this;
  }
}
