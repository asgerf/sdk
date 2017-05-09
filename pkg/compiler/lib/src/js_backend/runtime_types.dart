// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of js_backend.backend;

/// For each class, stores the possible class subtype tests that could succeed.
abstract class TypeChecks {
  /// Get the set of checks required for class [element].
  Iterable<TypeCheck> operator [](ClassElement element);

  /// Get the iterable for all classes that need type checks.
  Iterable<ClassElement> get classes;
}

typedef jsAst.Expression OnVariableCallback(
    ResolutionTypeVariableType variable);
typedef bool ShouldEncodeTypedefCallback(ResolutionTypedefType variable);

/// Interface for the classes and methods that need runtime types.
abstract class RuntimeTypesNeed {
  bool classNeedsRti(ClassElement cls);
  bool classNeedsRtiField(ClassElement cls);
  bool methodNeedsRti(MethodElement function);
  bool localFunctionNeedsRti(LocalFunctionElement function);
  bool classUsesTypeVariableExpression(ClassElement cls);
}

/// Interface for computing classes and methods that need runtime types.
abstract class RuntimeTypesNeedBuilder {
  /// Registers that [cls] contains a type variable literal.
  void registerClassUsingTypeVariableExpression(ClassEntity cls);

  /// Registers that if [element] needs reified runtime type information then so
  /// does [dependency].
  ///
  /// For instance:
  ///
  ///     class A<T> {
  ///       m() => new B<T>();
  ///     }
  ///     class B<T> {}
  ///     main() => new A<String>().m() is B<int>;
  ///
  /// Here `A` need reified runtime type information because `B` needs it in
  /// order to generate the check against `B<int>`.
  void registerRtiDependency(ClassEntity element, ClassEntity dependency);

  /// Computes the [RuntimeTypesNeed] for the data registered with this builder.
  RuntimeTypesNeed computeRuntimeTypesNeed(
      ResolutionWorldBuilder resolutionWorldBuilder,
      ClosedWorld closedWorld,
      DartTypes types,
      CommonElements commonElements,
      BackendUsage backendUsage,
      {bool enableTypeAssertions});
}

/// Interface for the needed runtime type checks.
abstract class RuntimeTypesChecks {
  /// Returns the required runtime type checks.
  TypeChecks get requiredChecks;

  /// Return all classes that are referenced in the type of the function, i.e.,
  /// in the return type or the argument types.
  Set<ClassElement> getReferencedClasses(ResolutionFunctionType type);

  /// Return all classes that are uses a type arguments.
  Set<ClassElement> getRequiredArgumentClasses();
}

/// Interface for computing the needed runtime type checks.
abstract class RuntimeTypesChecksBuilder {
  void registerTypeVariableBoundsSubtypeCheck(
      ResolutionDartType typeArgument, ResolutionDartType bound);

  /// Computes the [RuntimeTypesChecks] for the data in this builder.
  RuntimeTypesChecks computeRequiredChecks();

  /// Compute type arguments of classes that use one of their type variables in
  /// is-checks and add the is-checks that they imply.
  ///
  /// This function must be called after all is-checks have been registered.
  void registerImplicitChecks(
      WorldBuilder worldBuilder, Iterable<ClassElement> classesUsingChecks);
}

/// Interface for computing substitutions need for runtime type checks.
abstract class RuntimeTypesSubstitutions {
  bool isTrivialSubstitution(ClassElement cls, ClassElement check);

  Substitution getSubstitution(ClassElement cls, ClassElement other);

  /// Compute the required type checks and substitutions for the given
  /// instantitated and checked classes.
  TypeChecks computeChecks(
      Set<ClassElement> instantiated, Set<ClassElement> checked);

  Set<ClassElement> getClassesUsedInSubstitutions(TypeChecks checks);

  static bool hasTypeArguments(ResolutionDartType type) {
    if (type is ResolutionInterfaceType) {
      ResolutionInterfaceType interfaceType = type;
      return !interfaceType.treatAsRaw;
    }
    return false;
  }
}

abstract class RuntimeTypesEncoder {
  bool isSimpleFunctionType(ResolutionFunctionType type);

  jsAst.Expression getSignatureEncoding(
      Emitter emitter, ResolutionDartType type, jsAst.Expression this_);

  jsAst.Expression getSubstitutionRepresentation(Emitter emitter,
      List<ResolutionDartType> types, OnVariableCallback onVariable);
  jsAst.Expression getSubstitutionCode(
      Emitter emitter, Substitution substitution);

  /// Returns the JavaScript template to determine at runtime if a type object
  /// is a function type.
  jsAst.Template get templateForIsFunctionType;

  /// Returns the JavaScript template that creates at runtime a new function
  /// type object.
  jsAst.Template get templateForCreateFunctionType;
  jsAst.Name get getFunctionThatReturnsNullName;

  /// Returns a [jsAst.Expression] representing the given [type]. Type variables
  /// are replaced by the [jsAst.Expression] returned by [onVariable].
  jsAst.Expression getTypeRepresentation(
      Emitter emitter, ResolutionDartType type, OnVariableCallback onVariable,
      [ShouldEncodeTypedefCallback shouldEncodeTypedef]);

  String getTypeRepresentationForTypeConstant(ResolutionDartType type);
}

/// Common functionality for [_RuntimeTypesNeedBuilder] and [_RuntimeTypes].
abstract class _RuntimeTypesBase {
  final DartTypes _types;

  // TODO(21969): remove this and analyze instantiated types and factory calls
  // instead to find out which types are instantiated, if finitely many, or if
  // we have to use the more imprecise generic algorithm.
  bool get cannotDetermineInstantiatedTypesPrecisely => true;

  _RuntimeTypesBase(this._types);

