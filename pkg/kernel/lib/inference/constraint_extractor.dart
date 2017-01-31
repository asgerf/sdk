// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.type_checker;

import '../ast.dart';
import '../class_hierarchy.dart';
import '../core_types.dart';
import 'augmented_type.dart';
import 'binding.dart';
import 'constraints.dart';
import 'hierarchy.dart';
import 'package:kernel/inference/constraint_builder.dart';
import 'package:kernel/inference/key.dart';
import 'package:kernel/inference/value.dart';
import 'package:kernel/text/ast_to_text.dart';
import 'substitution.dart';

class ConstraintExtractor {
  CoreTypes coreTypes;
  Binding binding;
  ClassHierarchy baseHierarchy;
  AugmentedHierarchy hierarchy;
  ConstraintBuilder builder;

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

  AugmentedTypeAnnotator annotator;

  void checkProgram(Program program) {
    coreTypes ??= new CoreTypes(program);
    baseHierarchy ??= new ClassHierarchy(program);
    binding ??= new Binding(coreTypes);
    hierarchy ??= new AugmentedHierarchy(baseHierarchy, binding);
    builder ??= new ConstraintBuilder(hierarchy);
    annotator ??= new AugmentedTypeAnnotator(binding);
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
    for (var library in program.libraries) {
      if (library.importUri.scheme == 'dart') continue;
      for (var class_ in library.classes) {
        baseHierarchy.forEachOverridePair(class_,
            (Member ownMember, Member superMember, bool isSetter) {
          checkOverride(class_, ownMember, superMember, isSetter);
        });
      }
    }

    for (var library in program.libraries) {
      if (library.importUri.scheme == 'dart') continue;
      for (var class_ in library.classes) {
        for (var member in class_.members) {
          analyzeMember(member);
        }
      }
      for (var procedure in library.procedures) {
        analyzeMember(procedure);
      }
      for (var field in library.fields) {
        analyzeMember(field);
      }
    }
  }

  void analyzeMember(Member member) {
    var class_ = member.enclosingClass;
    var classBank = class_ == null ? null : binding.getClassBank(class_);
    var visitor = new TypeCheckingVisitor(
        this, member, binding.getMemberBank(member), classBank);
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
    from.generateSubtypeConstraints(to, builder);
  }

  /// Indicates that type checking failed.
  void fail(TreeNode where, String message) {
    print('$where: $message');
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

class TypeCheckingVisitor
    implements
        ExpressionVisitor<AType>,
        StatementVisitor<Null>,
        MemberVisitor<Null>,
        InitializerVisitor<Null> {
  final ConstraintExtractor checker;
  final Member currentMember;
  final ModifierBank modifiers;
  final ClassBank classModifiers;

  CoreTypes get coreTypes => checker.coreTypes;
  ClassHierarchy get baseHierarchy => checker.baseHierarchy;
  AugmentedHierarchy get hierarchy => checker.hierarchy;
  Binding get binding => checker.binding;
  ConstraintBuilder get builder => checker.builder;
  Class get currentClass => currentMember.enclosingClass;

  InterfaceAType thisType;
  Substitution thisSubstitution;

  AType returnType;
  AType yieldType;
  AsyncMarker currentAsyncMarker;

  final LocalScope scope = new LocalScope();

  TypeCheckingVisitor(
      this.checker, this.currentMember, this.modifiers, this.classModifiers);

  void checkTypeBound(TreeNode where, AType type, AType bound) {
    type.generateSubBoundConstraint(bound, builder);
  }

  void checkAssignable(TreeNode where, AType from, AType to) {
    checker.checkAssignable(where, from, to, scope);
  }

  void checkAssignableExpression(Expression from, AType to) {
    checker.checkAssignable(from, visitExpression(from), to, scope);
  }

  void checkConditionExpression(Expression condition) {
    checkAssignableExpression(condition, checker.conditionType);
  }

  void fail(TreeNode node, String message) {
    checker.fail(node, message);
  }

  AType visitExpression(Expression node) => node.accept(this);

  void visitStatement(Statement node) {
    node.accept(this);
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
          value, ValueSink.error('this type in $class_'), class_, thisTypeArgs);
      thisSubstitution = Substitution.fromInterfaceType(thisType);
    } else {
      thisSubstitution = Substitution.empty;
    }
    recordClassTypeParameterBounds();
    currentMember.accept(this);
  }

  visitField(Field node) {
    FieldBank modifiers = this.modifiers;
    var fieldType = thisSubstitution.substituteType(modifiers.type);
    if (node.initializer != null) {
      checkAssignableExpression(node.initializer, fieldType);
    }
  }

