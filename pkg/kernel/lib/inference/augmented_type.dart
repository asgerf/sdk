// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.augmented_type;

import '../ast.dart';
import 'constraint_builder.dart';
import 'key.dart';
import 'package:kernel/inference/substitution.dart';
import 'value.dart';

const bool _showKeys = const bool.fromEnvironment('kernel.inference.showKeys');

class ASupertype {
  final Class classNode;
  final List<AType> typeArguments;

  ASupertype(this.classNode, this.typeArguments);

  String toString() {
    if (typeArguments.isEmpty) return '$classNode';
    return '$classNode<${typeArguments.join(",")}>';
  }
}

abstract class AType {
  /// Describes the abstract values one may obtain by reading from a storage
  /// location with this type.
  ///
  /// This can be a [Value] or a [Key], depending on whether the abstract value
  /// is statically known, or is a symbolic value determined during type
  /// propagation.
  final ValueSource source;

  /// Describes the effects of assigning a value into a storage location with
  /// this type.
  ///
  /// In most cases this is a [Key], denoting an abstract storage location into
  /// which values should be recorded.
  ///
  /// Alternatives are [NowhereSink] that ignores incoming values and
  /// [ErrorSink] that throws an exception because the type should never
  /// occur as a left-hand value (e.g. it is an error to try to use the
  /// "this type" as a sink).
  ///
  /// For variables, fields, parameters, return types, and allocation-site
  /// type arguments, this equals the [source].  When a type occurs as type
  /// argument to an interface type, it represents a type bound, and then the
  /// source and sinks are separate [Key] values.
  final ValueSink sink;

  AType(this.source, this.sink) {
    assert(source != null);
    assert(sink != null);
  }

  void generateSubtypeConstraints(AType supertype, ConstraintBuilder builder) {
    supertype.sink.generateAssignmentFrom(builder, this.source, Flags.all);
    _generateSubtypeConstraints(supertype, builder);
  }

  void generateSubBoundConstraint(AType superbound, ConstraintBuilder builder) {
    if (superbound.source is Key) {
      Key superSource = superbound.source as Key;
      superSource.generateAssignmentFrom(builder, this.source, Flags.all);
    }
    if (superbound.sink is Key) {
      Key superSink = superbound.sink as Key;
      this.sink.generateAssignmentFrom(builder, superSink, Flags.all);
    }
    _generateSubtypeConstraints(superbound, builder);
  }

  void _generateSubtypeConstraints(AType supertype, ConstraintBuilder builder);

  bool containsAny(bool predicate(AType type)) => predicate(this);

  bool get containsFunctionTypeParameter =>
      containsAny((t) => t is FunctionTypeParameterAType);

  bool isClosed([Iterable<TypeParameter> scope = const []]) {
    return !containsAny(
        (t) => t is TypeParameterAType && !scope.contains(t.parameter));
  }

  static bool listContainsAny(
      Iterable<AType> types, bool predicate(AType type)) {
    return types.any((t) => t.containsAny(predicate));
  }

  AType substitute(Substitution substitution);

  static List<AType> substituteList(
      List<AType> types, Substitution substitution) {
    if (types.isEmpty) return const <AType>[];
    return types.map((t) => t.substitute(substitution)).toList(growable: false);
  }

  AType withSource(ValueSource source);
}

class InterfaceAType extends AType {
  final Class classNode;
  final List<AType> typeArguments;

  InterfaceAType(
      ValueSource source, ValueSink sink, this.classNode, this.typeArguments)
      : super(source, sink);

  void _generateSubtypeConstraints(AType supertype, ConstraintBuilder builder) {
    if (supertype is InterfaceAType) {
      var casted = builder.getTypeAsInstanceOf(this, supertype.classNode);
      if (casted == null) return;
      for (int i = 0; i < casted.typeArguments.length; ++i) {
        var subtypeArgument = casted.typeArguments[i];
        var supertypeArgument = supertype.typeArguments[i];
        subtypeArgument.generateSubBoundConstraint(supertypeArgument, builder);
      }
    }
  }

  bool containsAny(bool predicate(AType type)) =>
      predicate(this) || AType.listContainsAny(typeArguments, predicate);

  AType substitute(Substitution substitution) {
    return new InterfaceAType(source, sink, classNode,
        AType.substituteList(typeArguments, substitution));
  }

  AType withSource(ValueSource source) {
    return new InterfaceAType(source, sink, classNode, typeArguments);
  }

  String toString() {
    String typeArgumentPart =
        typeArguments.isEmpty ? '' : '<${typeArguments.join(',')}>';
    var value = source.value;
    return '$classNode($value)$typeArgumentPart';
  }
}