  /**
   * Compute type arguments of classes that use one of their type variables in
   * is-checks and add the is-checks that they imply.
   *
   * This function must be called after all is-checks have been registered.
   *
   * TODO(karlklose): move these computations into a function producing an
   * immutable datastructure.
   */
  void registerImplicitChecks(
      WorldBuilder worldBuilder, Iterable<ClassEntity> classesUsingChecks) {
    // If there are no classes that use their variables in checks, there is
    // nothing to do.
    if (classesUsingChecks.isEmpty) return;
    Set<InterfaceType> instantiatedTypes = worldBuilder.instantiatedTypes;
    if (cannotDetermineInstantiatedTypesPrecisely) {
      for (InterfaceType type in instantiatedTypes) {
        do {
          for (DartType argument in type.typeArguments) {
            worldBuilder.registerIsCheck(argument);
          }
          // TODO(johnniwinther): This seems wrong; the type arguments of [type]
          // are not substituted - `List<int>` yields `Iterable<E>` and not
          // `Iterable<int>`.
          type = _types.getSupertype(type.element);
        } while (type != null && !instantiatedTypes.contains(type));
      }
    } else {
      // Find all instantiated types that are a subtype of a class that uses
      // one of its type arguments in an is-check and add the arguments to the
      // set of is-checks.
      // TODO(karlklose): replace this with code that uses a subtype lookup
      // datastructure in the world.
      for (InterfaceType type in instantiatedTypes) {
        for (ClassEntity cls in classesUsingChecks) {
          do {
            // We need the type as instance of its superclass anyway, so we just
            // try to compute the substitution; if the result is [:null:], the
            // classes are not related.
            InterfaceType instance = _types.asInstanceOf(type, cls);
            if (instance == null) break;
            for (DartType argument in instance.typeArguments) {
              worldBuilder.registerIsCheck(argument);
            }
            // TODO(johnniwinther): This seems wrong; the type arguments of
            // [type] are not substituted - `List<int>` yields `Iterable<E>` and
            // not `Iterable<int>`.
            type = _types.getSupertype(type.element);
          } while (type != null && !instantiatedTypes.contains(type));
        }
      }
    }
  }
}

class _RuntimeTypesNeed implements RuntimeTypesNeed {
  final ElementEnvironment _elementEnvironment;
  final BackendUsage _backendUsage;
  final Set<ClassEntity> classesNeedingRti;
  final Set<FunctionEntity> methodsNeedingRti;
  final Set<Local> localFunctionsNeedingRti;

  /// The set of classes that use one of their type variables as expressions
  /// to get the runtime type.
  final Set<ClassEntity> classesUsingTypeVariableExpression;

  _RuntimeTypesNeed(
      this._elementEnvironment,
      this._backendUsage,
      this.classesNeedingRti,
      this.methodsNeedingRti,
      this.localFunctionsNeedingRti,
      this.classesUsingTypeVariableExpression);

  bool checkClass(ClassEntity cls) => true;

  bool classNeedsRti(ClassEntity cls) {
    assert(checkClass(cls));
    if (_backendUsage.isRuntimeTypeUsed) return true;
    return classesNeedingRti.contains(cls);
  }

  bool classNeedsRtiField(ClassEntity cls) {
    assert(checkClass(cls));
    if (!_elementEnvironment.isGenericClass(cls)) return false;
    if (_backendUsage.isRuntimeTypeUsed) return true;
    return classesNeedingRti.contains(cls);
  }

  bool methodNeedsRti(MethodElement function) {
    return methodsNeedingRti.contains(function) ||
        _backendUsage.isRuntimeTypeUsed;
  }

  bool localFunctionNeedsRti(LocalFunctionElement function) {
    return localFunctionsNeedingRti.contains(function) ||
        _backendUsage.isRuntimeTypeUsed;
  }

  @override
  bool classUsesTypeVariableExpression(ClassEntity cls) {
    return classesUsingTypeVariableExpression.contains(cls);
  }
}

class _ResolutionRuntimeTypesNeed extends _RuntimeTypesNeed {
  _ResolutionRuntimeTypesNeed(
      ElementEnvironment elementEnvironment,
      BackendUsage backendUsage,
      Set<ClassEntity> classesNeedingRti,
      Set<FunctionEntity> methodsNeedingRti,
      Set<Local> localFunctionsNeedingRti,
      Set<ClassEntity> classesUsingTypeVariableExpression)
      : super(
            elementEnvironment,
            backendUsage,
            classesNeedingRti,
            methodsNeedingRti,
            localFunctionsNeedingRti,
            classesUsingTypeVariableExpression);

  bool checkClass(ClassElement cls) => cls.isDeclaration;
}