  visitConstructor(Constructor node) {
    returnType = null;
    yieldType = null;
    recordParameterTypes(modifiers, node.function);
    node.initializers.forEach(visitInitializer);
    handleFunctionBody(node.function);
  }

  visitProcedure(Procedure node) {
    FunctionMemberBank modifiers = this.modifiers;
    var ret = thisSubstitution.substituteType(modifiers.returnType);
    returnType = _getInternalReturnType(node.function.asyncMarker, ret);
    yieldType = _getYieldType(node.function.asyncMarker, ret);
    recordParameterTypes(modifiers, node.function);
    handleFunctionBody(node.function);
  }

  void recordClassTypeParameterBounds() {
    var class_ = currentClass;
    if (class_ == null) return;
    var typeParamters = class_.typeParameters;
    for (int i = 0; i < typeParamters.length; ++i) {
      scope.typeParameterBounds[typeParamters[i]] =
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
      checker.annotator.variableTypes[variable] = type;
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
      visitStatement(node.body);
    }
    currentAsyncMarker = oldAsyncMarker;
  }

  FunctionAType handleNestedFunctionNode(FunctionNode node) {
    for (var parameter in node.typeParameters) {
      scope.typeParameterBounds[parameter] =
          modifiers.augmentBound(parameter.bound);
    }
    for (var parameter in node.positionalParameters) {
      scope.variables[parameter] = modifiers.augmentType(parameter.type);
    }
    for (var parameter in node.namedParameters) {
      scope.variables[parameter] = modifiers.augmentType(parameter.type);
    }
    AType augmentedReturnType = modifiers.augmentType(node.returnType);
    var oldReturn = returnType;
    var oldYield = yieldType;
    returnType = _getInternalReturnType(node.asyncMarker, augmentedReturnType);
    yieldType = _getYieldType(node.asyncMarker, augmentedReturnType);
    handleFunctionBody(node);
    returnType = oldReturn;
    yieldType = oldYield;
    var key = modifiers.newModifier();
    return new FunctionAType(
        key,
        key,
        node.typeParameters.map(getTypeParameterBound).toList(growable: false),
        node.requiredParameterCount,
        node.positionalParameters.map(getVariableType).toList(growable: false),
        node.namedParameters.map((v) => v.name).toList(growable: false),
        node.namedParameters.map(getVariableType).toList(growable: false),
        augmentedReturnType);
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
    var typeArguments =
        modifiers.augmentTypeList(arguments.types).toList(growable: false);
    if (typeArguments.length != typeParameters.length) {
      fail(arguments, 'Wrong number of type arguments');
      return BottomAType.nonNullable;
    }
    var instantiation = Substitution.fromPairs(typeParameters, typeArguments);
    var substitution = Substitution.either(receiver, instantiation);
    for (int i = 0; i < typeParameters.length; ++i) {
      var argument = typeArguments[i];
      var bound = substitution.substituteBound(target.typeParameters[i]);
      checkTypeBound(arguments, argument, bound);
    }
    for (int i = 0; i < arguments.positional.length; ++i) {
      var expectedType =
          substitution.substituteType(target.positionalParameters[i]);
      print('${target.positionalParameters[i]} became $expectedType');
      assert(!expectedType.containsFunctionTypeParameter);
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
        return checker.escapingType;

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
        return checker.escapingType;

      case AsyncMarker.SyncYielding:
        return returnType;

      default:
        throw 'Unexpected async marker: $asyncMarker';
    }
  }

