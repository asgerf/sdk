// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.constraint_extractor;

import '../../ast.dart';
import '../../class_hierarchy.dart';
import '../../core_types.dart';
import '../constraints.dart';
import '../key.dart';
import '../value.dart';
import 'augmented_type.dart';
import 'binding.dart';
import 'constraint_builder.dart';
import 'external_model.dart';
import 'hierarchy.dart';
import 'substitution.dart';
import 'value_sink.dart';

/// Generates constraints from an AST.
///
/// This follows like the type checking, where each subtyping judgement gives
/// rise to constraints.
class ConstraintExtractor {
  CoreTypes coreTypes;
  Binding binding;
  ClassHierarchy baseHierarchy;
  AugmentedHierarchy hierarchy;
  ConstraintBuilder builder;
  ExternalModel externalModel;

  AType conditionType;
  AType escapingType;
  AType boolType;
  AType intType;
  AType doubleType;
  AType numType;
  AType stringType;
  AType symbolType;
  AType typeType;
  AType topType;

  Value intValue;
  Value doubleValue;
  Value numValue;
  Value stringValue;
  Value boolValue;
  Value nullValue;
  Value functionValue;

  Value nullableIntValue;
  Value nullableDoubleValue;
  Value nullableNumValue;
  Value nullableStringValue;
  Value nullableBoolValue;

  void extractFromProgram(Program program) {
    coreTypes ??= new CoreTypes(program);
    baseHierarchy ??= new ClassHierarchy(program);
    binding ??= new Binding(coreTypes);
    hierarchy ??= new AugmentedHierarchy(baseHierarchy, binding);
    externalModel ??= new BasicExternalModel(coreTypes);
    builder ??= new ConstraintBuilder(hierarchy);
    conditionType = new InterfaceAType(
        Value.bottom, ValueSink.nowhere, coreTypes.boolClass, const <AType>[]);
    escapingType = new BottomAType(Value.escaping, ValueSink.nowhere);
    boolType = new InterfaceAType(new Value(coreTypes.boolClass, Flags.string),
        ValueSink.nowhere, coreTypes.boolClass, const <AType>[]);
    intType = new InterfaceAType(new Value(coreTypes.intClass, Flags.integer),
        ValueSink.nowhere, coreTypes.intClass, const <AType>[]);
    doubleType = new InterfaceAType(
        new Value(coreTypes.doubleClass, Flags.double_),
        ValueSink.nowhere,
        coreTypes.doubleClass, const <AType>[]);
    stringType = new InterfaceAType(
        new Value(coreTypes.stringClass, Flags.string),
        ValueSink.nowhere,
        coreTypes.stringClass, const <AType>[]);
    topType = new InterfaceAType(new Value(coreTypes.objectClass, Flags.all),
        ValueSink.nowhere, coreTypes.objectClass, const <AType>[]);
    numType = new InterfaceAType(
        new Value(coreTypes.numClass,
            Flags.integer | Flags.double_ | Flags.inexactBaseClass),
        ValueSink.nowhere,
        coreTypes.numClass,
        const <AType>[]);
    symbolType = new InterfaceAType(
        new Value(coreTypes.symbolClass, Flags.other),
        ValueSink.nowhere,
        coreTypes.symbolClass, const <AType>[]);
    typeType = new InterfaceAType(new Value(coreTypes.typeClass, Flags.other),
        ValueSink.nowhere, coreTypes.typeClass, const <AType>[]);
    intValue = new Value(coreTypes.intClass, Flags.integer);
    doubleValue = new Value(coreTypes.doubleClass, Flags.double_);
    numValue = new Value(coreTypes.numClass,
        Flags.integer | Flags.double_ | Flags.inexactBaseClass);
    stringValue = new Value(coreTypes.stringClass, Flags.string);
    boolValue = new Value(coreTypes.boolClass, Flags.boolean);
    nullValue = new Value(null, Flags.null_);
    functionValue = new Value(
        coreTypes.functionClass, Flags.other | Flags.inexactBaseClass);
    nullableIntValue =
        new Value(coreTypes.intClass, Flags.null_ | Flags.integer);
    nullableDoubleValue =
        new Value(coreTypes.doubleClass, Flags.null_ | Flags.double_);
    nullableNumValue = new Value(coreTypes.numClass,
        Flags.null_ | Flags.integer | Flags.double_ | Flags.inexactBaseClass);
    nullableStringValue =
        new Value(coreTypes.stringClass, Flags.null_ | Flags.string);
    nullableBoolValue = new Value(coreTypes.boolClass, Flags.boolean);
    for (var library in program.libraries) {
      for (var class_ in library.classes) {
        baseHierarchy.forEachOverridePair(class_,
            (Member ownMember, Member superMember, bool isSetter) {
          checkOverride(class_, ownMember, superMember, isSetter);
        });
      }
    }

    for (var library in program.libraries) {
      bool isUncheckedLibrary = library.importUri.scheme == 'dart';
      for (var class_ in library.classes) {
        for (var member in class_.members) {
          analyzeMember(member, isUncheckedLibrary);
        }
      }
      for (var procedure in library.procedures) {
        analyzeMember(procedure, isUncheckedLibrary);
      }
      for (var field in library.fields) {
        analyzeMember(field, isUncheckedLibrary);
      }
    }
  }

  void analyzeMember(Member member, bool isUncheckedLibrary) {
    builder.currentOwner = member;
    var class_ = member.enclosingClass;
    var classBank = class_ == null ? null : binding.getClassBank(class_);
    var visitor = new ConstraintExtractorVisitor(this, member,
        binding.getMemberBank(member), classBank, isUncheckedLibrary);
    visitor.analyzeMember();
  }

  AType getterType(Class host, Member member) {
    var substitution =
        hierarchy.getClassAsInstanceOf(host, member.enclosingClass);
    var type = substitution.substituteType(binding.getGetterType(member));
    assert(type.isClosed(host.typeParameters));
    return type;
  }

  AType setterType(Class host, Member member) {
    var substitution =
        hierarchy.getClassAsInstanceOf(host, member.enclosingClass);
    var type = substitution.substituteType(binding.getSetterType(member));
    assert(type.isClosed(host.typeParameters));
    return type;
  }

  void checkOverride(
      Class host, Member ownMember, Member superMember, bool isSetter) {
    if (isSetter) {
      checkAssignable(ownMember, setterType(host, superMember),
          setterType(host, ownMember), new GlobalScope(binding));
    } else {
      checkAssignable(ownMember, getterType(host, ownMember),
          getterType(host, superMember), new GlobalScope(binding));
    }
  }