class RuntimeTypesNeedBuilderImpl extends _RuntimeTypesBase
    implements RuntimeTypesNeedBuilder {
  final ElementEnvironment _elementEnvironment;

  final Map<ClassEntity, Set<ClassEntity>> rtiDependencies =
      <ClassEntity, Set<ClassEntity>>{};

  final Set<ClassEntity> classesUsingTypeVariableExpression =
      new Set<ClassEntity>();

  RuntimeTypesNeedBuilderImpl(this._elementEnvironment, DartTypes types)
      : super(types);

  bool checkClass(ClassEntity cls) => true;

  @override
  void registerClassUsingTypeVariableExpression(ClassEntity cls) {
    classesUsingTypeVariableExpression.add(cls);
  }

  @override
  void registerRtiDependency(ClassEntity element, ClassEntity dependency) {
    // We're not dealing with typedef for now.
    assert(element != null);
    Set<ClassEntity> classes =
        rtiDependencies.putIfAbsent(element, () => new Set<ClassEntity>());
    classes.add(dependency);
  }

  @override
  RuntimeTypesNeed computeRuntimeTypesNeed(
      ResolutionWorldBuilder resolutionWorldBuilder,
      ClosedWorld closedWorld,
      DartTypes types,
      CommonElements commonElements,
      BackendUsage backendUsage,
      {bool enableTypeAssertions}) {
    Set<ClassEntity> classesNeedingRti = new Set<ClassEntity>();
    Set<FunctionEntity> methodsNeedingRti = new Set<FunctionEntity>();
    Set<Local> localFunctionsNeedingRti = new Set<Local>();

    // Find the classes that need runtime type information. Such
    // classes are:
    // (1) used in a is check with type variables,
    // (2) dependencies of classes in (1),
    // (3) subclasses of (2) and (3).
    void potentiallyAddForRti(ClassEntity cls) {
      assert(checkClass(cls));
      if (!_elementEnvironment.isGenericClass(cls)) return;
      if (classesNeedingRti.contains(cls)) return;
      classesNeedingRti.add(cls);

      // TODO(ngeoffray): This should use subclasses, not subtypes.
      closedWorld.forEachStrictSubtypeOf(cls, (ClassEntity sub) {
        potentiallyAddForRti(sub);
      });

      Set<ClassEntity> dependencies = rtiDependencies[cls];
      if (dependencies != null) {
        dependencies.forEach((ClassEntity other) {
          potentiallyAddForRti(other);
        });
      }
    }

    Set<ClassEntity> classesUsingTypeVariableTests = new Set<ClassEntity>();
    resolutionWorldBuilder.isChecks.forEach((DartType type) {
      if (type.isTypeVariable) {
        TypeVariableType typeVariableType = type;
        TypeVariableEntity variable = typeVariableType.element;
        // GENERIC_METHODS: When generic method support is complete enough to
        // include a runtime value for method type variables, this may need to
        // be updated: It simply ignores method type arguments.
        if (variable.typeDeclaration is ClassEntity) {
          classesUsingTypeVariableTests.add(variable.typeDeclaration);
        }
      }
    });
    // Add is-checks that result from classes using type variables in checks.
    registerImplicitChecks(
        resolutionWorldBuilder, classesUsingTypeVariableTests);
    // Add the rti dependencies that are implicit in the way the backend
    // generates code: when we create a new [List], we actually create
    // a JSArray in the backend and we need to add type arguments to
    // the calls of the list constructor whenever we determine that
    // JSArray needs type arguments.
    // TODO(karlklose): make this dependency visible from code.
    if (commonElements.jsArrayClass != null) {
      ClassEntity listClass = commonElements.listClass;
      registerRtiDependency(commonElements.jsArrayClass, listClass);
    }

    // Check local functions and closurized members.
    void checkClosures({DartType potentialSubtypeOf}) {
      bool checkFunctionType(FunctionType functionType) {
        ClassEntity contextClass = Types.getClassContext(functionType);
        if (contextClass != null &&
            (potentialSubtypeOf == null ||
                types.isPotentialSubtype(functionType, potentialSubtypeOf))) {
          potentiallyAddForRti(contextClass);
          return true;
        }
        return false;
      }

      for (Local function
          in resolutionWorldBuilder.localFunctionsWithFreeTypeVariables) {
        if (checkFunctionType(
            _elementEnvironment.getLocalFunctionType(function))) {
          localFunctionsNeedingRti.add(function);
        }
      }
      for (FunctionEntity function
          in resolutionWorldBuilder.closurizedMembersWithFreeTypeVariables) {
        if (checkFunctionType(_elementEnvironment.getFunctionType(function))) {
          methodsNeedingRti.add(function);
        }
      }
    }

    // Compute the set of all classes and methods that need runtime type
    // information.
    resolutionWorldBuilder.isChecks.forEach((DartType type) {
      if (type.isInterfaceType) {
        ResolutionInterfaceType itf = type;
        if (!itf.treatAsRaw) {
          potentiallyAddForRti(itf.element);
        }
      } else {
        ClassEntity contextClass = Types.getClassContext(type);
        if (contextClass != null) {
          // [type] contains type variables (declared in [contextClass]) if
          // [contextClass] is non-null. This handles checks against type
          // variables and function types containing type variables.
          potentiallyAddForRti(contextClass);
        }
        if (type.isFunctionType) {
          checkClosures(potentialSubtypeOf: type);
        }
      }
    });
    if (enableTypeAssertions) {
      checkClosures();
    }

    // Add the classes that need RTI because they use a type variable as
    // expression.
    classesUsingTypeVariableExpression.forEach(potentiallyAddForRti);

    return _createRuntimeTypesNeed(
        _elementEnvironment,
        backendUsage,
        classesNeedingRti,
        methodsNeedingRti,
        localFunctionsNeedingRti,
        classesUsingTypeVariableExpression);
  }

  RuntimeTypesNeed _createRuntimeTypesNeed(
      ElementEnvironment elementEnvironment,
      BackendUsage backendUsage,
      Set<ClassEntity> classesNeedingRti,
      Set<FunctionEntity> methodsNeedingRti,
      Set<Local> localFunctionsNeedingRti,
      Set<ClassEntity> classesUsingTypeVariableExpression) {
    return new _RuntimeTypesNeed(
        _elementEnvironment,
        backendUsage,
        classesNeedingRti,
        methodsNeedingRti,
        localFunctionsNeedingRti,
        classesUsingTypeVariableExpression);
  }
}

