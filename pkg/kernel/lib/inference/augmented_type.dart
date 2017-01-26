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
  final ValueSource source;
  final ValueSink sink;

  AType(this.source, this.sink);

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

  bool get isPlaceholder => false;
  bool get containsPlaceholder => false;

  static bool listContainsPlaceholder(Iterable<AType> types) {
    return types.every((t) => t.containsPlaceholder);
  }

  AType substitute(Substitution substitution);

  static List<AType> substituteList(
      List<AType> types, Substitution substitution) {
    if (types.isEmpty) return const <AType>[];
    return types.map((t) => t.substitute(substitution)).toList(growable: false);
  }

  String get _keyString {
    if (!_showKeys) return '';
    return '($source,$sink)';
  }
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

  bool get containsPlaceholder => AType.listContainsPlaceholder(typeArguments);

  AType substitute(Substitution substitution) {
    return new InterfaceAType(source, sink, classNode,
        AType.substituteList(typeArguments, substitution));
  }

  String toString() {
    if (typeArguments.isEmpty) return '$classNode$_keyString';
    return '$classNode$_keyString<${typeArguments.join(",")}>';
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

  bool get containsPlaceholder {
    return AType.listContainsPlaceholder(typeParameters) ||
        AType.listContainsPlaceholder(positionalParameters) ||
        AType.listContainsPlaceholder(namedParameters) ||
        returnType.containsPlaceholder;
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
    return 'Function$_keyString$typeParameterString($parameters) '
        '=> $returnType';
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

  String toString() => '#$index';
}

/// Potentially nullable or true bottom.
class BottomAType extends AType {
  BottomAType(ValueSource source, ValueSink sink) : super(source, sink);

  @override
  void _generateSubtypeConstraints(
      AType supertype, ConstraintBuilder builder) {}

  BottomAType substitute(Substitution substitution) => this;

  String toString() => 'Bottom$_keyString';
}

class PlaceholderAType extends AType {
  final TypeParameter parameter;

  PlaceholderAType(this.parameter) : super(null, null);

  bool get isPlaceholder => true;
  bool get containsPlaceholder => false;

  @override
  void _generateSubtypeConstraints(AType supertype, ConstraintBuilder builder) {
    throw 'Incomplete type';
  }

  AType substitute(Substitution substitution) {
    return substitution.getSubstitute(parameter);
  }

  String toString() => '$parameter';
}