  /// Check that [from] is a subtype of [to].
  ///
  /// [where] is an AST node indicating roughly where the check is required.
  void checkAssignable(
      TreeNode where, AType from, AType to, TypeParameterScope scope) {
    // assert(!from.containsPlaceholder);
    // assert(!to.containsPlaceholder);
    // TODO: Expose type parameters in 'scope' and check closedness
    try {
      from.generateSubtypeConstraints(to, builder);
    } on UnassignableSinkError catch (e) {
      e.assignmentLocation = where.location;
      print('$from <: $to');
      rethrow;
    }
  }

  /// Indicates that type checking failed.
  void reportTypeError(TreeNode where, String message) {
    print('$where: $message');
  }

  Value getWorstCaseValueForType(AType type) {
    if (type is InterfaceAType) return getWorstCaseValue(type.classNode);
    if (type is FunctionAType) {
      return new Value(
          coreTypes.functionClass, Flags.other | Flags.inexactBaseClass);
    }
    return new Value(coreTypes.objectClass, Flags.all);
  }

  Value getWorstCaseValue(Class classNode, {bool isNice: false}) {
    if (isNice) return getNiceCaseValue(classNode);
    if (classNode == coreTypes.intClass) return nullableIntValue;
    if (classNode == coreTypes.doubleClass) return nullableDoubleValue;
    if (classNode == coreTypes.numClass) return nullableNumValue;
    if (classNode == coreTypes.stringClass) return nullableStringValue;
    if (classNode == coreTypes.boolClass) return nullableBoolValue;
    if (classNode == coreTypes.nullClass) return nullValue;
    return new Value(coreTypes.objectClass, Flags.all);
  }

  Value getNiceCaseValue(Class classNode) {
    if (classNode == coreTypes.intClass) return intValue;
    if (classNode == coreTypes.doubleClass) return doubleValue;
    if (classNode == coreTypes.numClass) return numValue;
    if (classNode == coreTypes.stringClass) return stringValue;
    if (classNode == coreTypes.boolClass) return boolValue;
    if (classNode == coreTypes.nullClass) return nullValue;
    return new Value(coreTypes.objectClass, Flags.all & ~Flags.escaping);
  }

  final List<Function> analysisCompleteHooks = <Function>[];

  void onAnalysisComplete(void hook()) {
    analysisCompleteHooks.add(hook);
  }
}

abstract class TypeParameterScope {
  AType getTypeParameterBound(TypeParameter parameter);
}

class GlobalScope extends TypeParameterScope {
  final Binding binding;

  GlobalScope(this.binding);

  AType getTypeParameterBound(TypeParameter parameter) {
    TreeNode parent = parameter.parent;
    if (parent is Class) {
      int index = parent.typeParameters.indexOf(parameter);
      return binding.getClassBank(parent).typeParameters[index];
    } else {
      FunctionNode function = parent;
      Member member = function.parent;
      int index = function.typeParameters.indexOf(parameter);
      return binding.getFunctionBank(member).type.typeParameters[index];
    }
  }
}

class LocalScope extends TypeParameterScope {
  final Map<TypeParameter, AType> typeParameterBounds =
      <TypeParameter, AType>{};
  final Map<VariableDeclaration, AType> variables =
      <VariableDeclaration, AType>{};

  AType getVariableType(VariableDeclaration node) {
    assert(variables.containsKey(node));
    return variables[node];
  }

  AType getTypeParameterBound(TypeParameter parameter) {
    assert(typeParameterBounds.containsKey(parameter));
    return typeParameterBounds[parameter];
  }
}

