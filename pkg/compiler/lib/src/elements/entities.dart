// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library entities;

import '../common.dart';

/// Abstract interface for entities.
///
/// Implement this directly if the entity is not a Dart language entity.
/// Entities defined within the Dart language should implement [Element].
///
/// For instance, the JavaScript backend need to create synthetic variables for
/// calling intercepted classes and such variables do not correspond to an
/// entity in the Dart source code nor in the terminology of the Dart language
/// and should therefore implement [Entity] directly.
abstract class Entity implements Spannable {
  String get name;
}

/// Stripped down super interface for library like entities.
///
/// Currently only [LibraryElement] but later also kernel based Dart classes
/// and/or Dart-in-JS classes.
abstract class LibraryEntity extends Entity {
  /// Return the canonical uri that identifies this library.
  Uri get canonicalUri;
}

/// Stripped down super interface for class like entities.
///
/// Currently only [ClassElement] but later also kernel based Dart classes
/// and/or Dart-in-JS classes.
abstract class ClassEntity extends Entity {
  /// If this is a normal class, the enclosing library for this class. If this
  /// is a closure class, the enclosing class of the closure for which it was
  /// created.
  LibraryEntity get library;

  /// Whether this is a synthesized class for a closurized method or local
  /// function.
  bool get isClosure;

  /// Whether this is an abstract class.
  bool get isAbstract;
}

abstract class TypeVariableEntity extends Entity {
  /// The class or generic method that declared this type variable.
  Entity get typeDeclaration;

  /// The index of this type variable in the type variables of its
  /// [typeDeclaration].
  int get index;
}

/// Stripped down super interface for member like entities, that is,
/// constructors, methods, fields etc.
///
/// Currently only [MemberElement] but later also kernel based Dart members
/// and/or Dart-in-JS properties.
abstract class MemberEntity extends Entity {
  /// Whether this is a member of a library.
  bool get isTopLevel;

  /// Whether this is a static member of a class.
  bool get isStatic;

  /// Whether this is an instance member of a class.
  bool get isInstanceMember;

  /// Whether this is a constructor.
  bool get isConstructor;

  /// Whether this is a field.
  bool get isField;

  /// Whether this is a normal method (neither constructor, getter or setter)
  /// or operator method.
  bool get isFunction;

  /// Whether this is a getter.
  bool get isGetter;

  /// Whether this is a setter.
  bool get isSetter;

  /// Whether this member is assignable, i.e. a non-final, non-const field.
  bool get isAssignable;

  /// Whether this member is constant, i.e. a constant field or constructor.
  bool get isConst;

  /// Whether this member is abstract, i.e. an abstract method, getter or
  /// setter.
  bool get isAbstract;

  /// The enclosing class if this is a constructor, instance member or
  /// static member of a class.
  ClassEntity get enclosingClass;

  /// The enclosing library if this is a library member, otherwise the
  /// enclosing library of the [enclosingClass].
  LibraryEntity get library;
}

/// Stripped down super interface for field like entities.
///
/// Currently only [FieldElement] but later also kernel based Dart fields
/// and/or Dart-in-JS field-like properties.
abstract class FieldEntity extends MemberEntity {}

/// Stripped down super interface for function like entities.
///
/// Currently only [MethodElement] but later also kernel based Dart constructors
/// and methods and/or Dart-in-JS function-like properties.
abstract class FunctionEntity extends MemberEntity {
  /// Whether this function is external, i.e. the body is not defined in terms
  /// of Dart code.
  bool get isExternal;

  /// The structure of the function parameters.
  ParameterStructure get parameterStructure;
}

/// Stripped down super interface for constructor like entities.
///
/// Currently only [ConstructorElement] but later also kernel based Dart
/// constructors and/or Dart-in-JS constructor-like properties.
// TODO(johnniwinther): Remove factory constructors from the set of
// constructors.
abstract class ConstructorEntity extends FunctionEntity {
  /// Whether this is a generative constructor, possibly redirecting.
  bool get isGenerativeConstructor;

  /// Whether this is a factory constructor, possibly redirecting.
  bool get isFactoryConstructor;
}

/// An entity that defines a local entity (memory slot) in generated code.
///
/// Parameters, local variables and local functions (can) define local entity
/// and thus implement [Local] through [LocalElement]. For non-element locals,
/// like `this` and boxes, specialized [Local] classes are created.
///
/// Type variables can introduce locals in factories and constructors
/// but since one type variable can introduce different locals in different
/// factories and constructors it is not itself a [Local] but instead
/// a non-element [Local] is created through a specialized class.
// TODO(johnniwinther): Should [Local] have `isAssignable` or `type`?
abstract class Local extends Entity {
  /// The context in which this local is defined.
  Entity get executableContext;

  /// The outermost member that contains this element.
  ///
  /// For top level, static or instance members, the member context is the
  /// element itself. For parameters, local variables and nested closures, the
  /// member context is the top level, static or instance member in which it is
  /// defined.
  MemberEntity get memberContext;
}

/// The structure of function parameters.
class ParameterStructure {
  /// The number of required (positional) parameters.
  final int requiredParameters;

  /// The number of positional parameters.
  final int positionalParameters;

  /// The named parameters sorted alphabetically.
  final List<String> namedParameters;

  const ParameterStructure(
      this.requiredParameters, this.positionalParameters, this.namedParameters);

  const ParameterStructure.getter() : this(0, 0, const <String>[]);

  const ParameterStructure.setter() : this(1, 1, const <String>[]);

  /// The number of optional parameters (positional or named).
  int get optionalParameters =>
      positionalParameters - requiredParameters + namedParameters.length;
}