class ResolutionRuntimeTypesNeedBuilderImpl
    extends RuntimeTypesNeedBuilderImpl {
  ResolutionRuntimeTypesNeedBuilderImpl(
      ElementEnvironment elementEnvironment, DartTypes types)
      : super(elementEnvironment, types);

  bool checkClass(ClassElement cls) => cls.isDeclaration;

  RuntimeTypesNeed _createRuntimeTypesNeed(
      ElementEnvironment elementEnvironment,
      BackendUsage backendUsage,
      Set<ClassEntity> classesNeedingRti,
      Set<FunctionEntity> methodsNeedingRti,
      Set<Local> localFunctionsNeedingRti,
      Set<ClassEntity> classesUsingTypeVariableExpression) {
    return new _ResolutionRuntimeTypesNeed(
        _elementEnvironment,
        backendUsage,
        classesNeedingRti,
        methodsNeedingRti,
        localFunctionsNeedingRti,
        classesUsingTypeVariableExpression);
  }
}

class _RuntimeTypesChecks implements RuntimeTypesChecks {
  final RuntimeTypesSubstitutions substitutions;
  final TypeChecks requiredChecks;
  final Set<ClassElement> directlyInstantiatedArguments;
  final Set<ClassElement> checkedArguments;

  _RuntimeTypesChecks(this.substitutions, this.requiredChecks,
      this.directlyInstantiatedArguments, this.checkedArguments);

  @override
  Set<ClassElement> getRequiredArgumentClasses() {
    Set<ClassElement> requiredArgumentClasses = new Set<ClassElement>.from(
        substitutions.getClassesUsedInSubstitutions(requiredChecks));
    return requiredArgumentClasses
      ..addAll(directlyInstantiatedArguments)
      ..addAll(checkedArguments);
  }

  @override
  Set<ClassElement> getReferencedClasses(ResolutionFunctionType type) {
    FunctionArgumentCollector collector = new FunctionArgumentCollector();
    collector.collect(type);
    return collector.classes;
  }
}