/// Generates constraints from the body of a member.
class ConstraintExtractorVisitor
    implements
        ExpressionVisitor<AType>,
        StatementVisitor<bool>,
        MemberVisitor<Null>,
        InitializerVisitor<Null> {
  final ConstraintExtractor extractor;
  final Member currentMember;
  final ModifierBank modifiers;
  final ClassBank classModifiers;

  CoreTypes get coreTypes => extractor.coreTypes;
  ClassHierarchy get baseHierarchy => extractor.baseHierarchy;
  AugmentedHierarchy get hierarchy => extractor.hierarchy;
  Binding get binding => extractor.binding;
  ConstraintBuilder get builder => extractor.builder;
  Class get currentClass => currentMember.enclosingClass;

  Uri get currentUri => currentMember.enclosingLibrary.importUri;
  bool get isFileUri => currentUri.scheme == 'file';

  InterfaceAType thisType;
  Substitution thisSubstitution;

  AType returnType;
  AType yieldType;
  AsyncMarker currentAsyncMarker;
  bool seenTypeError = false;

  final LocalScope scope = new LocalScope();
  final bool isUncheckedLibrary;

  ConstraintExtractorVisitor(this.extractor, this.currentMember, this.modifiers,
      this.classModifiers, this.isUncheckedLibrary);

  void checkTypeBound(TreeNode where, AType type, AType bound) {
    type.generateSubBoundConstraint(bound, builder);
  }

  void checkAssignable(TreeNode where, AType from, AType to) {
    extractor.checkAssignable(where, from, to, scope);
  }

  AType checkAssignableExpression(Expression from, AType to) {
    var type = visitExpression(from);
    extractor.checkAssignable(from, type, to, scope);
    return type;
  }

  void checkConditionExpression(Expression condition) {
    checkAssignableExpression(condition, extractor.conditionType);
  }

  void fail(TreeNode node, String message) {
    if (!isUncheckedLibrary) {
      extractor.reportTypeError(node, message);
    }
    seenTypeError = true;
  }

  AType visitExpression(Expression node) {
    var type = node.accept(this);
    var source = type.source;
    if (source is Key && source.owner == modifiers.classOrMember) {
      node.inferredValueIndex = source.index;
    } else {
      var newKey = modifiers.newModifier();
      builder.addAssignment(source, newKey, Flags.all);
      type = type.withSource(newKey);
      node.inferredValueIndex = newKey.index;
    }
    return type;
  }

  /// Returns false if the statement cannot complete normally.
  bool visitStatement(Statement node) {
    return node.accept(this);
  }

  void visitInitializer(Initializer node) {
    node.accept(this);
  }

  defaultMember(Member node) => throw 'Unused';

  AType defaultBasicLiteral(BasicLiteral node) {
    return defaultExpression(node);
  }

  AType defaultExpression(Expression node) {
    throw 'Unexpected expression ${node.runtimeType}';
  }

  defaultStatement(Statement node) {
    throw 'Unexpected statement ${node.runtimeType}';
  }

  defaultInitializer(Initializer node) {
    throw 'Unexpected initializer ${node.runtimeType}';
  }

  void analyzeMember() {
    var class_ = currentClass;
    if (class_ != null) {
      var typeParameters = class_.typeParameters;
      var thisTypeArgs = <AType>[];
      for (int i = 0; i < typeParameters.length; ++i) {
        var parameter = typeParameters[i];
        var bound = classModifiers.typeParameters[i];
        scope.typeParameterBounds[parameter] = bound;
        // TODO
        thisTypeArgs
            .add(new TypeParameterAType(bound.source, bound.sink, parameter));
      }
      var value = new Value(class_, Flags.inexactBaseClass);
      thisType = new InterfaceAType(
          value,
          ValueSink.unassignable("type of 'this'", class_),
          class_,
          thisTypeArgs);
      thisSubstitution = Substitution.fromInterfaceType(thisType);
    } else {
      thisSubstitution = Substitution.empty;
    }
    thisSubstitution = Substitution.empty;

    recordClassTypeParameterBounds();
    currentMember.accept(this);
  }

  visitField(Field node) {
    FieldBank modifiers = this.modifiers;
    var fieldType = thisSubstitution.substituteType(modifiers.type);
    if (node.initializer != null && !isUncheckedLibrary) {
      checkAssignableExpression(node.initializer, fieldType);
    }
    if (node.isExternal || seenTypeError) {
      modifiers.type.accept(new ExternalVisitor(extractor,
          extractor.externalModel.isNicelyBehaved(node), true, !node.isFinal));
    }
  }

  visitConstructor(Constructor node) {
    returnType = null;
    yieldType = null;
    FunctionMemberBank modifiers = this.modifiers;
    recordParameterTypes(modifiers, node.function);
    node.initializers.forEach(visitInitializer);
    handleFunctionBody(node.function);
    if (node.isExternal || seenTypeError) {
      modifiers.type.accept(new ExternalVisitor(extractor,
          extractor.externalModel.isNicelyBehaved(node), true, false));
    }
  }

  visitProcedure(Procedure node) {
    FunctionMemberBank modifiers = this.modifiers;
    var ret = thisSubstitution.substituteType(modifiers.returnType);
    returnType = _getInternalReturnType(node.function.asyncMarker, ret);
    yieldType = _getYieldType(node.function.asyncMarker, ret);
    recordParameterTypes(modifiers, node.function);
    handleFunctionBody(node.function);
    if (node.isExternal || seenTypeError) {
      modifiers.type.accept(new ExternalVisitor(extractor,
          extractor.externalModel.isNicelyBehaved(node), true, false));
    }
  }

  void recordClassTypeParameterBounds() {
    var class_ = currentClass;
    if (class_ == null) return;
    var typeParameters = class_.typeParameters;
    for (int i = 0; i < typeParameters.length; ++i) {
      scope.typeParameterBounds[typeParameters[i]] =
          classModifiers.typeParameters[i];
    }
  }

  void recordParameterTypes(
      FunctionMemberBank modifiers, FunctionNode function) {
    for (int i = 0; i < function.typeParameters.length; ++i) {
      scope.typeParameterBounds[function.typeParameters[i]] =
          modifiers.typeParameters[i];
    }
    for (int i = 0; i < function.positionalParameters.length; ++i) {
      var variable = function.positionalParameters[i];
      var type = modifiers.positionalParameters[i];
      scope.variables[variable] = type;
    }
    for (int i = 0; i < function.namedParameters.length; ++i) {
      scope.variables[function.namedParameters[i]] =
          modifiers.namedParameters[i];
    }
  }

  void handleFunctionBody(FunctionNode node) {
    var oldAsyncMarker = currentAsyncMarker;
    currentAsyncMarker = node.asyncMarker;
    node.positionalParameters
        .skip(node.requiredParameterCount)
        .forEach(handleOptionalParameter);
    node.namedParameters.forEach(handleOptionalParameter);
    if (node.body != null) {
      bool completes = visitStatement(node.body);
      if (completes && returnType != null) {
        builder.addAssignment(
            extractor.nullValue, returnType.sink, Flags.null_);
      }
    }
    currentAsyncMarker = oldAsyncMarker;
  }

  FunctionAType handleNestedFunctionNode(FunctionNode node,
      [VariableDeclaration selfReference]) {
    for (var parameter in node.typeParameters) {
      scope.typeParameterBounds[parameter] =
          modifiers.augmentBound(parameter.bound);
    }
    var typeTerms = <AType>[];
    for (var parameter in node.positionalParameters) {
      parameter.inferredValueOffset = modifiers.nextIndex;
      var type = modifiers.augmentType(parameter.type);
      scope.variables[parameter] = type;
      typeTerms.add(type);
    }
    for (var parameter in node.namedParameters) {
      parameter.inferredValueOffset = modifiers.nextIndex;
      var type = modifiers.augmentType(parameter.type);
      scope.variables[parameter] = type;
      typeTerms.add(type);
    }
    AType augmentedReturnType = modifiers.augmentType(node.returnType);
    typeTerms.add(augmentedReturnType);
    var functionObject = modifiers.newModifier();
    var type = new FunctionAType(
        functionObject,
        functionObject,
        node.typeParameters.map(getTypeParameterBound).toList(growable: false),
        node.requiredParameterCount,
        node.positionalParameters.map(getVariableType).toList(growable: false),
        node.namedParameters.map((v) => v.name).toList(growable: false),
        node.namedParameters.map(getVariableType).toList(growable: false),
        augmentedReturnType);
    addAllocationConstraints(functionObject, extractor.functionValue, type);
    if (selfReference != null) {
      scope.variables[selfReference] = type;
    }
    var oldReturn = returnType;
    var oldYield = yieldType;
    returnType = _getInternalReturnType(node.asyncMarker, augmentedReturnType);
    yieldType = _getYieldType(node.asyncMarker, augmentedReturnType);
    handleFunctionBody(node);
    returnType = oldReturn;
    yieldType = oldYield;
    return type;
  }

  AType getVariableType(VariableDeclaration node) {
    return scope.getVariableType(node);
  }

  AType getTypeParameterBound(TypeParameter parameter) {
    return scope.getTypeParameterBound(parameter);
  }

  void handleOptionalParameter(VariableDeclaration parameter) {
    if (parameter.initializer != null) {
      checkAssignableExpression(
          parameter.initializer, getVariableType(parameter));
    } else {
      builder.addAssignment(
          extractor.nullValue, getVariableType(parameter).sink, Flags.null_);
    }
  }

  Substitution getReceiverType(
      TreeNode where, Expression receiver, Member member) {
    AType type = visitExpression(receiver);
    Class superclass = member.enclosingClass;
    if (superclass.supertype == null) {
      return Substitution.empty; // Members on Object are always accessible.
    }
    while (type is TypeParameterAType) {
      type = getTypeParameterBound((type as TypeParameterAType).parameter);
    }
    if (type is BottomAType) {
      // The bottom type is a subtype of all types, so it should be allowed.
      return Substitution.bottomForClass(superclass);
    }
    if (type is InterfaceAType) {
      // The receiver type should implement the interface declaring the member.
      var superSubstitution =
          hierarchy.getClassAsInstanceOf(type.classNode, superclass);
      if (superSubstitution != null) {
        var ownSubstitution = Substitution.fromInterfaceType(type);
        return Substitution.sequence(superSubstitution, ownSubstitution);
      }
    }
    if (type is FunctionAType && superclass == coreTypes.functionClass) {
      assert(type.typeParameters.isEmpty);
      return Substitution.empty;
    }
    // Note that we do not allow 'dynamic' here.  Dynamic calls should not
    // have a declared interface target.
    fail(where, '$member is not accessible on a receiver of type $type');
    // Continue type checking.
    return Substitution.bottomForClass(superclass);
  }

  Substitution getSuperReceiverType(Member member) {
    return hierarchy.getClassAsInstanceOf(currentClass, member.enclosingClass);
  }

  void checkTypeParameterBounds(TreeNode where, List<AType> arguments,
      List<AType> bounds, Substitution substitution) {
    for (int i = 0; i < arguments.length; ++i) {
      var argument = arguments[i];
      var bound = substitution.substituteBound(bounds[i]);
      checkTypeBound(where, argument, bound);
    }
  }

  AType handleCall(Arguments arguments, Member member,
      {Substitution receiver: Substitution.empty}) {
    var function = member.function;
    if (arguments.positional.length < function.requiredParameterCount) {
      fail(arguments, 'Too few positional arguments');
      return BottomAType.nonNullable;
    }
    if (arguments.positional.length > function.positionalParameters.length) {
      fail(arguments, 'Too many positional arguments');
      return BottomAType.nonNullable;
    }
    FunctionMemberBank target = binding.getFunctionBank(function.parent);
    var typeParameters = function.typeParameters;
    Substitution instantiation = Substitution.empty;
    List<AType> typeArguments = const [];
    if (member is! Constructor) {
      typeArguments =
          modifiers.augmentTypeList(arguments.types).toList(growable: false);
      if (typeArguments.length != typeParameters.length) {
        fail(arguments, 'Wrong number of type arguments');
        return BottomAType.nonNullable;
      }
      instantiation = Substitution.fromPairs(typeParameters, typeArguments);
    } else {
      assert(typeParameters.isEmpty);
    }
    var substitution = Substitution.either(receiver, instantiation);
    checkTypeParameterBounds(
        arguments, typeArguments, target.typeParameters, substitution);
    for (int i = 0; i < arguments.positional.length; ++i) {
      var expectedType =
          substitution.substituteType(target.positionalParameters[i]);
      checkAssignableExpression(arguments.positional[i], expectedType);
    }
    for (int i = 0; i < arguments.named.length; ++i) {
      var argument = arguments.named[i];
      bool found = false;
      // TODO: exploit that named parameters are sorted.
      for (int j = 0; j < function.namedParameters.length; ++j) {
        if (argument.name == function.namedParameters[j].name) {
          var expectedType =
              substitution.substituteType(target.namedParameters[i]);
          checkAssignableExpression(argument.value, expectedType);
          found = true;
          break;
        }
      }
      if (!found) {
        fail(argument.value, 'Unexpected named parameter: ${argument.name}');
        break;
      }
    }
    return substitution.substituteType(target.returnType);
  }

  AType _getInternalReturnType(AsyncMarker asyncMarker, AType returnType) {
    switch (asyncMarker) {
      case AsyncMarker.Sync:
        return returnType;

      case AsyncMarker.Async:
        Class container = coreTypes.futureClass;
        if (returnType is InterfaceAType && returnType.classNode == container) {
          return returnType.typeArguments.single;
        }
        return extractor.escapingType;

      case AsyncMarker.SyncStar:
      case AsyncMarker.AsyncStar:
      case AsyncMarker.SyncYielding:
        return null;

      default:
        throw 'Unexpected async marker: $asyncMarker';
    }
  }

  AType _getYieldType(AsyncMarker asyncMarker, AType returnType) {
    switch (asyncMarker) {
      case AsyncMarker.Sync:
      case AsyncMarker.Async:
        return null;

      case AsyncMarker.SyncStar:
      case AsyncMarker.AsyncStar:
        Class container = asyncMarker == AsyncMarker.SyncStar
            ? coreTypes.iterableClass
            : coreTypes.streamClass;
        if (returnType is InterfaceAType && returnType.classNode == container) {
          return returnType.typeArguments.single;
        }
        return extractor.escapingType;

      case AsyncMarker.SyncYielding:
        return returnType;

      default:
        throw 'Unexpected async marker: $asyncMarker';
    }
  }

  /// True if [castType] has type arguments which must be considered tainted
  /// after the cast.
  ///
  /// For example, when casting from `Object` to `List<int>`, we must consider
  /// the `int` type to be nullable, because we do not track where it came from.
  bool isTaintingDowncast(DartType castType) {
    // Potential improvement: Consider both input type and output type, and
    //   taint only type arguments that cannot be connected to a type in the
    //   input type. For example, casting `List<num>` to `List<int>` or
    //   `Iterable<int>` to `List<int>` does not require taint.
    if (castType is InterfaceType) {
      return castType.typeArguments.isNotEmpty;
    }
    if (castType is FunctionType) {
      return true;
    }
    return false;
  }

  void taintSubterms(AType type) {
    if (type is InterfaceAType) {
      for (var argument in type.typeArguments) {
        argument.accept(new ExternalVisitor.bivariant(extractor));
      }
    } else if (type is FunctionAType) {
      for (var argument in type.positionalParameters) {
        argument.accept(new ExternalVisitor.covariant(extractor));
      }
      for (var argument in type.namedParameters) {
        argument.accept(new ExternalVisitor.covariant(extractor));
      }
      type.returnType.accept(new ExternalVisitor.contravariant(extractor));
    }
  }

  @override
  AType visitAsExpression(AsExpression node) {
    var input = visitExpression(node.operand);
    var output = modifiers.augmentType(node.type);
    builder.addAssignment(input.source, output.sink, Flags.all);
    if (isTaintingDowncast(node.type)) {
      taintSubterms(output);
      builder.addEscape(input.source);
    }
    return output;
  }

  AType unfutureType(AType type) {
    if (type is InterfaceAType && type.classNode == coreTypes.futureClass) {
      return unfutureType(type.typeArguments[0]);
    } else {
      return type;
    }
  }

  @override
  AType visitAwaitExpression(AwaitExpression node) {
    return unfutureType(visitExpression(node.operand));
  }

  @override
  AType visitBoolLiteral(BoolLiteral node) {
    return extractor.boolType;
  }

  @override
  AType visitConditionalExpression(ConditionalExpression node) {
    checkConditionExpression(node.condition);
    var type = modifiers.augmentType(node.staticType);
    checkAssignableExpression(node.then, type);
    checkAssignableExpression(node.otherwise, type);
    return type;
  }

  int flagsFromExactClass(Class class_) {
    if (class_ == coreTypes.intClass) return Flags.integer;
    if (class_ == coreTypes.doubleClass) return Flags.double_;
    if (class_ == coreTypes.stringClass) return Flags.string;
    if (class_ == coreTypes.boolClass) return Flags.boolean;
    return Flags.other;
  }

  void addAllocationTypeArgument(Key createdObject, AType typeArgument) {
    new AllocationVisitor(extractor, createdObject).visit(typeArgument);
  }

  void addAllocationConstraints(Key createdObject, Value value, AType type) {
    builder.addConstraint(new ValueConstraint(createdObject, value));
    new AllocationVisitor(extractor, createdObject).visitSubterms(type);
  }

  @override
  AType visitConstructorInvocation(ConstructorInvocation node) {
    Constructor target = node.target;
    Arguments arguments = node.arguments;
    Class class_ = target.enclosingClass;
    node.arguments.inferredTypeArgumentIndex = modifiers.nextIndex;
    var typeArguments = modifiers.augmentTypeList(arguments.types);
    Substitution substitution =
        Substitution.fromPairs(class_.typeParameters, typeArguments);
    checkTypeParameterBounds(node, typeArguments,
        binding.getClassBank(class_).typeParameters, substitution);
    handleCall(arguments, target, receiver: substitution);
    var createdObject = modifiers.newModifier();
    var value = new Value(class_, flagsFromExactClass(class_));
    var type = new InterfaceAType(
        createdObject,
        ValueSink.unassignable('result of an expression', node),
        target.enclosingClass,
        typeArguments);
    addAllocationConstraints(createdObject, value, type);
    return type;
  }

  @override
  AType visitDirectMethodInvocation(DirectMethodInvocation node) {
    return handleCall(node.arguments, node.target,
        receiver: getReceiverType(node, node.receiver, node.target));
  }

  @override
  AType visitDirectPropertyGet(DirectPropertyGet node) {
    var receiver = getReceiverType(node, node.receiver, node.target);
    var getterType = binding.getGetterType(node.target);
    return receiver.substituteType(getterType);
  }

  @override
  AType visitDirectPropertySet(DirectPropertySet node) {
    var receiver = getReceiverType(node, node.receiver, node.target);
    var value = visitExpression(node.value);
    var setterType = binding.getSetterType(node.target);
    checkAssignable(node, value, receiver.substituteType(setterType));
    return value;
  }

  @override
  AType visitDoubleLiteral(DoubleLiteral node) {
    return extractor.doubleType;
  }

  @override
  AType visitFunctionExpression(FunctionExpression node) {
    return handleNestedFunctionNode(node.function);
  }

  @override
  AType visitIntLiteral(IntLiteral node) {
    return extractor.intType;
  }

  @override
  AType visitInvalidExpression(InvalidExpression node) {
    return BottomAType.nonNullable;
  }

  @override
  AType visitIsExpression(IsExpression node) {
    visitExpression(node.operand);
    return extractor.boolType;
  }

  @override
  AType visitLet(Let node) {
    var value = visitExpression(node.variable.initializer);
    // TODO(asgerf): Make sure let variable is not 'dynamic'.
    var type = scope.variables[node.variable] =
        modifiers.augmentType(node.variable.type);
    checkAssignable(node, value, type);
    return visitExpression(node.body);
  }

  @override
  AType visitListLiteral(ListLiteral node) {
    node.inferredTypeArgumentIndex = modifiers.nextIndex;
    var typeArgument = modifiers.augmentType(node.typeArgument);
    for (var item in node.expressions) {
      checkAssignableExpression(item, typeArgument);
    }
    var createdObject = modifiers.newModifier();
    var value = new Value(coreTypes.listClass, Flags.other);
    var type = new InterfaceAType(
        createdObject,
        ValueSink.unassignable('result of an expression', node),
        coreTypes.listClass,
        <AType>[typeArgument]);
    addAllocationConstraints(createdObject, value, type);
    return type;
  }

  @override
  AType visitLogicalExpression(LogicalExpression node) {
    checkConditionExpression(node.left);
    checkConditionExpression(node.right);
    return extractor.boolType;
  }

  @override
  AType visitMapLiteral(MapLiteral node) {
    node.inferredTypeArgumentIndex = modifiers.nextIndex;
    var keyType = modifiers.augmentType(node.keyType);
    var valueType = modifiers.augmentType(node.valueType);
    for (var entry in node.entries) {
      checkAssignableExpression(entry.key, keyType);
      checkAssignableExpression(entry.value, valueType);
    }
    var createdObject = modifiers.newModifier();
    var value = new Value(coreTypes.mapClass, Flags.other);
    var type = new InterfaceAType(
        createdObject,
        ValueSink.unassignable('result of an expression', node),
        coreTypes.mapClass,
        <AType>[keyType, valueType]);
    addAllocationConstraints(createdObject, value, type);
    return type;
  }

  void handleEscapingExpression(Expression node) {
    var type = visitExpression(node);
    handleEscapingType(type);
  }

  void handleEscapingType(AType type) {
    builder.addEscape(type.source);
  }

  AType handleDynamicCall(AType receiver, Arguments arguments) {
    handleEscapingType(receiver);
    for (var argument in arguments.positional) {
      handleEscapingExpression(argument);
    }
    for (var argument in arguments.named) {
      handleEscapingExpression(argument.value);
    }
    return extractor.topType;
  }

  AType handleFunctionCall(
      TreeNode where, FunctionAType function, Arguments arguments) {
    if (function.requiredParameterCount > arguments.positional.length) {
      fail(where, 'Too few positional arguments');
      return BottomAType.nonNullable;
    }
    if (function.positionalParameters.length < arguments.positional.length) {
      fail(where, 'Too many positional arguments');
      return BottomAType.nonNullable;
    }
    if (function.typeParameters.length != arguments.types.length) {
      fail(where, 'Wrong number of type arguments');
      return BottomAType.nonNullable;
    }
    List<AType> typeArguments = modifiers.augmentTypeList(arguments.types);
    if (typeArguments.isNotEmpty) {
      fail(where, 'Function type arguments not yet supported');
    }
    var instantiation = Substitution.empty;
    // var instantiation = Substitution.instantiateFunctionType(typeArguments);
    for (int i = 0; i < typeArguments.length; ++i) {
      checkTypeBound(where, typeArguments[i],
          instantiation.substituteBound(function.typeParameters[i]));
    }
    for (int i = 0; i < arguments.positional.length; ++i) {
      var expectedType =
          instantiation.substituteType(function.positionalParameters[i]);
      checkAssignableExpression(arguments.positional[i], expectedType);
    }
    for (int i = 0; i < arguments.named.length; ++i) {
      var argument = arguments.named[i];
      bool found = false;
      // TODO: exploit that named parameters are sorted.
      for (int j = 0; j < function.namedParameters.length; ++j) {
        if (argument.name == function.namedParameterNames[j]) {
          var expectedType =
              instantiation.substituteType(function.namedParameters[j]);
          checkAssignableExpression(argument.value, expectedType);
          found = true;
          break;
        }
      }
      if (!found) {
        fail(argument.value, 'Unexpected named parameter: ${argument.name}');
        break;
      }
    }
    return instantiation.substituteType(function.returnType);
  }

  bool isOverloadedArithmeticOperator(Procedure member) {
    Class class_ = member.enclosingClass;
    if (class_ == coreTypes.intClass || class_ == coreTypes.numClass) {
      String name = member.name.name;
      return name == '+' ||
          name == '-' ||
          name == '*' ||
          name == 'remainder' ||
          name == '%';
    }
    return false;
  }

  AType getTypeOfOverloadedArithmetic(AType type1, AType type2) {
    if (type1 is TypeParameterAType &&
        type2 is TypeParameterAType &&
        type1.parameter == type2.parameter) {
      // TODO: Prevent 'null' value from being propagated here.
      return type1;
    }
    while (type1 is TypeParameterAType) {
      type1 = getTypeParameterBound((type1 as TypeParameterAType).parameter);
    }
    if (type1 is InterfaceAType && type2 is InterfaceAType) {
      Class class1 = type1.classNode;
      Class class2 = type2.classNode;
      // Note that the result cannot be null because that would fail at runtime,
      // so do not return 'type1' or 'type2'.
      if (class1 == coreTypes.intClass && class2 == coreTypes.intClass) {
        return extractor.intType;
      }
      if (class1 == coreTypes.doubleClass || class2 == coreTypes.doubleClass) {
        return extractor.doubleType;
      }
    }
    return extractor.numType;
  }

  @override
  AType visitMethodInvocation(MethodInvocation node) {
    var target = node.interfaceTarget;
    if (target == null) {
      var receiver = visitExpression(node.receiver);
      if (node.name.name == '==') {
        // TODO: Handle value escaping through == operator.
        visitExpression(node.arguments.positional.single);
        return extractor.boolType;
      }
      if (node.name.name == 'call' && receiver is FunctionAType) {
        return handleFunctionCall(node, receiver, node.arguments);
      }
      return handleDynamicCall(receiver, node.arguments);
    } else if (isOverloadedArithmeticOperator(target)) {
      assert(node.arguments.positional.length == 1);
      var receiver = visitExpression(node.receiver);
      var argument = visitExpression(node.arguments.positional[0]);
      return getTypeOfOverloadedArithmetic(receiver, argument);
    } else {
      return handleCall(node.arguments, target,
          receiver: getReceiverType(node, node.receiver, node.interfaceTarget));
    }
  }

  @override
  AType visitPropertyGet(PropertyGet node) {
    if (node.interfaceTarget == null) {
      handleEscapingExpression(node.receiver);
      return extractor.topType;
    } else {
      var receiver = getReceiverType(node, node.receiver, node.interfaceTarget);
      var getterType = binding.getGetterType(node.interfaceTarget);
      return receiver.substituteType(getterType);
    }
  }

  @override
  AType visitPropertySet(PropertySet node) {
    var value = visitExpression(node.value);
    if (node.interfaceTarget != null) {
      var receiver = getReceiverType(node, node.receiver, node.interfaceTarget);
      var setterType = binding.getSetterType(node.interfaceTarget);
      checkAssignable(node.value, value, receiver.substituteType(setterType));
    } else {
      handleEscapingExpression(node.receiver);
      handleEscapingType(value);
    }
    return value;
  }

  @override
  AType visitNot(Not node) {
    checkConditionExpression(node.operand);
    return extractor.boolType;
  }

  @override
  AType visitNullLiteral(NullLiteral node) {
    return BottomAType.nullable;
  }

  @override
  AType visitRethrow(Rethrow node) {
    return BottomAType.nonNullable;
  }

  @override
  AType visitStaticGet(StaticGet node) {
    return binding.getGetterType(node.target);
  }

  @override
  AType visitStaticInvocation(StaticInvocation node) {
    return handleCall(node.arguments, node.target);
  }

  @override
  AType visitStaticSet(StaticSet node) {
    var value = visitExpression(node.value);
    var setterType = binding.getSetterType(node.target);
    checkAssignable(node.value, value, setterType);
    return value;
  }

  @override
  AType visitStringConcatenation(StringConcatenation node) {
    node.expressions.forEach(visitExpression);
    return extractor.stringType;
  }

  @override
  AType visitStringLiteral(StringLiteral node) {
    return extractor.stringType;
  }

  @override
  AType visitSuperMethodInvocation(SuperMethodInvocation node) {
    if (node.interfaceTarget == null) {
      return handleDynamicCall(thisType, node.arguments);
    } else {
      return handleCall(node.arguments, node.interfaceTarget,
          receiver: getSuperReceiverType(node.interfaceTarget));
    }
  }

  @override
  AType visitSuperPropertyGet(SuperPropertyGet node) {
    if (node.interfaceTarget == null) {
      return extractor.topType;
    } else {
      var receiver = getSuperReceiverType(node.interfaceTarget);
      var getterType = binding.getGetterType(node.interfaceTarget);
      return receiver.substituteType(getterType);
    }
  }

  @override
  AType visitSuperPropertySet(SuperPropertySet node) {
    var value = visitExpression(node.value);
    if (node.interfaceTarget != null) {
      var receiver = getSuperReceiverType(node.interfaceTarget);
      var setterType = binding.getSetterType(node.interfaceTarget);
      checkAssignable(node.value, value, receiver.substituteType(setterType));
    }
    return value;
  }

  @override
  AType visitSymbolLiteral(SymbolLiteral node) {
    return extractor.symbolType;
  }

  @override
  AType visitThisExpression(ThisExpression node) {
    return thisType;
  }

  @override
  AType visitThrow(Throw node) {
    // TODO escape value
    visitExpression(node.expression);
    return BottomAType.nonNullable;
  }

  @override
  AType visitTypeLiteral(TypeLiteral node) {
    return extractor.typeType;
  }

  @override
  AType visitVariableGet(VariableGet node) {
    if (node.promotedType != null) {
      // TODO: Ensure dataflow from variable base type
      return modifiers.augmentType(node.promotedType);
    }
    return getVariableType(node.variable);
  }

  @override
  AType visitVariableSet(VariableSet node) {
    var value = visitExpression(node.value);
    checkAssignable(node.value, value, getVariableType(node.variable));
    return value;
  }

  @override
  bool visitAssertStatement(AssertStatement node) {
    visitExpression(node.condition);
    if (node.message != null) {
      visitExpression(node.message);
    }
    return true;
  }

  @override
  bool visitBlock(Block node) {
    for (var statement in node.statements) {
      if (!visitStatement(statement)) return false;
    }
    return true;
  }

  @override
  bool visitBreakStatement(BreakStatement node) {
    return false;
  }

  @override
  bool visitContinueSwitchStatement(ContinueSwitchStatement node) {
    return false;
  }

  bool isTrueConstant(Expression node) {
    return node is BoolLiteral && node.value == true;
  }

  @override
  bool visitDoStatement(DoStatement node) {
    var bodyCompletes = visitStatement(node.body);
    checkConditionExpression(node.condition);
    return bodyCompletes && !isTrueConstant(node.condition);
  }

  @override
  bool visitEmptyStatement(EmptyStatement node) {
    return true;
  }

  @override
  bool visitExpressionStatement(ExpressionStatement node) {
    visitExpression(node.expression);
    return node.expression is! Throw && node.expression is! Rethrow;
  }

  @override
  bool visitForInStatement(ForInStatement node) {
    scope.variables[node.variable] = modifiers.augmentType(node.variable.type);
    var iterable = visitExpression(node.iterable);
    // TODO(asgerf): Store interface targets on for-in loops or desugar them,
    // instead of doing the ad-hoc resolution here.
    if (node.isAsync) {
      checkAssignable(
          node, getStreamElementType(iterable), getVariableType(node.variable));
    } else {
      checkAssignable(node, getIterableElementType(iterable),
          getVariableType(node.variable));
    }
    visitStatement(node.body);
    return true;
  }

  static final Name iteratorName = new Name('iterator');
  static final Name nextName = new Name('next');

  AType getIterableElementType(AType iterable) {
    if (iterable is InterfaceAType) {
      var iteratorGetter =
          baseHierarchy.getInterfaceMember(iterable.classNode, iteratorName);
      if (iteratorGetter == null) return extractor.topType;
      var iteratorType = Substitution
          .fromInterfaceType(iterable)
          .substituteType(binding.getGetterType(iteratorGetter));
      if (iteratorType is InterfaceAType) {
        var nextGetter =
            baseHierarchy.getInterfaceMember(iteratorType.classNode, nextName);
        if (nextGetter == null) return extractor.topType;
        return Substitution
            .fromInterfaceType(iteratorType)
            .substituteType(binding.getGetterType(nextGetter));
      }
    }
    return extractor.topType;
  }

  AType getStreamElementType(AType stream) {
    if (stream is InterfaceAType) {
      var asStream = hierarchy.getClassAsInstanceOf(
          stream.classNode, coreTypes.streamClass);
      if (asStream == null) return extractor.topType;
      var parameter = coreTypes.streamClass.typeParameters[0];
      var modifier = modifiers.newModifier();
      return asStream
          .getSubstitute(new TypeParameterAType(modifier, modifier, parameter));
    }
    return extractor.topType;
  }

  @override
  bool visitForStatement(ForStatement node) {
    node.variables.forEach(visitVariableDeclaration);
    if (node.condition != null) {
      checkConditionExpression(node.condition);
    }
    node.updates.forEach(visitExpression);
    visitStatement(node.body);
    return !isTrueConstant(node.condition);
  }

  @override
  bool visitFunctionDeclaration(FunctionDeclaration node) {
    handleNestedFunctionNode(node.function, node.variable);
    return true;
  }

  @override
  bool visitIfStatement(IfStatement node) {
    checkConditionExpression(node.condition);
    bool thenCompletes = visitStatement(node.then);
    bool elseCompletes =
        (node.otherwise != null) ? visitStatement(node.otherwise) : false;
    return thenCompletes || elseCompletes;
  }

  @override
  bool visitInvalidStatement(InvalidStatement node) {
    return false;
  }

  @override
  bool visitLabeledStatement(LabeledStatement node) {
    visitStatement(node.body);
    return true;
  }

  @override
  bool visitReturnStatement(ReturnStatement node) {
    if (node.expression != null) {
      if (returnType == null) {
        fail(node, 'Return of a value from void method');
      } else {
        var type = visitExpression(node.expression);
        if (currentAsyncMarker == AsyncMarker.Async) {
          type = unfutureType(type);
        }
        checkAssignable(node.expression, type, returnType);
      }
    }
    return false;
  }

  @override
  bool visitSwitchStatement(SwitchStatement node) {
    visitExpression(node.expression);
    for (var switchCase in node.cases) {
      switchCase.expressions.forEach(visitExpression);
      visitStatement(switchCase.body);
    }
    return false; // Must break out from an enclosing labeled statement.
  }

  @override
  bool visitTryCatch(TryCatch node) {
    bool bodyCompletes = visitStatement(node.body);
    bool catchCompletes = false;
    for (var catchClause in node.catches) {
      // TODO: Set precise types on catch parameters
      scope.variables[catchClause.exception] = extractor.topType;
      if (catchClause.stackTrace != null) {
        scope.variables[catchClause.stackTrace] = extractor.topType;
      }
      bool completes = visitStatement(catchClause.body);
      if (completes) {
        catchCompletes = true;
      }
    }
    return bodyCompletes || catchCompletes;
  }

  @override
  bool visitTryFinally(TryFinally node) {
    bool bodyCompletes = visitStatement(node.body);
    bool finalizerCompletes = visitStatement(node.finalizer);
    return bodyCompletes && finalizerCompletes;
  }

  @override
  bool visitVariableDeclaration(VariableDeclaration node) {
    assert(!scope.variables.containsKey(node));
    node.inferredValueOffset = modifiers.nextIndex;
    var type = scope.variables[node] = modifiers.augmentType(node.type);
    if (node.initializer != null) {
      checkAssignableExpression(node.initializer, type);
    }
    return true;
  }

  @override
  bool visitWhileStatement(WhileStatement node) {
    checkConditionExpression(node.condition);
    visitStatement(node.body);
    return !isTrueConstant(node.condition);
  }

  @override
  bool visitYieldStatement(YieldStatement node) {
    if (node.isYieldStar) {
      Class container = currentAsyncMarker == AsyncMarker.AsyncStar
          ? coreTypes.streamClass
          : coreTypes.iterableClass;
      var type = visitExpression(node.expression);
      var asContainer = type is InterfaceAType
          ? hierarchy.getTypeAsInstanceOf(type, container)
          : null;
      if (asContainer != null) {
        checkAssignable(
            node.expression, asContainer.typeArguments[0], yieldType);
      } else {
        fail(node.expression, '$type is not an instance of $container');
      }
    } else {
      checkAssignableExpression(node.expression, yieldType);
    }
    return true;
  }

  @override
  visitFieldInitializer(FieldInitializer node) {
    var type =
        thisSubstitution.substituteType(binding.getFieldType(node.field));
    checkAssignableExpression(node.value, type);
  }

  @override
  visitRedirectingInitializer(RedirectingInitializer node) {
    handleCall(node.arguments, node.target);
  }

  @override
  visitSuperInitializer(SuperInitializer node) {
    handleCall(node.arguments, node.target,
        receiver: hierarchy.getClassAsInstanceOf(
            currentClass, node.target.enclosingClass));
  }

  @override
  visitLocalInitializer(LocalInitializer node) {
    visitVariableDeclaration(node.variable);
  }

  @override
  visitInvalidInitializer(InvalidInitializer node) {}

  @override
  AType visitCheckLibraryIsLoaded(CheckLibraryIsLoaded node) {
    return extractor.topType;
  }

  @override
  AType visitLoadLibrary(LoadLibrary node) {
    return new InterfaceAType(
        new Value(coreTypes.futureClass, Flags.other),
        ValueSink.unassignable('return value of expression', node),
        coreTypes.futureClass,
        [extractor.topType]);
  }
}

