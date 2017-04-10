// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.augmented_type;

import '../../ast.dart';
import '../../text/printable.dart';
import '../storage_location.dart';
import '../value.dart';
import 'constraint_builder.dart';
import 'constraint_extractor.dart';
import 'package:kernel/core_types.dart';
import 'substitution.dart';
import 'value_sink.dart';
import 'value_source.dart';

class ASupertype implements Printable {
  final Class classNode;
  final List<AType> typeArguments;

  ASupertype(this.classNode, this.typeArguments);

  void printTo(Printer printer) {
    printer.writeClassReference(classNode);
    if (typeArguments.isNotEmpty) {
      printer.writeSymbol('<');
      printer.writeList(typeArguments, (AType argument) {
        argument.printTo(printer);
      });
      printer.writeSymbol('>');
    }
  }

  String toString() => Printable.show(this);
}

class SubtypingScope {
  final ConstraintBuilder builder;
  final TypeParameterScope scope;
  final CoreTypes coreTypes;

  ValueLattice get lattice => builder.lattice;

  SubtypingScope(this.builder, this.scope, this.coreTypes);
}

abstract class AType implements Printable {
  /// Describes the abstract values one may obtain by reading from a storage
  /// location with this type.
  ///
  /// This is typically a [Value] or a [StorageLocation], depending on whether
  /// the abstract value is statically known, or is a symbolic value determined
  /// by the constraint solver.
  final ValueSource source;

  /// Describes the effects of assigning a value into a storage location with
  /// this type.
  ///
  /// This is typically a [StorageLocation], denoting an abstract storage
  /// location into which values should be recorded.
  ///
  /// Alternatives are [NowhereSink] that ignores incoming values and
  /// [UnassignableSink] that throws an exception because the type should never
  /// occur as a left-hand value (e.g. it is an error to try to use the
  /// "this type" as a sink).
  ///
  /// For variables, fields, parameters, return types, and allocation-site
  /// type arguments, this equals the [source].  When a type occurs as type
  /// argument to an interface type, it represents a type bound, and then the
  /// source and sinks are separate [StorageLocation] values.
  final ValueSink sink;

  AType(this.source, this.sink) {
    assert(source != null);
    assert(sink != null);
  }

  accept(ATypeVisitor visitor);

  AType substitute(Substitution substitution, int shift);

  /// Returns a copy of this type with its value source replaced.
  AType withSource(ValueSource source);

  /// True if this type or any of its subterms match [predicate].
  bool containsAny(bool predicate(AType type)) => predicate(this);

  bool get containsFunctionTypeParameter =>
      containsAny((t) => t is FunctionTypeParameterAType);

  /// True if this contains no type parameters, other than those in [scope].
  bool isClosed([Iterable<TypeParameter> scope = const []]) {
    return !containsAny(
        (t) => t is TypeParameterAType && !scope.contains(t.parameter));
  }

  static bool listContainsAny(
      Iterable<AType> types, bool predicate(AType type)) {
    return types.any((t) => t.containsAny(predicate));
  }

  static List<AType> substituteList(
      List<AType> types, Substitution substitution, int shift) {
    if (types.isEmpty) return const <AType>[];
    return types
        .map((t) => t.substitute(substitution, shift))
        .toList(growable: false);
  }

  String toString() => Printable.show(this);
}

class InterfaceAType extends AType {
  final Class classNode;
  final List<AType> typeArguments;

  InterfaceAType(
      ValueSource source, ValueSink sink, this.classNode, this.typeArguments)
      : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitInterfaceAType(this);

  bool containsAny(bool predicate(AType type)) =>
      predicate(this) || AType.listContainsAny(typeArguments, predicate);

  AType substitute(Substitution substitution, int shift) {
    return new InterfaceAType(source, sink, classNode,
        AType.substituteList(typeArguments, substitution, shift));
  }

  AType withSource(ValueSource source) {
    return new InterfaceAType(source, sink, classNode, typeArguments);
  }

  void printTo(Printer printer) {
    Value value = source.value;
    value.printTo(printer);
    if (value.baseClass != classNode) {
      printer.writeSymbol('&');
      printer.writeClassReference(classNode);
    }
    if (typeArguments.isNotEmpty) {
      printer.writeSymbol('<');
      printer.writeList(typeArguments, (AType bound) {
        bound.printTo(printer);
        var sink = bound.sink;
        if (sink is StorageLocation) {
          printer.writeSymbol('/');
          if (!sink.value.isBottom()) {
            sink.value.printTo(printer);
          }
        }
      });
      printer.writeSymbol('>');
    }
  }
}

class FunctionAType extends AType {
  final List<AType> typeParameterBounds;
  final int requiredParameterCount;
  final List<AType> positionalParameters;
  final List<String> namedParameterNames;
  final List<AType> namedParameters;
  final AType returnType;

  FunctionAType(
      ValueSource source,
      ValueSink sink,
      this.typeParameterBounds,
      this.requiredParameterCount,
      this.positionalParameters,
      this.namedParameterNames,
      this.namedParameters,
      this.returnType)
      : super(source, sink) {
    assert(!typeParameterBounds.contains(null));
    assert(requiredParameterCount != null);
    assert(!positionalParameters.contains(null));
    assert(!namedParameterNames.contains(null));
    assert(!namedParameters.contains(null));
    assert(returnType != null);
  }