  @override
  AType visitAsExpression(AsExpression node) {
    visitExpression(node.operand);
    return modifiers.augmentType(node.type);
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
    return checker.boolType;
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

  @override
  AType visitConstructorInvocation(ConstructorInvocation node) {
    Constructor target = node.target;
    Arguments arguments = node.arguments;
    Class class_ = target.enclosingClass;
    var typeArguments = modifiers.augmentTypeList(arguments.types);
    // Substitution substitution =
    //     Substitution.fromPairs(class_.typeParameters, typeArguments);
    handleCall(arguments, target);
    var modifier = modifiers.newModifier();
    builder.addConstraint(new ValueConstraint(
        modifier, new Value(class_, flagsFromExactClass(class_))));
    // TODO: Generate TypeArgumentConstraints
    return new InterfaceAType(
        modifier,
        ValueSink.error('result of an expression'),
        target.enclosingClass,
        typeArguments);
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
    return checker.doubleType;
  }

  @override
  AType visitFunctionExpression(FunctionExpression node) {
    return handleNestedFunctionNode(node.function);
  }

  @override
  AType visitIntLiteral(IntLiteral node) {
    return checker.intType;
  }

  @override
  AType visitInvalidExpression(InvalidExpression node) {
    return BottomAType.nonNullable;
  }

  @override
  AType visitIsExpression(IsExpression node) {
    visitExpression(node.operand);
    return checker.boolType;
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
    var typeArgument = modifiers.augmentType(node.typeArgument);
    for (var item in node.expressions) {
      checkAssignableExpression(item, typeArgument);
    }
    var modifier = modifiers.newModifier();
    builder.addConstraint(new ValueConstraint(
        modifier, new Value(coreTypes.listClass, Flags.other)));
    return new InterfaceAType(
        modifier,
        ValueSink.error('result of an expression'),
        coreTypes.listClass,
        <AType>[typeArgument]);
  }

  @override
  AType visitLogicalExpression(LogicalExpression node) {
    checkConditionExpression(node.left);
    checkConditionExpression(node.right);
    return checker.boolType;
  }

  @override
  AType visitMapLiteral(MapLiteral node) {
    var keyType = modifiers.augmentType(node.keyType);
    var valueType = modifiers.augmentType(node.valueType);
    for (var entry in node.entries) {
      checkAssignableExpression(entry.key, keyType);
      checkAssignableExpression(entry.value, valueType);
    }
    var modifier = modifiers.newModifier();
    builder.addConstraint(new ValueConstraint(
        modifier, new Value(coreTypes.mapClass, Flags.other)));
    return new InterfaceAType(
        modifier,
        ValueSink.error('result of an expression'),
        coreTypes.mapClass,
        <AType>[keyType, valueType]);
  }

  AType handleDynamicCall(AType receiver, Arguments arguments) {
    // TODO: Escape values
    arguments.positional.forEach(visitExpression);
    arguments.named.forEach((NamedExpression n) => visitExpression(n.value));
    return checker.topType;
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
    var instantiation = Substitution.instantiateFunctionType(typeArguments);
    for (int i = 0; i < typeArguments.length; ++i) {
      checkTypeBound(where, typeArguments[i],
          instantiation.substituteBound(function.typeParameters[i]));
    }
    for (int i = 0; i < arguments.positional.length; ++i) {
      var expectedType = instantiation
          .substituteType(function.positionalParameters[i], covariant: false);
      checkAssignableExpression(arguments.positional[i], expectedType);
    }
    for (int i = 0; i < arguments.named.length; ++i) {
      var argument = arguments.named[i];
      bool found = false;
      // TODO: exploit that named parameters are sorted.
      for (int j = 0; j < function.namedParameters.length; ++j) {
        if (argument.name == function.namedParameterNames[j]) {
          var expectedType = instantiation
              .substituteType(function.namedParameters[j], covariant: false);
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
        return checker.intType;
      }
      if (class1 == coreTypes.doubleClass || class2 == coreTypes.doubleClass) {
        return checker.doubleType;
      }
    }
    return checker.numType;
  }

  @override
  AType visitMethodInvocation(MethodInvocation node) {
    var target = node.interfaceTarget;
    if (target == null) {
      var receiver = visitExpression(node.receiver);
      if (node.name.name == '==') {
        // TODO: Handle value escaping through == operator.
        visitExpression(node.arguments.positional.single);
        return checker.boolType;
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
      visitExpression(node.receiver);
      return checker.topType;
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
      visitExpression(node.receiver);
    }
    return value;
  }

  @override
  AType visitNot(Not node) {
    checkConditionExpression(node.operand);
    return checker.boolType;
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
    return checker.stringType;
  }

  @override
  AType visitStringLiteral(StringLiteral node) {
    return checker.stringType;
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
      return checker.topType;
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
    return checker.symbolType;
  }

  @override
  AType visitThisExpression(ThisExpression node) {
    return thisType;
  }

  @override
  AType visitThrow(Throw node) {
    visitExpression(node.expression);
    return BottomAType.nonNullable;
  }

  @override
  AType visitTypeLiteral(TypeLiteral node) {
    return checker.typeType;
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
  visitAssertStatement(AssertStatement node) {
    visitExpression(node.condition);
    if (node.message != null) {
      visitExpression(node.message);
    }
  }

  @override
  visitBlock(Block node) {
    node.statements.forEach(visitStatement);
  }

  @override
  visitBreakStatement(BreakStatement node) {}

  @override
  visitContinueSwitchStatement(ContinueSwitchStatement node) {}

  @override
  visitDoStatement(DoStatement node) {
    visitStatement(node.body);
    checkConditionExpression(node.condition);
  }

  @override
  visitEmptyStatement(EmptyStatement node) {}

  @override
  visitExpressionStatement(ExpressionStatement node) {
    visitExpression(node.expression);
  }

  @override
  visitForInStatement(ForInStatement node) {
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
  }

  static final Name iteratorName = new Name('iterator');
  static final Name nextName = new Name('next');

  AType getIterableElementType(AType iterable) {
    if (iterable is InterfaceAType) {
      var iteratorGetter =
          baseHierarchy.getInterfaceMember(iterable.classNode, iteratorName);
      if (iteratorGetter == null) return checker.topType;
      var iteratorType = Substitution
          .fromInterfaceType(iterable)
          .substituteType(binding.getGetterType(iteratorGetter));
      if (iteratorType is InterfaceAType) {
        var nextGetter =
            baseHierarchy.getInterfaceMember(iteratorType.classNode, nextName);
        if (nextGetter == null) return checker.topType;
        return Substitution
            .fromInterfaceType(iteratorType)
            .substituteType(binding.getGetterType(nextGetter));
      }
    }
    return checker.topType;
  }

  AType getStreamElementType(AType stream) {
    if (stream is InterfaceAType) {
      var asStream = hierarchy.getClassAsInstanceOf(
          stream.classNode, coreTypes.streamClass);
      if (asStream == null) return checker.topType;
      var parameter = coreTypes.streamClass.typeParameters[0];
      var modifier = modifiers.newModifier();
      return asStream
          .getSubstitute(new TypeParameterAType(modifier, modifier, parameter));
    }
    return checker.topType;
  }

  @override
  visitForStatement(ForStatement node) {
    node.variables.forEach(visitVariableDeclaration);
    if (node.condition != null) {
      checkConditionExpression(node.condition);
    }
    node.updates.forEach(visitExpression);
    visitStatement(node.body);
  }

  @override
  visitFunctionDeclaration(FunctionDeclaration node) {
    handleNestedFunctionNode(node.function);
  }

  @override
  visitIfStatement(IfStatement node) {
    checkConditionExpression(node.condition);
    visitStatement(node.then);
    if (node.otherwise != null) {
      visitStatement(node.otherwise);
    }
  }

  @override
  visitInvalidStatement(InvalidStatement node) {}

  @override
  visitLabeledStatement(LabeledStatement node) {
    visitStatement(node.body);
  }

  @override
  visitReturnStatement(ReturnStatement node) {
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
  }

  @override
  visitSwitchStatement(SwitchStatement node) {
    visitExpression(node.expression);
    for (var switchCase in node.cases) {
      switchCase.expressions.forEach(visitExpression);
      visitStatement(switchCase.body);
    }
  }

  @override
  visitTryCatch(TryCatch node) {
    visitStatement(node.body);
    for (var catchClause in node.catches) {
      visitStatement(catchClause.body);
    }
  }

  @override
  visitTryFinally(TryFinally node) {
    visitStatement(node.body);
    visitStatement(node.finalizer);
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    assert(!scope.variables.containsKey(node));
    var type = scope.variables[node] = modifiers.augmentType(node.type);
    if (node.initializer != null) {
      checkAssignableExpression(node.initializer, type);
    }
    checker.annotator.variableTypes[node] = type;
  }

  @override
  visitWhileStatement(WhileStatement node) {
    checkConditionExpression(node.condition);
    visitStatement(node.body);
  }

  @override
  visitYieldStatement(YieldStatement node) {
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
}

class AugmentedTypeAnnotator implements Annotator {
  final Binding binding;
  final Map<VariableDeclaration, AType> variableTypes =
      <VariableDeclaration, AType>{};

  AugmentedTypeAnnotator(this.binding);

  bool get showDartTypes => false;

  @override
  void annotateField(Printer printer, Field node) {
    binding.getFieldType(node).print(printer);
  }

  @override
  void annotateReturn(Printer printer, FunctionNode node) {
    var parent = node.parent;
    if (parent is Member) {
      binding.getFunctionBank(parent).type.returnType.print(printer);
    } else {
      printer.write('<?>');
    }
  }

  @override
  void annotateVariable(Printer printer, VariableDeclaration node) {
    var type = variableTypes[node];
    if (type == null) {
      printer.write('<?>');
    } else {
      type.print(printer);
    }
  }
}