/// Generates constraints for external code based on its type.
///
/// If [isCovariant] this generates constraints for values that can enter the
/// program from external code.  If [isContravariant], this generates constraints
/// for values that escape into external code.
class ExternalVisitor extends ATypeVisitor {
  final ConstraintExtractor extractor;
  final bool isCovariant, isContravariant;
  final bool isNice;

  CoreTypes get coreTypes => extractor.coreTypes;
  ConstraintBuilder get builder => extractor.builder;

  ExternalVisitor(
      this.extractor, this.isNice, this.isCovariant, this.isContravariant);

  ExternalVisitor.bivariant(this.extractor)
      : isNice = false,
        isCovariant = true,
        isContravariant = true;

  ExternalVisitor.covariant(this.extractor)
      : isNice = false,
        isCovariant = true,
        isContravariant = false;

  ExternalVisitor.contravariant(this.extractor)
      : isNice = false,
        isCovariant = false,
        isContravariant = true;

  ExternalVisitor get inverseVisitor {
    return new ExternalVisitor(extractor, isNice, isContravariant, isCovariant);
  }

  ExternalVisitor get bivariantVisitor {
    return new ExternalVisitor(extractor, isNice, true, true);
  }

  void visit(AType type) => type.accept(this);
  void visitBound(AType type) => type.accept(bivariantVisitor);
  void visitInverse(AType type) => type.accept(inverseVisitor);

