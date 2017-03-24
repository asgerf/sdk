// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.substitution;

import '../../ast.dart';
import '../value.dart';
import 'augmented_type.dart';
import 'value_sink.dart';
import 'value_source.dart';

abstract class Substitution {
  const Substitution();

  AType getSubstitute(TypeParameterAType parameter) {
    // Note: this is overridden in some subclasses.
    return getRawSubstitute(parameter.parameter);
  }

  AType getRawSubstitute(TypeParameter parameter);

  AType getInstantiation(FunctionTypeParameterAType parameter, int shift);

  AType substituteType(AType type, [int shift = 0]) {
    return type.substitute(this, shift);
  }

  // TODO: Determine if this needs to be changed or just removed.
  AType substituteBound(AType type) => type.substitute(this, 0);

  List<AType> substituteTypeList(List<AType> types, [int shift = 0]) {
    return types.map((t) => t.substitute(this, shift)).toList(growable: false);
  }

  static const Substitution empty = EmptySubstitution.instance;

  static Substitution fromSupertype(ASupertype type) {
    return fromPairs(type.classNode.typeParameters, type.typeArguments);
  }

  static Substitution fromInterfaceType(InterfaceAType type) {
    return fromPairs(type.classNode.typeParameters, type.typeArguments);
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

  static Substitution bottomForClass(Class class_) {
    return new BottomSubstitution(class_);
  }

  static Substitution erasing(AType result) {
    return new ErasingSubstitution(result);
  }

  static Substitution instantiate(List<AType> functionTypeArguments) {
    return new FunctionInstantiator(functionTypeArguments);
  }
}

class ErasingSubstitution extends Substitution {
  final AType type;

  ErasingSubstitution(this.type);

  @override
  AType getRawSubstitute(TypeParameter parameter) {
    return type;
  }

  @override
  AType getInstantiation(FunctionTypeParameterAType parameter, int shift) {
    return type;
  }
}

class BottomSubstitution extends Substitution {
  final Class class_;

  BottomSubstitution(this.class_);

  @override
  AType getRawSubstitute(TypeParameter parameter) {
    if (parameter.parent == class_) {
      return new BottomAType(Value.bottom, ValueSink.nowhere);
    }
    return null;
  }

  @override
  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    return null;
  }
}

class EmptySubstitution extends Substitution {
  static const EmptySubstitution instance = const EmptySubstitution();

  const EmptySubstitution();

  @override
  AType substituteType(AType type, [int shift = 0]) {
    return type; // Do not traverse type when there is nothing to do.
  }

  AType getRawSubstitute(TypeParameter parameter) {
    return null;
  }

  @override
  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    return null;
  }
}

class PairSubstitution extends Substitution {
  final List<TypeParameter> parameters;
  final List<AType> types;

  PairSubstitution(this.parameters, this.types);

  AType getSubstitute(TypeParameterAType parameterType) {
    var parameter = parameterType.parameter;
    int index = parameters.indexOf(parameter);
    if (index == -1) return null;
    AType argument = types[index];
    var source =
        new ValueSourceWithNullability(argument.source, parameterType.source);
    return argument.withSource(source);
  }

  AType getRawSubstitute(TypeParameter parameter) {
    int index = parameters.indexOf(parameter);
    if (index == -1) return null;
    return types[index];
  }

  @override
  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    return null;
  }
}

class SequenceSubstitution extends Substitution {
  final Substitution left, right;

  SequenceSubstitution(this.left, this.right);

  AType getSubstitute(TypeParameterAType type) {
    var replacement = left.getSubstitute(type);
    if (replacement != null) {
      return right.substituteType(replacement);
    } else {
      return right.getSubstitute(type);
    }
  }

  AType getRawSubstitute(TypeParameter parameter) {
    var replacement = left.getRawSubstitute(parameter);
    if (replacement != null) {
      return right.substituteType(replacement);
    } else {
      return right.getRawSubstitute(parameter);
    }
  }

  @override
  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    var replacement = left.getInstantiation(type, shift);
    if (replacement != null) {
      return right.substituteType(replacement);
    } else {
      return right.getInstantiation(type, shift);
    }
  }
}

class EitherSubstitution extends Substitution {
  final Substitution left, right;

  EitherSubstitution(this.left, this.right);

  AType getSubstitute(TypeParameterAType type) {
    return left.getSubstitute(type) ?? right.getSubstitute(type);
  }

  AType getRawSubstitute(TypeParameter parameter) {
    return left.getRawSubstitute(parameter) ??
        right.getRawSubstitute(parameter);
  }

  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    return left.getInstantiation(type, shift) ??
        right.getInstantiation(type, shift);
  }
}

class ClosednessChecker extends Substitution {
  final Iterable<TypeParameter> typeParameters;

  ClosednessChecker(this.typeParameters);

  AType getRawSubstitute(TypeParameter parameter) {
    if (typeParameters.contains(parameter)) return null;
    throw '$parameter from ${parameter.parent} ${parameter.parent.parent} '
        'is out of scope';
  }

  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    throw '$type is referenced out of scope is out of scope';
  }
}

class FunctionInstantiator extends Substitution {
  final List<AType> arguments;

  FunctionInstantiator(this.arguments);

  AType getRawSubstitute(TypeParameter parameter) {
    return null;
  }

  AType getInstantiation(FunctionTypeParameterAType type, int shift) {
    int shiftedIndex = type.index - shift;
    if (shiftedIndex >= 0) {
      assert(shiftedIndex < arguments.length,
          'Too few type arguments or type argument out of scope');
      return arguments[shiftedIndex];
    } else {
      return null;
    }
  }
}