class _RuntimeTypes extends _RuntimeTypesBase
    implements RuntimeTypesChecksBuilder, RuntimeTypesSubstitutions {
  final Compiler compiler;

  // The set of type arguments tested against type variable bounds.
  final Set<ResolutionDartType> checkedTypeArguments;
  // The set of tested type variable bounds.
  final Set<ResolutionDartType> checkedBounds;

  TypeChecks cachedRequiredChecks;

  JavaScriptBackend get backend => compiler.backend;

  bool rtiChecksBuilderClosed = false;

  _RuntimeTypes(Compiler compiler)
      : this.compiler = compiler,
        checkedTypeArguments = new Set<ResolutionDartType>(),
        checkedBounds = new Set<ResolutionDartType>(),
        super(compiler.types);

  Set<ClassElement> directlyInstantiatedArguments;
  Set<ClassElement> allInstantiatedArguments;
  Set<ClassElement> checkedArguments;

  @override
  void registerTypeVariableBoundsSubtypeCheck(
      ResolutionDartType typeArgument, ResolutionDartType bound) {
    checkedTypeArguments.add(typeArgument);
    checkedBounds.add(bound);
  }

  @override
  TypeChecks computeChecks(
      Set<ClassEntity> instantiated, Set<ClassEntity> checked) {
    // Run through the combination of instantiated and checked
    // arguments and record all combination where the element of a checked
    // argument is a superclass of the element of an instantiated type.
    TypeCheckMapping result = new TypeCheckMapping();
    for (ClassElement element in instantiated) {
      if (checked.contains(element)) {
        result.add(element, element, null);
      }
      // Find all supertypes of [element] in [checkedArguments] and add checks
      // and precompute the substitutions for them.
      assert(invariant(element, element.allSupertypes != null,
          message: 'Supertypes have not been computed for $element.'));
      for (ResolutionInterfaceType supertype in element.allSupertypes) {
        ClassElement superelement = supertype.element;
        if (checked.contains(superelement)) {
          Substitution substitution =
              computeSubstitution(element, superelement);
          result.add(element, superelement, substitution);
        }
      }
    }
    return result;
  }

  RuntimeTypesChecks computeRequiredChecks() {
    Set<ResolutionDartType> isChecks = compiler.codegenWorldBuilder.isChecks;
    // These types are needed for is-checks against function types.
    Set<ResolutionDartType> instantiatedTypesAndClosures =
        computeInstantiatedTypesAndClosures(compiler.codegenWorldBuilder);
    computeInstantiatedArguments(instantiatedTypesAndClosures, isChecks);
    computeCheckedArguments(instantiatedTypesAndClosures, isChecks);
    cachedRequiredChecks =
        computeChecks(allInstantiatedArguments, checkedArguments);
    rtiChecksBuilderClosed = true;
    return new _RuntimeTypesChecks(this, cachedRequiredChecks,
        directlyInstantiatedArguments, checkedArguments);
  }

  Set<ResolutionDartType> computeInstantiatedTypesAndClosures(
      CodegenWorldBuilder worldBuilder) {
    Set<ResolutionDartType> instantiatedTypes =
        new Set<ResolutionDartType>.from(worldBuilder.instantiatedTypes);
    for (ResolutionInterfaceType instantiatedType
        in worldBuilder.instantiatedTypes) {
      ResolutionFunctionType callType = instantiatedType.callType;
      if (callType != null) {
        instantiatedTypes.add(callType);
      }
    }
    for (FunctionElement element in worldBuilder.staticFunctionsNeedingGetter) {
      instantiatedTypes.add(element.type);
    }
    // TODO(johnniwinther): We should get this information through the
    // [neededClasses] computed in the emitter instead of storing it and pulling
    // it from resolution, but currently it would introduce a cyclic dependency
    // between [computeRequiredChecks] and [computeNeededClasses].
    for (MethodElement element
        in compiler.resolutionWorldBuilder.closurizedMembers) {
      instantiatedTypes.add(element.type);
    }
    return instantiatedTypes;
  }

  /**
   * Collects all types used in type arguments of instantiated types.
   *
   * This includes type arguments used in supertype relations, because we may
   * have a type check against this supertype that includes a check against
   * the type arguments.
   */
  void computeInstantiatedArguments(Set<ResolutionDartType> instantiatedTypes,
      Set<ResolutionDartType> isChecks) {
    ArgumentCollector superCollector = new ArgumentCollector();
    ArgumentCollector directCollector = new ArgumentCollector();
    FunctionArgumentCollector functionArgumentCollector =
        new FunctionArgumentCollector();

    // We need to add classes occurring in function type arguments, like for
    // instance 'I' for [: o is C<f> :] where f is [: typedef I f(); :].
    void collectFunctionTypeArguments(Iterable<ResolutionDartType> types) {
      for (ResolutionDartType type in types) {
        functionArgumentCollector.collect(type);
      }
    }

    collectFunctionTypeArguments(isChecks);
    collectFunctionTypeArguments(checkedBounds);

    void collectTypeArguments(Iterable<ResolutionDartType> types,
        {bool isTypeArgument: false}) {
      for (ResolutionDartType type in types) {
        directCollector.collect(type, isTypeArgument: isTypeArgument);
        if (type.isInterfaceType) {
          ClassElement cls = type.element;
          for (ResolutionInterfaceType supertype in cls.allSupertypes) {
            superCollector.collect(supertype, isTypeArgument: isTypeArgument);
          }
        }
      }
    }

    collectTypeArguments(instantiatedTypes);
    collectTypeArguments(checkedTypeArguments, isTypeArgument: true);

    for (ClassElement cls in superCollector.classes.toList()) {
      for (ResolutionInterfaceType supertype in cls.allSupertypes) {
        superCollector.collect(supertype);
      }
    }

    directlyInstantiatedArguments = directCollector.classes
      ..addAll(functionArgumentCollector.classes);
    allInstantiatedArguments = superCollector.classes
      ..addAll(directlyInstantiatedArguments);
  }

  /// Collects all type arguments used in is-checks.
  void computeCheckedArguments(Set<ResolutionDartType> instantiatedTypes,
      Set<ResolutionDartType> isChecks) {
    ArgumentCollector collector = new ArgumentCollector();
    FunctionArgumentCollector functionArgumentCollector =
        new FunctionArgumentCollector();

    // We need to add types occurring in function type arguments, like for
    // instance 'J' for [: (J j) {} is f :] where f is
    // [: typedef void f(I i); :] and 'J' is a subtype of 'I'.
    void collectFunctionTypeArguments(Iterable<ResolutionDartType> types) {
      for (ResolutionDartType type in types) {
        functionArgumentCollector.collect(type);
      }
    }

    collectFunctionTypeArguments(instantiatedTypes);
    collectFunctionTypeArguments(checkedTypeArguments);

    void collectTypeArguments(Iterable<ResolutionDartType> types,
        {bool isTypeArgument: false}) {
      for (ResolutionDartType type in types) {
        collector.collect(type, isTypeArgument: isTypeArgument);
      }
    }

    collectTypeArguments(isChecks);
    collectTypeArguments(checkedBounds, isTypeArgument: true);

    checkedArguments = collector.classes
      ..addAll(functionArgumentCollector.classes);
  }

  @override
  Set<ClassElement> getClassesUsedInSubstitutions(TypeChecks checks) {
    Set<ClassElement> instantiated = new Set<ClassElement>();
    ArgumentCollector collector = new ArgumentCollector();
    for (ClassElement target in checks.classes) {
      instantiated.add(target);
      for (TypeCheck check in checks[target]) {
        Substitution substitution = check.substitution;
        if (substitution != null) {
          collector.collectAll(substitution.arguments);
        }
      }
    }
    return instantiated..addAll(collector.classes);

    // TODO(sra): This computation misses substitutions for reading type
    // parameters.
  }

  // TODO(karlklose): maybe precompute this value and store it in typeChecks?
  @override
  bool isTrivialSubstitution(ClassElement cls, ClassElement check) {
    if (cls.isClosure) {
      // TODO(karlklose): handle closures.
      return true;
    }

    // If there are no type variables or the type is the same, we do not need
    // a substitution.
    if (check.typeVariables.isEmpty || cls == check) {
      return true;
    }

    ResolutionInterfaceType originalType = cls.thisType;
    ResolutionInterfaceType type = originalType.asInstanceOf(check);
    // [type] is not a subtype of [check]. we do not generate a check and do not
    // need a substitution.
    if (type == null) return true;

    // Run through both lists of type variables and check if the type variables
    // are identical at each position. If they are not, we need to calculate a
    // substitution function.
    List<ResolutionDartType> variables = cls.typeVariables;
    List<ResolutionDartType> arguments = type.typeArguments;
    if (variables.length != arguments.length) {
      return false;
    }
    for (int index = 0; index < variables.length; index++) {
      if (variables[index].element != arguments[index].element) {
        return false;
      }
    }
    return true;
  }

  @override
  Substitution getSubstitution(ClassElement cls, ClassElement other) {
    // Look for a precomputed check.
    for (TypeCheck check in cachedRequiredChecks[cls]) {
      if (check.cls == other) {
        return check.substitution;
      }
    }
    // There is no precomputed check for this pair (because the check is not
    // done on type arguments only.  Compute a new substitution.
    return computeSubstitution(cls, other);
  }

  Substitution computeSubstitution(ClassElement cls, ClassElement check,
      {bool alwaysGenerateFunction: false}) {
    if (isTrivialSubstitution(cls, check)) return null;

    // Unnamed mixin application classes do not need substitutions, because they
    // are never instantiated and their checks are overwritten by the class that
    // they are mixed into.
    ResolutionInterfaceType type = cls.thisType;
    ResolutionInterfaceType target = type.asInstanceOf(check);
    List<ResolutionDartType> typeVariables = cls.typeVariables;
    if (typeVariables.isEmpty && !alwaysGenerateFunction) {
      return new Substitution.list(target.typeArguments);
    } else {
      return new Substitution.function(target.typeArguments, typeVariables);
    }
  }
}