  @override
  visitBottomAType(BottomAType type) {}

  @override
  visitFunctionAType(FunctionAType type) {
    var source = type.source;
    if (isCovariant && source is Key) {
      var anyValue = new Value(coreTypes.objectClass, Flags.other);
      builder.addAssignment(anyValue, source, Flags.all);
    }
    var sink = type.sink;
    if (isContravariant && sink is Key) {
      builder.addEscape(sink);
    }
    type.typeParameters.forEach(visitBound);
    type.positionalParameters.forEach(visitInverse);
    type.namedParameters.forEach(visitInverse);
    visit(type.returnType);
  }

  @override
  visitFunctionTypeParameterAType(FunctionTypeParameterAType type) {}

  @override
  visitInterfaceAType(InterfaceAType type) {
    var source = type.source;
    if (isCovariant && source is Key) {
      var value = extractor.getWorstCaseValue(type.classNode, isNice: isNice);
      builder.addAssignment(value, source, Flags.valueFlags);
    }
    var sink = type.sink;
    if (!isNice && isContravariant && sink is Key) {
      builder.addEscape(sink);
    }
    type.typeArguments.forEach(visitBound);
  }

  @override
  visitTypeParameterAType(TypeParameterAType type) {}
}

class AllocationVisitor extends ATypeVisitor {
  final ConstraintExtractor extractor;
  final Key object;
  bool isCovariant;