class FunctionAType extends AType {
  final List<AType> typeParameters;
  final int requiredParameterCount;
  final List<AType> positionalParameters;
  final List<String> namedParameterNames;
  final List<AType> namedParameters;
  final AType returnType;

  FunctionAType(
      ValueSource source,
      ValueSink sink,
      this.typeParameters,
      this.requiredParameterCount,
      this.positionalParameters,
      this.namedParameterNames,
      this.namedParameters,
      this.returnType)
      : super(source, sink);

  @override
  void _generateSubtypeConstraints(AType supertype, ConstraintBuilder builder) {
    if (supertype is FunctionAType) {
      for (int i = 0; i < typeParameters.length; ++i) {
        if (i < supertype.typeParameters.length) {
          supertype.typeParameters[i]
              .generateSubtypeConstraints(typeParameters[i], builder);
        }
      }
      for (int i = 0; i < positionalParameters.length; ++i) {
        if (i < supertype.positionalParameters.length) {
          supertype.positionalParameters[i]
              .generateSubtypeConstraints(positionalParameters[i], builder);
        }
      }
      for (int i = 0; i < namedParameters.length; ++i) {
        String name = namedParameterNames[i];
        int j = supertype.namedParameterNames.indexOf(name);
        if (j != -1) {
          supertype.namedParameters[j]
              .generateSubtypeConstraints(namedParameters[i], builder);
        }
      }
      returnType.generateSubtypeConstraints(supertype.returnType, builder);
    }
  }

  bool containsAny(bool predicate(AType type)) {
    return predicate(this) ||
        AType.listContainsAny(typeParameters, predicate) ||
        AType.listContainsAny(positionalParameters, predicate) ||
        AType.listContainsAny(namedParameters, predicate) ||
        returnType.containsAny(predicate);
  }

  FunctionAType substitute(Substitution substitution) {
    return new FunctionAType(
        source,
        sink,
        AType.substituteList(typeParameters, substitution),
        requiredParameterCount,
        AType.substituteList(positionalParameters, substitution),
        namedParameterNames,
        AType.substituteList(namedParameters, substitution),
        returnType.substitute(substitution));
  }

  String toString() {
    var typeParameterString =
        typeParameters.isEmpty ? '' : '<${typeParameters.join(",")}>';
    List<Object> parameters = <Object>[];
    parameters.addAll(positionalParameters.take(requiredParameterCount));
    if (requiredParameterCount > 0) {
      var optional =
          positionalParameters.skip(requiredParameterCount).join(',');
      parameters.add('[$optional]');
    }
    if (namedParameters.length > 0) {
      var named = new List.generate(namedParameters.length,
          (i) => '${namedParameterNames[i]}: ${namedParameters[i]}').join(',');
      parameters.add('{$named}');
    }
    var value = source.value;
    return 'Function($value)$typeParameterString($parameters) '
        '=> $returnType';
  }

  AType withSource(ValueSource source) {
    return new FunctionAType(
        source,
        sink,
        typeParameters,
        requiredParameterCount,
        positionalParameters,
        namedParameterNames,
        namedParameters,
        returnType);
  }
}

class FunctionTypeParameterAType extends AType {
  final int index;

  FunctionTypeParameterAType(ValueSource source, ValueSink sink, this.index)
      : super(source, sink);

  @override
  void _generateSubtypeConstraints(
      AType supertype, ConstraintBuilder builder) {}

  FunctionTypeParameterAType substitute(Substitution substitution) => this;

  String toString() => 'FunctionTypeParameter($index)';

  AType withSource(ValueSource source) {
    return new FunctionTypeParameterAType(source, sink, index);
  }
}

/// Potentially nullable or true bottom.
class BottomAType extends AType {
  BottomAType(ValueSource source, ValueSink sink) : super(source, sink);

  @override
  void _generateSubtypeConstraints(
      AType supertype, ConstraintBuilder builder) {}

  BottomAType substitute(Substitution substitution) => this;

  String toString() => 'Bottom(${source.value})';

  static final BottomAType nonNullable =
      new BottomAType(Value.bottom, ValueSink.nowhere);
  static final BottomAType nullable =
      new BottomAType(Value.nullValue, ValueSink.nowhere);

  AType withSource(ValueSource source) {
    return new BottomAType(source, sink);
  }
}

class TypeParameterAType extends AType {
  final TypeParameter parameter;

  TypeParameterAType(ValueSource source, ValueSink sink, this.parameter)
      : super(source, sink);

  @override
  void _generateSubtypeConstraints(AType supertype, ConstraintBuilder builder) {
    // TODO: Use bound.
  }

  AType substitute(Substitution substitution) {
    return substitution.getSubstitute(this);
  }

  String toString() => '$parameter${source.value}';

  AType withSource(ValueSource source) {
    return new TypeParameterAType(source, sink, parameter);
  }
}
