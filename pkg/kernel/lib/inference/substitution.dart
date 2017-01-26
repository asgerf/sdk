// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.strong_inference.substitution;

import '../ast.dart';
import 'augmented_type.dart';

abstract class Substitution {
  const Substitution();

  AType getOuterSubstitute(TypeParameter parameter, bool covariant, int offset);

  AType getInnerSubstitute(int index, bool covariant, int offset);

  AType substituteType(AType type, {bool covariant: true, int offset: 0}) {
    return type.substitute(this, covariant, offset);
  }

  Bound substituteBound(Bound bound, {bool covariant: true, int offset: 0}) {
    return bound.substitute(this, covariant, offset);
  }

  List<AType> substituteTypeList(List<AType> types,
      {bool covariant: true, int offset: 0}) {
    return types
        .map((t) => t.substitute(this, covariant, offset))
        .toList(growable: false);
  }

  List<Bound> substituteBoundList(List<Bound> bounds,
      {bool covariant: true, int offset: 0}) {
    return bounds
        .map((b) => b.substitute(this, covariant, offset))
        .toList(growable: false);
  }

  static const Substitution empty = EmptySubstitution.instance;

  static Substitution fromSupertype(ASupertype type) {
    if (type.typeArguments.isEmpty) return empty;
    return new SupertypeSubstitution(type);
  }

  static Substitution fromInterfaceType(InterfaceAType type) {
    if (type.typeArguments.isEmpty) return empty;
    return new InterfaceSubstitution(type);
  }

  static Substitution fromPairs(
      List<TypeParameter> parameters, List<AType> types) {
    assert(parameters.length == types.length);
    if (parameters.isEmpty) return empty;
    return new PairSubstitution(parameters, types);
  }

  static Substitution either(Substitution first, Substitution second) {
    if (first == empty) return second;
    if (second == empty) return first;
    return new EitherSubstitution(first, second);
  }

  static Substitution sequence(Substitution first, Substitution second) {
    if (first == empty) return second;
    if (second == empty) return first;
    return new SequenceSubstitution(first, second);
  }

  static Substitution bottomForClass(Class class_, AType top, AType bottom) {
    if (class_.typeParameters.isEmpty) return empty;
    return new BottomSubstitution(class_, top, bottom);
  }

  static Substitution instantiateFunctionType(List<AType> arguments) {
    return new InstantiatingSubstitution(arguments);
  }

  static Substitution generalizeFunctionType(List<TypeParameter> parameters) {
    return new GeneralizingSubstitution(parameters);
  }
}

class EmptySubstitution extends Substitution {
  static const EmptySubstitution instance = const EmptySubstitution();

  const EmptySubstitution();

  @override
  AType substituteType(AType type, {bool covariant: true, int offset: 0}) {
    return type;
  }

  @override
  Bound substituteBound(Bound bound, {bool covariant: true, int offset: 0}) {
    return bound;
  }

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    return null;
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return null;
  }
}

class SupertypeSubstitution extends Substitution {
  final ASupertype supertype;

  SupertypeSubstitution(this.supertype);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    int index = supertype.classNode.typeParameters.indexOf(parameter);
    return index == -1 ? null : supertype.typeArguments[index];
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return null;
  }
}

class InterfaceSubstitution extends Substitution {
  final InterfaceAType type;

  InterfaceSubstitution(this.type);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    Class class_ = type.classNode;
    int index = class_.typeParameters.indexOf(parameter);
    if (index == -1) return null;
    var bound = type.typeArguments[index];
    return covariant ? bound.upperBound : bound.getLowerBound();
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return null;
  }
}

class PairSubstitution extends Substitution {
  final List<TypeParameter> parameters;
  final List<AType> types;

  PairSubstitution(this.parameters, this.types);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    int index = parameters.indexOf(parameter);
    if (index == -1) return null;
    return types[index];
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return null;
  }
}

class SequenceSubstitution extends Substitution {
  final Substitution left, right;

  SequenceSubstitution(this.left, this.right);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    var replacement = left.getOuterSubstitute(parameter, covariant, offset);
    if (replacement != null) {
      return right.substituteType(replacement,
          covariant: covariant, offset: offset);
    } else {
      return right.getOuterSubstitute(parameter, covariant, offset);
    }
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    var replacement = left.getInnerSubstitute(index, covariant, offset);
    if (replacement != null) {
      return right.substituteType(replacement,
          covariant: covariant, offset: offset);
    } else {
      return right.getInnerSubstitute(index, covariant, offset);
    }
  }
}

class EitherSubstitution extends Substitution {
  final Substitution left, right;

  EitherSubstitution(this.left, this.right);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    return left.getOuterSubstitute(parameter, covariant, offset) ??
        right.getOuterSubstitute(parameter, covariant, offset);
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return left.getInnerSubstitute(index, covariant, offset) ??
        right.getInnerSubstitute(index, covariant, offset);
  }
}

class BottomSubstitution extends Substitution {
  final Class class_;
  final AType top, bottom;

  BottomSubstitution(this.class_, this.top, this.bottom);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    if (class_.typeParameters.contains(parameter)) {
      return covariant ? bottom : top;
    } else {
      return null;
    }
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return null;
  }
}

class InstantiatingSubstitution extends Substitution {
  final List<AType> arguments;

  InstantiatingSubstitution(this.arguments);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    return null;
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return index >= offset ? arguments[index - offset] : null;
  }
}

class GeneralizingSubstitution extends Substitution {
  final List<TypeParameter> typeParameters;

  GeneralizingSubstitution(this.typeParameters);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    int index = typeParameters.indexOf(parameter);
    if (index == -1) return new TypeParameterAType(parameter);
    return new FunctionTypeParameterAType(index + offset);
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    return null;
  }
}

class ClosednessChecker extends Substitution {
  final Iterable<TypeParameter> typeParameters;

  ClosednessChecker(this.typeParameters);

  AType getOuterSubstitute(
      TypeParameter parameter, bool covariant, int offset) {
    if (typeParameters.contains(parameter)) return null;
    throw '$parameter from ${parameter.parent} ${parameter.parent.parent} is out of scope';
  }

  AType getInnerSubstitute(int index, bool covariant, int offset) {
    if (index >= offset) throw 'Inner parameter T#$index is out of scope';
    return null;
  }
}