class _RuntimeTypesEncoder implements RuntimeTypesEncoder {
  final Namer namer;
  final CommonElements commonElements;
  final TypeRepresentationGenerator _representationGenerator;

  _RuntimeTypesEncoder(this.namer, this.commonElements)
      : _representationGenerator = new TypeRepresentationGenerator(namer);

  @override
  bool isSimpleFunctionType(ResolutionFunctionType type) {
    if (!type.returnType.isDynamic) return false;
    if (!type.optionalParameterTypes.isEmpty) return false;
    if (!type.namedParameterTypes.isEmpty) return false;
    for (ResolutionDartType parameter in type.parameterTypes) {
      if (!parameter.isDynamic) return false;
    }
    return true;
  }

  /// Returns the JavaScript template to determine at runtime if a type object
  /// is a function type.
  @override
  jsAst.Template get templateForIsFunctionType {
    return _representationGenerator.templateForIsFunctionType;
  }

  /// Returns the JavaScript template that creates at runtime a new function
  /// type object.
  @override
  jsAst.Template get templateForCreateFunctionType {
    return _representationGenerator.templateForCreateFunctionType;
  }

  @override
  jsAst.Expression getTypeRepresentation(
      Emitter emitter, ResolutionDartType type, OnVariableCallback onVariable,
      [ShouldEncodeTypedefCallback shouldEncodeTypedef]) {
    // GENERIC_METHODS: When generic method support is complete enough to
    // include a runtime value for method type variables this must be updated.
    return _representationGenerator.getTypeRepresentation(emitter,
        type.dynamifyMethodTypeVariableType, onVariable, shouldEncodeTypedef);
  }

  @override
  jsAst.Expression getSubstitutionRepresentation(Emitter emitter,
      List<ResolutionDartType> types, OnVariableCallback onVariable) {
    List<jsAst.Expression> elements = types
        .map((ResolutionDartType type) =>
            getTypeRepresentation(emitter, type, onVariable))
        .toList(growable: false);
    return new jsAst.ArrayInitializer(elements);
  }

  jsAst.Expression getTypeEncoding(Emitter emitter, ResolutionDartType type,
      {bool alwaysGenerateFunction: false}) {
    ClassElement contextClass = Types.getClassContext(type);
    jsAst.Expression onVariable(ResolutionTypeVariableType v) {
      return new jsAst.VariableUse(v.name);
    }

    jsAst.Expression encoding =
        getTypeRepresentation(emitter, type, onVariable);
    if (contextClass == null && !alwaysGenerateFunction) {
      return encoding;
    } else {
      List<String> parameters = const <String>[];
      if (contextClass != null) {
        parameters = contextClass.typeVariables.map((type) {
          return type.name;
        }).toList();
      }
      return js('function(#) { return # }', [parameters, encoding]);
    }
  }

  @override
  jsAst.Expression getSignatureEncoding(
      Emitter emitter, ResolutionDartType type, jsAst.Expression this_) {
    ClassElement contextClass = Types.getClassContext(type);
    jsAst.Expression encoding =
        getTypeEncoding(emitter, type, alwaysGenerateFunction: true);
    if (contextClass != null) {
      jsAst.Name contextName = namer.className(contextClass);
      return js('function () { return #(#, #, #); }', [
        emitter.staticFunctionAccess(commonElements.computeSignature),
        encoding,
        this_,
        js.quoteName(contextName)
      ]);
    } else {
      return encoding;
    }
  }

  /**
   * Compute a JavaScript expression that describes the necessary substitution
   * for type arguments in a subtype test.
   *
   * The result can be:
   *  1) `null`, if no substituted check is necessary, because the
   *     type variables are the same or there are no type variables in the class
   *     that is checked for.
   *  2) A list expression describing the type arguments to be used in the
   *     subtype check, if the type arguments to be used in the check do not
   *     depend on the type arguments of the object.
   *  3) A function mapping the type variables of the object to be checked to
   *     a list expression.
   */
  @override
  jsAst.Expression getSubstitutionCode(
      Emitter emitter, Substitution substitution) {
    jsAst.Expression declaration(ResolutionTypeVariableType variable) {
      return new jsAst.Parameter(getVariableName(variable.name));
    }

    jsAst.Expression use(ResolutionTypeVariableType variable) {
      return new jsAst.VariableUse(getVariableName(variable.name));
    }

    if (substitution.arguments
        .every((ResolutionDartType type) => type.isDynamic)) {
      return emitter.generateFunctionThatReturnsNull();
    } else {
      jsAst.Expression value =
          getSubstitutionRepresentation(emitter, substitution.arguments, use);
      if (substitution.isFunction) {
        Iterable<jsAst.Expression> formals =
            substitution.parameters.map(declaration);
        return js('function(#) { return # }', [formals, value]);
      } else {
        return js('function() { return # }', value);
      }
    }
  }

  String getVariableName(String name) {
    return namer.safeVariableName(name);
  }

  @override
  jsAst.Name get getFunctionThatReturnsNullName =>
      namer.internalGlobal('functionThatReturnsNull');

