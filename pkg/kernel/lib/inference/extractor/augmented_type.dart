// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.augmented_type;

import '../../ast.dart';
import 'constraint_builder.dart';
import '../key.dart';
import 'substitution.dart';
import 'package:kernel/text/ast_to_text.dart';
import '../value.dart';

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

  accept(ATypeVisitor visitor);

  AType substitute(Substitution substitution);

  /// Returns a copy of this type with its value source replaced.
  AType withSource(ValueSource source);

  /// Generates constraints to ensure this type is more specific than
  /// [supertype].
  void generateSubtypeConstraints(AType supertype, ConstraintBuilder builder) {
    supertype.sink.generateAssignmentFrom(builder, this.source, Flags.all);
    _generateSubtypeConstraintsForSubterms(supertype, builder);
  }

  /// Generates constraints to ensure this bound is more specific than
  /// [superbound].
  void generateSubBoundConstraint(AType superbound, ConstraintBuilder builder) {
    if (superbound.source is Key) {
      Key superSource = superbound.source as Key;
      superSource.generateAssignmentFrom(builder, this.source, Flags.all);
    }
    if (superbound.sink is Key) {
      Key superSink = superbound.sink as Key;
      this.sink.generateAssignmentFrom(builder, superSink, Flags.all);
    }
    _generateSubtypeConstraintsForSubterms(superbound, builder);
  }

  /// Generates subtyping constraints specific to a subclass.
  void _generateSubtypeConstraintsForSubterms(
      AType supertype, ConstraintBuilder builder);

  /// True if this type or any of its subterms match [predicate].
  bool containsAny(bool predicate(AType type)) => predicate(this);

  bool get containsFunctionTypeParameter =>
      containsAny((t) => t is FunctionTypeParameterAType);

  /// True if this contains no type parameters, other than those in [scope].
  bool isClosed([Iterable<TypeParameter> scope = const []]) {
    return !containsAny(
        (t) => t is TypeParameterAType && !scope.contains(t.parameter));
  }

  void writeTo(Printer printer);

  static bool listContainsAny(
      Iterable<AType> types, bool predicate(AType type)) {
    return types.any((t) => t.containsAny(predicate));
  }

  static List<AType> substituteList(
      List<AType> types, Substitution substitution) {
    if (types.isEmpty) return const <AType>[];
    return types.map((t) => t.substitute(substitution)).toList(growable: false);
  }
}

class InterfaceAType extends AType {
  final Class classNode;
  final List<AType> typeArguments;

  InterfaceAType(
      ValueSource source, ValueSink sink, this.classNode, this.typeArguments)
      : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitInterfaceAType(this);

  void _generateSubtypeConstraintsForSubterms(
      AType supertype, ConstraintBuilder builder) {
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

  void writeTo(Printer printer) {
    Value value = source.value;
    value.print(printer);
    if (value.baseClass != classNode) {
      printer.writeSymbol('&');
      printer.writeClassReference(classNode);
    }
    if (typeArguments.isNotEmpty) {
      printer.writeSymbol('<');
      printer.writeList(typeArguments, (AType bound) {
        bound.writeTo(printer);
        var sink = bound.sink;
        if (sink is Key) {
          printer.writeSymbol('/');
          if (!sink.value.isBottom(Flags.valueFlags)) {
            sink.value.print(printer);
          }
        }
      });
      printer.writeSymbol('>');
    }
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

  accept(ATypeVisitor visitor) => visitor.visitFunctionAType(this);

  @override
  void _generateSubtypeConstraintsForSubterms(
      AType supertype, ConstraintBuilder builder) {
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

  void writeTo(Printer printer) {
    Value value = source.value;
    if (value.canBeNull) {
      printer.write('?');
    }
    if (typeParameters.isNotEmpty) {
      printer.writeSymbol('<');
      printer.writeList(typeParameters, (AType type) {
        type.writeTo(printer);
      });
      printer.writeSymbol('>');
    }
    printer.writeSymbol('(');
    if (positionalParameters.length > 0) {
      printer.writeList(positionalParameters.take(requiredParameterCount),
          (AType p) => p.writeTo(printer));
      if (requiredParameterCount < positionalParameters.length) {
        if (requiredParameterCount > 0) {
          printer.writeComma();
        }
        printer.writeSymbol('[');
        printer.writeList(positionalParameters.skip(requiredParameterCount),
            (AType p) => p.writeTo(printer));
        printer.writeSymbol(']');
      }
    }
    printer.writeSymbol(') => ');
    returnType.writeTo(printer);
  }
}

class FunctionTypeParameterAType extends AType {
  final int index;

  FunctionTypeParameterAType(ValueSource source, ValueSink sink, this.index)
      : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitFunctionTypeParameterAType(this);

  @override
  void _generateSubtypeConstraintsForSubterms(
      AType supertype, ConstraintBuilder builder) {}

  FunctionTypeParameterAType substitute(Substitution substitution) => this;

  String toString() => 'FunctionTypeParameter($index)';

  AType withSource(ValueSource source) {
    return new FunctionTypeParameterAType(source, sink, index);
  }

  void writeTo(Printer printer) {
    printer.writeWord('FunctionTypeParameter($index)');
  }
}

/// Potentially nullable or true bottom.
class BottomAType extends AType {
  BottomAType(ValueSource source, ValueSink sink) : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitBottomAType(this);

  @override
  void _generateSubtypeConstraintsForSubterms(
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

  void writeTo(Printer printer) {
    source.value.print(printer);
  }
}

class TypeParameterAType extends AType {
  final TypeParameter parameter;

  TypeParameterAType(ValueSource source, ValueSink sink, this.parameter)
      : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitTypeParameterAType(this);

  @override
  void _generateSubtypeConstraintsForSubterms(
      AType supertype, ConstraintBuilder builder) {
    // TODO: Use bound.
  }

  AType substitute(Substitution substitution) {
    return substitution.getSubstitute(this);
  }

  String toString() => '$parameter(${source}=${source.value})';

  AType withSource(ValueSource newSource) {
    return new TypeParameterAType(newSource, sink, parameter);
  }

  void writeTo(Printer printer) {
    printer.writeTypeParameterReference(parameter);
    if (source.value.canBeNull) {
      printer.write('?');
    }
  }
}

abstract class ATypeVisitor {
  visitInterfaceAType(InterfaceAType type);
  visitFunctionAType(FunctionAType type);
  visitFunctionTypeParameterAType(FunctionTypeParameterAType type);
  visitBottomAType(BottomAType type);
  visitTypeParameterAType(TypeParameterAType type);
}