  AllocationVisitor(this.extractor, this.object, {this.isCovariant: true});

  AllocationVisitor get inverse =>
      new AllocationVisitor(extractor, object, isCovariant: !isCovariant);

  void visitSubterms(AType type) {
    type.accept(this);
  }

  void visit(AType type) {
    if (isCovariant) {
      var source = type.source;
      if (source is Key) {
        extractor.builder.addConstraint(new TypeArgumentConstraint(
            object, source, extractor.getWorstCaseValueForType(type)));
      }
      var sink = type.sink;
      if (sink is Key) {
        extractor.builder.addEscape(sink);
      }
    } else {
      extractor.builder.addEscape(type.source);
      var sink = type.sink;
      if (sink is Key) {
        extractor.builder.addConstraint(new TypeArgumentConstraint(
            object, sink, extractor.getWorstCaseValueForType(type)));
      }
    }
    type.accept(this);
  }

  @override
  visitBottomAType(BottomAType type) {}

  @override
  visitFunctionAType(FunctionAType type) {
    type.positionalParameters.forEach(inverse.visit);
    type.namedParameters.forEach(inverse.visit);
    visit(type.returnType);
  }

  @override
  visitFunctionTypeParameterAType(FunctionTypeParameterAType type) {}

  @override
  visitInterfaceAType(InterfaceAType type) {
    for (var argument in type.typeArguments) {
      visit(argument);
    }
  }

  @override
  visitTypeParameterAType(TypeParameterAType type) {}
}