  @override
  String getTypeRepresentationForTypeConstant(ResolutionDartType type) {
    if (type.isDynamic) return "dynamic";
    String name = namer.uniqueNameForTypeConstantElement(type.element);
    if (!type.element.isClass) return name;
    ResolutionInterfaceType interface = type;
    List<ResolutionDartType> variables = interface.element.typeVariables;
    // Type constants can currently only be raw types, so there is no point
    // adding ground-term type parameters, as they would just be 'dynamic'.
    // TODO(sra): Since the result string is used only in constructing constant
    // names, it would result in more readable names if the final string was a
    // legal JavaScript identifer.
    if (variables.isEmpty) return name;
    String arguments = new List.filled(variables.length, 'dynamic').join(', ');
    return '$name<$arguments>';
  }
}

class TypeRepresentationGenerator implements ResolutionDartTypeVisitor {
  final Namer namer;
  OnVariableCallback onVariable;
  ShouldEncodeTypedefCallback shouldEncodeTypedef;
  Map<ResolutionTypeVariableType, jsAst.Expression> typedefBindings;

  TypeRepresentationGenerator(this.namer);

  /**
   * Creates a type representation for [type]. [onVariable] is called to provide
   * the type representation for type variables.
   */
  jsAst.Expression getTypeRepresentation(
      Emitter emitter,
      ResolutionDartType type,
      OnVariableCallback onVariable,
      ShouldEncodeTypedefCallback encodeTypedef) {
    assert(typedefBindings == null);
    this.onVariable = onVariable;
    this.shouldEncodeTypedef = (encodeTypedef != null)
        ? encodeTypedef
        : (ResolutionTypedefType type) => false;
    jsAst.Expression representation = visit(type, emitter);
    this.onVariable = null;
    this.shouldEncodeTypedef = null;
    return representation;
  }

  jsAst.Expression getJavaScriptClassName(Element element, Emitter emitter) {
    return emitter.typeAccess(element);
  }

  @override
  visit(ResolutionDartType type, Emitter emitter) => type.accept(this, emitter);

  visitTypeVariableType(ResolutionTypeVariableType type, Emitter emitter) {
    if (typedefBindings != null) {
      assert(typedefBindings[type] != null);
      return typedefBindings[type];
    }
    return onVariable(type);
  }

  visitDynamicType(ResolutionDynamicType type, Emitter emitter) {
    return js('null');
  }

  visitInterfaceType(ResolutionInterfaceType type, Emitter emitter) {
    jsAst.Expression name = getJavaScriptClassName(type.element, emitter);
    return type.treatAsRaw
        ? name
        : visitList(type.typeArguments, emitter, head: name);
  }

  jsAst.Expression visitList(List<ResolutionDartType> types, Emitter emitter,
      {jsAst.Expression head}) {
    List<jsAst.Expression> elements = <jsAst.Expression>[];
    if (head != null) {
      elements.add(head);
    }
    for (ResolutionDartType type in types) {
      jsAst.Expression element = visit(type, emitter);
      if (element is jsAst.LiteralNull) {
        elements.add(new jsAst.ArrayHole());
      } else {
        elements.add(element);
      }
    }
    return new jsAst.ArrayInitializer(elements);
  }

  /// Returns the JavaScript template to determine at runtime if a type object
  /// is a function type.
  jsAst.Template get templateForIsFunctionType {
    return jsAst.js.expressionTemplateFor("'${namer.functionTypeTag}' in #");
  }

  /// Returns the JavaScript template that creates at runtime a new function
  /// type object.
  jsAst.Template get templateForCreateFunctionType {
    // The value of the functionTypeTag can be anything. We use "dynaFunc" for
    // easier debugging.
    return jsAst.js
        .expressionTemplateFor('{ ${namer.functionTypeTag}: "dynafunc" }');
  }

  visitFunctionType(ResolutionFunctionType type, Emitter emitter) {
    List<jsAst.Property> properties = <jsAst.Property>[];

    void addProperty(String name, jsAst.Expression value) {
      properties.add(new jsAst.Property(js.string(name), value));
    }

    // Type representations for functions have a property which is a tag marking
    // them as function types. The value is not used, so '1' is just a dummy.
    addProperty(namer.functionTypeTag, js.number(1));
    if (type.returnType.isVoid) {
      addProperty(namer.functionTypeVoidReturnTag, js('true'));
    } else if (!type.returnType.treatAsDynamic) {
      addProperty(
          namer.functionTypeReturnTypeTag, visit(type.returnType, emitter));
    }
    if (!type.parameterTypes.isEmpty) {
      addProperty(namer.functionTypeRequiredParametersTag,
          visitList(type.parameterTypes, emitter));
    }
    if (!type.optionalParameterTypes.isEmpty) {
      addProperty(namer.functionTypeOptionalParametersTag,
          visitList(type.optionalParameterTypes, emitter));
    }
    if (!type.namedParameterTypes.isEmpty) {
      List<jsAst.Property> namedArguments = <jsAst.Property>[];
      List<String> names = type.namedParameters;
      List<ResolutionDartType> types = type.namedParameterTypes;
      assert(types.length == names.length);
      for (int index = 0; index < types.length; index++) {
        jsAst.Expression name = js.string(names[index]);
        namedArguments
            .add(new jsAst.Property(name, visit(types[index], emitter)));
      }
      addProperty(namer.functionTypeNamedParametersTag,
          new jsAst.ObjectInitializer(namedArguments));
    }
    return new jsAst.ObjectInitializer(properties);
  }

  visitMalformedType(MalformedType type, Emitter emitter) {
    // Treat malformed types as dynamic at runtime.
    return js('null');
  }

  visitVoidType(ResolutionVoidType type, Emitter emitter) {
    // TODO(ahe): Reify void type ("null" means "dynamic").
    return js('null');
  }

