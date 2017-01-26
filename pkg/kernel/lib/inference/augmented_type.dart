// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.atype;

import '../ast.dart';
import 'constraints.dart';
import 'substitution.dart';
import 'value.dart';
import 'key.dart';
import 'constraint_builder.dart';

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

  AType get innerType => this;

  AType toLowerBound(Key key);
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

  InterfaceAType toLowerBound(Key newKey) {
    return new InterfaceAType(newKey, classNode, typeArguments);
  }
}

class Bound {
  final AType upperBound;
  final Key lowerBoundKey;

  Bound(this.upperBound, this.lowerBoundKey);

  AType getLowerBound() => upperBound.toLowerBound(lowerBoundKey);

  void generateSubtypeConstraint(Bound supertype, ConstraintBuilder builder) {
    upperBound.generateSubtypeConstraint(supertype.upperBound, builder);
    if (lowerBoundKey != null && supertype.lowerBoundKey != null) {
      builder.addSubtypeConstraint(supertype.lowerBoundKey, this.lowerBoundKey);
    }
  }

  Bound substitute(Substitution substitution, bool covariant, int offset) {
    return new Bound(
        upperBound.substitute(substitution, covariant, offset), lowerBoundKey);
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

  ConstantAType toLowerBound(Key newKey) => this;
}

class NullabilityType extends AType {
  final AType type;
  final Key nullability;

  NullabilityType(this.type, this.nullability);

  Key get key => type.key;
  AType get innerType => type.innerType;

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

  AType toLowerBound(Key newKey) => type.toLowerBound(newKey);
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
    supertype = supertype.innerType;
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

  FunctionAType toLowerBound(Key newKey) {
    return new FunctionAType(newKey, typeParameters, requiredParameterCount,
        positionalParameters, namedParameterNames, namedParameters, returnType);
  }
}

class TypeParameterAType extends AType {
  final TypeParameter parameter;

  TypeParameterAType(this.parameter);

  Key get key => null;

  void generateSubtypeConstraint(AType supertype, ConstraintBuilder builder) {
    supertype = supertype.innerType;
    if (supertype is TypeParameterAType && supertype.parameter == parameter) {
      // No constraint is needed.
    } else {
      var bound = builder.getTypeParameterBound(parameter);
      bound.upperBound.generateSubtypeConstraint(supertype, builder);
    }
  }

  AType substitute(Substitution substitution, bool covariant, int offset) {
    return substitution.getOuterSubstitute(parameter, covariant, offset) ??
        this;
  }

  AType toLowerBound(Key newKey) {
    return new NullabilityType(this, newKey);
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

  AType toLowerBound(Key newKey) {
    throw 'Function type parameters cannot be converted to lower bounds';
  }
}