  accept(ATypeVisitor visitor) => visitor.visitFunctionAType(this);

  bool containsAny(bool predicate(AType type)) {
    return predicate(this) ||
        AType.listContainsAny(typeParameterBounds, predicate) ||
        AType.listContainsAny(positionalParameters, predicate) ||
        AType.listContainsAny(namedParameters, predicate) ||
        returnType.containsAny(predicate);
  }

  FunctionAType substitute(Substitution substitution, int shift) {
    shift += typeParameterBounds.length;
    return new FunctionAType(
        source,
        sink,
        AType.substituteList(typeParameterBounds, substitution, shift),
        requiredParameterCount,
        AType.substituteList(positionalParameters, substitution, shift),
        namedParameterNames,
        AType.substituteList(namedParameters, substitution, shift),
        returnType.substitute(substitution, shift));
  }

  FunctionAType instantiate(List<AType> arguments) {
    assert(arguments.length == typeParameterBounds.length);
    var substitution = Substitution.instantiate(arguments);
    return new FunctionAType(
        source,
        sink,
        const [],
        requiredParameterCount,
        AType.substituteList(positionalParameters, substitution, 0),
        namedParameterNames,
        AType.substituteList(namedParameters, substitution, 0),
        returnType.substitute(substitution, 0));
  }

  AType withSource(ValueSource source) {
    return new FunctionAType(
        source,
        sink,
        typeParameterBounds,
        requiredParameterCount,
        positionalParameters,
        namedParameterNames,
        namedParameters,
        returnType);
  }

  void printTo(Printer printer) {
    Value value = source.value;
    if (value.canBeNull) {
      printer.write('?');
    }
    if (typeParameterBounds.isNotEmpty) {
      printer.writeSymbol('<');
      printer.writeList(typeParameterBounds, (AType type) {
        type.printTo(printer);
      });
      printer.writeSymbol('>');
    }
    printer.writeSymbol('(');
    if (positionalParameters.length > 0) {
      printer.writeList(positionalParameters.take(requiredParameterCount),
          (AType p) => p.printTo(printer));
      if (requiredParameterCount < positionalParameters.length) {
        if (requiredParameterCount > 0) {
          printer.writeComma();
        }
        printer.writeSymbol('[');
        printer.writeList(positionalParameters.skip(requiredParameterCount),
            (AType p) => p.printTo(printer));
        printer.writeSymbol(']');
      }
    }
    printer.writeSymbol(') => ');
    returnType.printTo(printer);
  }

  int indexOfNamedParameter(String name) {
    return namedParameterNames.indexOf(name);
  }

  AType getNamedParameterType(String name) {
    int index = indexOfNamedParameter(name);
    return index == -1 ? null : namedParameters[index];
  }
}

/// Reference to a type parameter declared on an enclosing function type.
///
/// Note that type parameters declared on classes and functions (but not
/// *function types*) are referenced using [TypeParameterAType].
///
/// Type parameters on function types are encoded using [De Brujin indices][1].
///
/// This example shows how a type involving nested generic function types is
/// represented:
///
///     type:  <T>(T) => <G>(G, T) => G
///     index:     0         0  1     0
///
/// [1]: https://en.wikipedia.org/wiki/De_Bruijn_index
class FunctionTypeParameterAType extends AType {
  final int index;

  FunctionTypeParameterAType(ValueSource source, ValueSink sink, this.index)
      : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitFunctionTypeParameterAType(this);

  AType substitute(Substitution substitution, int shift) {
    return substitution.getInstantiation(this, shift) ?? this;
  }

  AType withSource(ValueSource source) {
    return new FunctionTypeParameterAType(source, sink, index);
  }

  void printTo(Printer printer) {
    printer.writeWord('FunctionTypeParameter($index)');
  }
}

/// Potentially nullable or true bottom.
class BottomAType extends AType {
  BottomAType(ValueSource source, ValueSink sink) : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitBottomAType(this);

  BottomAType substitute(Substitution substitution, int shift) => this;

  static final BottomAType nonNullable =
      new BottomAType(Value.bottom, ValueSink.nowhere);
  static final BottomAType nullable =
      new BottomAType(Value.null_, ValueSink.nowhere);

  AType withSource(ValueSource source) {
    return new BottomAType(source, sink);
  }

  void printTo(Printer printer) {
    source.value.printTo(printer);
  }
}

class TypeParameterAType extends AType {
  final TypeParameter parameter;

  TypeParameterAType(ValueSource source, ValueSink sink, this.parameter)
      : super(source, sink);

  accept(ATypeVisitor visitor) => visitor.visitTypeParameterAType(this);

  AType substitute(Substitution substitution, int shift) {
    return substitution.getSubstitute(this) ?? this;
  }

  AType withSource(ValueSource newSource) {
    return new TypeParameterAType(newSource, sink, parameter);
  }

  void printTo(Printer printer) {
    printer.writeTypeParameterReference(parameter);
    if (source.value.canBeNull) {
      printer.write('?');
    }
  }
}

abstract class ATypeVisitor<T> {
  T visitInterfaceAType(InterfaceAType type);
  T visitFunctionAType(FunctionAType type);
  T visitFunctionTypeParameterAType(FunctionTypeParameterAType type);
  T visitBottomAType(BottomAType type);
  T visitTypeParameterAType(TypeParameterAType type);
}