  visitTypedefType(ResolutionTypedefType type, Emitter emitter) {
    bool shouldEncode = shouldEncodeTypedef(type);
    ResolutionDartType unaliasedType = type.unaliased;

    var oldBindings = typedefBindings;
    if (typedefBindings == null) {
      // First level typedef - capture arguments for re-use within typedef body.
      //
      // The type `Map<T, Foo<Set<T>>>` contains one type variable referenced
      // twice, so there are two inputs into the HTypeInfoExpression
      // instruction.
      //
      // If Foo is a typedef, T can be reused, e.g.
      //
      //     typedef E Foo<E>(E a, E b);
      //
      // As the typedef is expanded (to (Set<T>, Set<T>) => Set<T>) it should
      // not consume additional types from the to-level input.  We prevent this
      // by capturing the types and using the captured type expressions inside
      // the typedef expansion.
      //
      // TODO(sra): We should make the type subexpression Foo<...> be a second
      // HTypeInfoExpression, with Set<T> as its input (a third
      // HTypeInfoExpression). This would share all the Set<T> subexpressions
      // instead of duplicating them. This would require HTypeInfoExpression
      // inputs to correspond to type variables AND typedefs.
      typedefBindings = <ResolutionTypeVariableType, jsAst.Expression>{};
      type.forEachTypeVariable((variable) {
        if (variable is! MethodTypeVariableType) {
          typedefBindings[variable] = onVariable(variable);
        }
      });
    }

    jsAst.Expression finish(jsAst.Expression result) {
      typedefBindings = oldBindings;
      return result;
    }

    if (shouldEncode) {
      jsAst.ObjectInitializer initializer = visit(unaliasedType, emitter);
      // We have to encode the aliased type.
      jsAst.Expression name = getJavaScriptClassName(type.element, emitter);
      jsAst.Expression encodedTypedef = type.treatAsRaw
          ? name
          : visitList(type.typeArguments, emitter, head: name);

      // Add it to the function-type object.
      jsAst.LiteralString tag = js.string(namer.typedefTag);
      initializer.properties.add(new jsAst.Property(tag, encodedTypedef));
      return finish(initializer);
    } else {
      return finish(visit(unaliasedType, emitter));
    }
  }
}

class TypeCheckMapping implements TypeChecks {
  final Map<ClassElement, Set<TypeCheck>> map =
      new Map<ClassElement, Set<TypeCheck>>();

  Iterable<TypeCheck> operator [](ClassElement element) {
    Set<TypeCheck> result = map[element];
    return result != null ? result : const <TypeCheck>[];
  }

  void add(ClassElement cls, ClassElement check, Substitution substitution) {
    map.putIfAbsent(cls, () => new Set<TypeCheck>());
    map[cls].add(new TypeCheck(check, substitution));
  }

  Iterable<ClassElement> get classes => map.keys;

  String toString() {
    StringBuffer sb = new StringBuffer();
    for (ClassElement holder in classes) {
      for (ClassElement check in [holder]) {
        sb.write('${holder.name}.' '${check.name}, ');
      }
    }
    return '[$sb]';
  }
}

class ArgumentCollector extends ResolutionDartTypeVisitor {
  final Set<ClassElement> classes = new Set<ClassElement>();

  collect(ResolutionDartType type, {bool isTypeArgument: false}) {
    visit(type, isTypeArgument);
  }

  /// Collect all types in the list as if they were arguments of an
  /// InterfaceType.
  collectAll(List<ResolutionDartType> types) {
    for (ResolutionDartType type in types) {
      visit(type, true);
    }
  }

  visitTypedefType(ResolutionTypedefType type, bool isTypeArgument) {
    type.unaliased.accept(this, isTypeArgument);
  }

  visitInterfaceType(ResolutionInterfaceType type, bool isTypeArgument) {
    if (isTypeArgument) classes.add(type.element);
    type.visitChildren(this, true);
  }

  visitFunctionType(ResolutionFunctionType type, _) {
    type.visitChildren(this, true);
  }
}

class FunctionArgumentCollector extends ResolutionDartTypeVisitor {
  final Set<ClassElement> classes = new Set<ClassElement>();

  FunctionArgumentCollector();

  collect(ResolutionDartType type) {
    visit(type, false);
  }

  /// Collect all types in the list as if they were arguments of an
  /// InterfaceType.
  collectAll(Link<ResolutionDartType> types) {
    for (ResolutionDartType type in types) {
      visit(type, true);
    }
  }

  visitTypedefType(ResolutionTypedefType type, bool inFunctionType) {
    type.unaliased.accept(this, inFunctionType);
  }

  visitInterfaceType(ResolutionInterfaceType type, bool inFunctionType) {
    if (inFunctionType) {
      classes.add(type.element);
    }
    type.visitChildren(this, inFunctionType);
  }

  visitFunctionType(ResolutionFunctionType type, _) {
    type.visitChildren(this, true);
  }
}

/**
 * Representation of the substitution of type arguments
 * when going from the type of a class to one of its supertypes.
 *
 * For [:class B<T> extends A<List<T>, int>:], the substitution is
 * the representation of [: (T) => [<List, T>, int] :].  For more details
 * of the representation consult the documentation of
 * [getSupertypeSubstitution].
 */
//TODO(floitsch): Remove support for non-function substitutions.
class Substitution {
  final bool isFunction;
  final List<ResolutionDartType> arguments;
  final List<ResolutionDartType> parameters;

  Substitution.list(this.arguments)
      : isFunction = false,
        parameters = const <ResolutionDartType>[];

  Substitution.function(this.arguments, this.parameters) : isFunction = true;
}

/**
 * A pair of a class that we need a check against and the type argument
 * substition for this check.
 */
class TypeCheck {
  final ClassElement cls;
  final Substitution substitution;
  final int hashCode = _nextHash = (_nextHash + 100003).toUnsigned(30);
  static int _nextHash = 0;

  TypeCheck(this.cls, this.substitution);
}
