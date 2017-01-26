// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.strong_inference.substitution;

import '../ast.dart';
import 'augmented_type.dart';

abstract class Substitution {
  const Substitution();

  AType getSubstitute(TypeParameter parameter);

  AType substituteType(AType type) {
    return type.substitute(this);
  }

  List<AType> substituteTypeList(List<AType> types) {
    return types.map((t) => t.substitute(this)).toList(growable: false);
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
}

class EmptySubstitution extends Substitution {
  static const EmptySubstitution instance = const EmptySubstitution();

  const EmptySubstitution();

  @override
  AType substituteType(AType type) {
    return type; // Do not traverse type when there is nothing to do.
  }

  AType getSubstitute(TypeParameter parameter) {
    return null;
  }
}

class SupertypeSubstitution extends Substitution {
  final ASupertype supertype;

  SupertypeSubstitution(this.supertype);

  AType getSubstitute(TypeParameter parameter) {
    int index = supertype.classNode.typeParameters.indexOf(parameter);
    return index == -1 ? null : supertype.typeArguments[index];
  }
}

class InterfaceSubstitution extends Substitution {
  final InterfaceAType type;

  InterfaceSubstitution(this.type);

  AType getSubstitute(TypeParameter parameter) {
    int index = type.classNode.typeParameters.indexOf(parameter);
    if (index == -1) return null;
    return type.typeArguments[index];
  }
}

class PairSubstitution extends Substitution {
  final List<TypeParameter> parameters;
  final List<AType> types;

  PairSubstitution(this.parameters, this.types);

  AType getSubstitute(TypeParameter parameter) {
    int index = parameters.indexOf(parameter);
    if (index == -1) return null;
    return types[index];
  }
}

class SequenceSubstitution extends Substitution {
  final Substitution left, right;

  SequenceSubstitution(this.left, this.right);

  AType getSubstitute(TypeParameter parameter) {
    var replacement = left.getSubstitute(parameter);
    if (replacement != null) {
      return right.substituteType(replacement);
    } else {
      return right.getSubstitute(parameter);
    }
  }
}

class EitherSubstitution extends Substitution {
  final Substitution left, right;

  EitherSubstitution(this.left, this.right);

  AType getSubstitute(TypeParameter parameter) {
    return left.getSubstitute(parameter) ?? right.getSubstitute(parameter);
  }
}

class ClosednessChecker extends Substitution {
  final Iterable<TypeParameter> typeParameters;

  ClosednessChecker(this.typeParameters);

  AType getSubstitute(TypeParameter parameter) {
    if (typeParameters.contains(parameter)) return null;
    throw '$parameter from ${parameter.parent} ${parameter.parent.parent} is out of scope';
  }
}
