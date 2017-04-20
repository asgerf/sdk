// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.constraint_extractor;

import 'package:kernel/util/class_set.dart';
import 'package:meta/meta.dart';

import '../../ast.dart';
import '../../class_hierarchy.dart';
import '../../core_types.dart';
import '../constraints.dart';
import '../storage_location.dart';
import '../value.dart';
import 'augmented_hierarchy.dart';
import 'augmented_substitution.dart';
import 'augmented_type.dart';
import 'backend_core_types.dart';
import 'binding.dart';
import 'common_values.dart';
import 'control_flow_state.dart';
import 'dynamic_index.dart';
import 'external_model.dart';
import 'source_sink_translator.dart';
import 'subtype_translator.dart';
import 'type_augmentor.dart';
import 'value_sink.dart';
import 'value_source.dart';

typedef void TypeErrorCallback(TreeNode where, String message);

/// Method names which are treated specially for numbers, in that the return
/// type is determined based on both receiver and argument type.
final List<String> overloadedArithmeticOperatorNames = <String>[
  '+',
  '-',
  '*',
  'remainder',
  '%',
];

/// The result of extracting a constraint system from a set of libaries.
class ExtractionResult {
  final ConstraintSystem constraintSystem;
  final Binding binding;

  ExtractionResult(this.constraintSystem, this.binding);
}

/// Extracts subtyping judgements from the program, which are then translated
/// into constraints.
class ConstraintExtractor {
  final ExternalModel externalModel;
  final BackendCoreTypes backendCoreTypes;
  final TypeErrorCallback typeErrorCallback;

  ClassHierarchy hierarchy;
  CommonValues common;
  CoreTypes coreTypes;
  ValueLattice lattice;

  ConstraintSystem _constraintSystem;
  Binding _binding;

  AugmentedHierarchy _augmentedHierarchy;
  ClassSetDomain _instantiatedClasses;
  SubtypeTranslator _builder;
  DynamicIndex _dynamicIndex;

  ConstraintExtractor(
      {@required this.externalModel,
      @required this.backendCoreTypes,
      this.typeErrorCallback,
      this.coreTypes,
      this.hierarchy,
      this.lattice,
      this.common});

  ExtractionResult extractFromProgram(Program program) {
    // Build shared data structures if not provided.
    coreTypes ??= new CoreTypes(program);
    hierarchy ??= new ClassHierarchy(program);
    lattice ??= new ValueLattice(coreTypes, hierarchy);
    common ??= new CommonValues(coreTypes, backendCoreTypes, lattice);

    // Build output data structures.
    _constraintSystem = new ConstraintSystem();
    var protector = new ProtectCleanSupertype(coreTypes, common);
    _binding = new Binding(_constraintSystem, coreTypes, externalModel,
        cleanTypeConverter: protector.convertSupertype);

    // Build internal data structures used by for extraction.
    _dynamicIndex = new DynamicIndex(program);
    _augmentedHierarchy = new AugmentedHierarchy(hierarchy, _binding);
    _builder = new SubtypeTranslator(
        _constraintSystem, _augmentedHierarchy, lattice, common, coreTypes);
    _instantiatedClasses = lattice.instantiatedClasses;

    // Build the constraint system.
    handleLiteralClassTypeBounds();
    handleMainEntryPoint(program);

    // Build constraints from inheritance and member overrides.
    for (var library in program.libraries) {
      for (var class_ in library.classes) {
        handleClassInheritance(class_);
        hierarchy.forEachOverridePair(class_,
            (Member ownMember, Member superMember, bool isSetter) {
          handleMemberOverride(class_, ownMember, superMember, isSetter);
        });
      }
    }

    // Build constraints from member bodies.
    for (var library in program.libraries) {
      bool isUncheckedLibrary = library.importUri.scheme == 'dart';
      for (var class_ in library.classes) {
        for (var member in class_.members) {
          handleMemberBody(member, isUncheckedLibrary);
        }
      }
      for (var procedure in library.procedures) {
        handleMemberBody(procedure, isUncheckedLibrary);
      }
      for (var field in library.fields) {
        handleMemberBody(field, isUncheckedLibrary);
      }
    }

    return new ExtractionResult(_constraintSystem, _binding);
  }

  /// Generates constraints for the initial call to the program's main entry
  /// point.
  void handleMainEntryPoint(Program program) {
    var function = program.mainMethod?.function;
    if (function != null && function.positionalParameters.isNotEmpty) {
      var bank = _binding.getFunctionBank(program.mainMethod);
      var stringListType = new InterfaceAType(common.fixedLengthListValue,
          ValueSink.nowhere, coreTypes.listClass, [common.stringType]);
      _builder.setOwner(program.mainMethod);
      checkAssignable(
          program.mainMethod,
          stringListType,
          bank.positionalParameters.first,
          new GlobalScope(_binding),
          program.mainMethod.fileOffset);
    }
  }

  /// Pollutes the upper bounds of the type parameters to literal lists and maps
  /// so that we don't need to check the bounds at every literal.
  void handleLiteralClassTypeBounds() {
    var literalValues = [
      backendCoreTypes.growableListValue,
      backendCoreTypes.immutableListValue,
      backendCoreTypes.linkedHashMapValue,
      backendCoreTypes.immutableMapValue,
    ];
    for (var value in literalValues) {
      var class_ = value.baseClass;
      if (class_.isInExternalLibrary) continue;
      var bank = _binding.getClassBank(value.baseClass);
      for (var bound in bank.typeParameterBounds) {
        var upperBound = bound.source as StorageLocation;
        _builder.setOwner(class_);
        _builder.setFileOffset(class_.fileOffset);
        _builder
            .addConstraint(new ValueConstraint(upperBound, common.anyValue));
      }
    }
  }

  /// Generates constraints for the 'extends' and 'implements' clauses of the
  /// given class to ensure dataflow between the type parameter bounds.
  void handleClassInheritance(Class class_) {
    _builder.setOwner(class_);
    _builder.setFileOffset(class_.fileOffset);
    if (externalModel.forceCleanSupertypes(class_)) return;
    var scope = new GlobalScope(_binding);
    var bank = _binding.getClassBank(class_);
    for (var supertype in bank.supertypes) {
      var substitution = Substitution.fromSupertype(supertype);
      var superBank = _binding.getClassBank(supertype.classNode);
      for (int i = 0; i < supertype.typeArguments.length; ++i) {
        var typeArgument = supertype.typeArguments[i];
        var bound = superBank.typeParameterBounds[i];
        _builder.addSubBound(
            typeArgument, substitution.substituteBound(bound), scope);
      }
    }
  }

  /// Generates constraints to account for the fact that an interface call to
  /// [superMember] may concretely target [ownMember] or one of its overriders.
  ///
  /// This is not called for transitive overrides. Even if [ownMember] is
  /// abstract, we must generate constraints so that the constraints system as a
  /// whole connects the super member with every concrete implementation.
  void handleMemberOverride(
      Class host, Member ownMember, Member superMember, bool isSetter) {
    _builder.setOwner(ownMember);
    if (isSetter) {
      checkAssignable(
          ownMember,
          setterType(host, superMember),
          setterType(host, ownMember),
          new GlobalScope(_binding),
          ownMember.fileOffset);
    } else {
      var ownMemberType = getterType(host, ownMember);
      var superMemberType = getterType(host, superMember);
      if (externalModel.forceExternal(superMember) &&
          host.enclosingLibrary.importUri.scheme == 'dart') {
        // Remove all value sinks from the super member to avoid polluting its
        // return type (which should be based on the external model).
        // We still need to generate constraints from its arguments to the
        // overridden member, to ensure the body of the overridden member can be
        // compiled soundly.
        superMemberType = new ProtectSinks().convertType(superMemberType);
      }
      checkAssignable(ownMember, ownMemberType, superMemberType,
          new GlobalScope(_binding), ownMember.fileOffset);
    }
  }

  AType getterType(Class host, Member member) {
    var substitution =
        _augmentedHierarchy.getClassAsInstanceOf(host, member.enclosingClass);
    var type = substitution.substituteType(_binding.getGetterType(member));
    assert(type.isClosed(host.typeParameters));
    return type;
  }

  AType setterType(Class host, Member member) {
    var substitution =
        _augmentedHierarchy.getClassAsInstanceOf(host, member.enclosingClass);
    var type = substitution.substituteType(_binding.getSetterType(member));
    assert(type.isClosed(host.typeParameters));
    return type;
  }

  /// Generates constraints for the body of the given member, possibly using
  /// the external model.
  void handleMemberBody(Member member, bool isUncheckedLibrary) {
    _builder.setOwner(member);
    var class_ = member.enclosingClass;
    var classBank = class_ == null ? null : _binding.getClassBank(class_);
    var visitor = new ConstraintExtractorVisitor(this, member,
        _binding.getMemberBank(member), classBank, isUncheckedLibrary);
    visitor.analyzeMember();
  }

  /// Check that [from] is a subtype of [to].
  ///
  /// [where] is an AST node indicating roughly where the check is required.
  void checkAssignable(TreeNode where, AType from, AType to,
      TypeParameterScope scope, int fileOffset) {
    // assert(!from.containsPlaceholder);
    // assert(!to.containsPlaceholder);
    // TODO: Expose type parameters in 'scope' and check closedness
    assert(from != null);
    assert(to != null);
    try {
      _builder.setFileOffset(fileOffset);
      _builder.addSubtype(from, to, scope);
    } on UnassignableSinkError catch (e) {
      e.assignmentLocation = where.location;
      rethrow;
    }
  }

  /// Indicates that type checking failed.
  void reportTypeError(TreeNode where, String message) {
    if (typeErrorCallback != null) {
      typeErrorCallback(where, message);
    }
  }

  int getValueSetFlagsFromInterfaceType(DartType type) {
    if (type is InterfaceType) {
      return getValueSetFlagsFromInterfaceClass(type.classNode);
    } else if (type is FunctionType) {
      return ValueFlags.null_ | ValueFlags.other;
    } else {
      return ValueFlags.null_;
    }
  }

  int getValueSetFlagsFromInterfaceClass(Class classNode) {
    return lattice.getValueSetFlagsForInterface(classNode);
  }

  Value getWorstCaseValueForType(AType type, {bool isClean: false}) {
    if (type is InterfaceAType) {
      return getWorstCaseValue(type.classNode, isClean: isClean);
    }
    if (type is FunctionAType) {
      return isClean ? common.functionValue : common.nullableFunctionValue;
    }
    if (type is TypeParameterAType || type is FunctionTypeParameterAType) {
      return isClean ? Value.bottom : common.nullValue;
    }
    return common.anyValue;
  }

  Value getWorstCaseValue(Class classNode, {bool isClean: false}) {
    if (isClean) return getCleanValue(classNode);
    if (classNode == coreTypes.intClass) return common.nullableIntValue;
    if (classNode == coreTypes.doubleClass) return common.nullableDoubleValue;
    if (classNode == coreTypes.numClass) return common.nullableNumValue;
    if (classNode == coreTypes.stringClass) return common.nullableStringValue;
    if (classNode == coreTypes.boolClass) return common.nullableBoolValue;
    if (classNode == coreTypes.nullClass) return common.nullValue;
    if (classNode == coreTypes.objectClass) return common.anyValue;

    ClassSet classSet = _instantiatedClasses.getSubtypesOf(classNode);
    Class baseClass = classSet.getCommonBaseClass();
    int exactness = classSet.isSingleton ? 0 : ValueFlags.inexactBaseClass;

    return new Value(baseClass,
        ValueFlags.null_ | ValueFlags.other | ValueFlags.escaping | exactness);
  }

  Value getCleanValue(Class classNode) {
    if (classNode == coreTypes.intClass) return common.intValue;
    if (classNode == coreTypes.doubleClass) return common.doubleValue;
    if (classNode == coreTypes.numClass) return common.numValue;
    if (classNode == coreTypes.stringClass) return common.stringValue;
    if (classNode == coreTypes.boolClass) return common.boolValue;
    if (classNode == coreTypes.nullClass) return common.nullValue;

    // As a special case, a type annotation of 'Object' is treated as nullable,
    // even for clean externals.
    if (classNode == coreTypes.objectClass) return common.anyValue;

    ClassSet classSet = _instantiatedClasses.getSubtypesOf(classNode);
    Class baseClass = classSet.getCommonBaseClass();
    int exactness = classSet.isSingleton ? 0 : ValueFlags.inexactBaseClass;

    return new Value(baseClass, ValueFlags.other | exactness);
  }

  Value getExactClassValue(Class class_) {
    return new Value(class_, valueFlagFromExactClass(class_));
  }

  Value getBaseClassValue(Class class_) {
    return new Value(class_, valueFlagsFromBaseClass(class_));
  }

  int valueFlagFromExactClass(Class class_) {
    if (class_ == coreTypes.intClass) return ValueFlags.integer;
    if (class_ == coreTypes.doubleClass) return ValueFlags.double_;
    if (class_ == coreTypes.stringClass) return ValueFlags.string;
    if (class_ == coreTypes.boolClass) return ValueFlags.boolean;
    return ValueFlags.other;
  }

  int valueFlagsFromBaseClass(Class class_) {
    if (class_ == coreTypes.intClass) return ValueFlags.integer;
    if (class_ == coreTypes.doubleClass) return ValueFlags.double_;
    if (class_ == coreTypes.stringClass) return ValueFlags.string;
    if (class_ == coreTypes.boolClass) return ValueFlags.boolean;
    if (class_ == coreTypes.objectClass) return ValueFlags.allValueSets;
    return ValueFlags.other;
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
      return binding.getClassBank(parent).typeParameterBounds[index];
    } else {
      FunctionNode function = parent;
      Member member = function.parent;
      int index = function.typeParameters.indexOf(parameter);
      return binding
          .getFunctionBank(member)
          .interfaceType
          .typeParameterBounds[index];
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
        StatementVisitor<Null>,
        MemberVisitor<Null>,
        InitializerVisitor<Null> {
  final ConstraintExtractor extractor;
  final Member currentMember;
  final MemberBank bank;
  final ClassBank classBank;
  TypeAugmentor augmentor;
  Reference defaultListFactoryReference;
  Reference listFromIterableReference;
  Reference linkedHashSetFromIterableReference;

  CoreTypes get coreTypes => extractor.coreTypes;
  ClassHierarchy get hierarchy => extractor.hierarchy;
  AugmentedHierarchy get augmentedHierarchy => extractor._augmentedHierarchy;
  Binding get binding => extractor._binding;
  SubtypeTranslator get builder => extractor._builder;
  ExternalModel get externalModel => extractor.externalModel;
  Class get currentClass => currentMember.enclosingClass;
  CommonValues get common => extractor.common;

  Uri get currentUri => currentMember.enclosingLibrary.importUri;
  bool get isFileUri => currentUri.scheme == 'file';

  InterfaceAType thisType;
  Substitution thisSubstitution;

  AType returnType;
  AType yieldType;
  AsyncMarker currentAsyncMarker;
  bool seenTypeError = false;

  final ControlFlowState controlFlow = new ControlFlowState();

  final LocalScope scope = new LocalScope();
  final bool isUncheckedLibrary;

  ConstraintExtractorVisitor(this.extractor, this.currentMember, this.bank,
      this.classBank, this.isUncheckedLibrary) {
    defaultListFactoryReference =
        extractor.backendCoreTypes.listFactory.reference;
    listFromIterableReference =
        coreTypes.tryGetMember('dart:core', 'List', 'from')?.reference;
    linkedHashSetFromIterableReference = coreTypes
        .tryGetMember('dart:collection', 'LinkedHashSet', 'from')
        ?.reference;
  }

  void checkTypeBound(TreeNode where, AType type, AType bound,
      [int fileOffset = TreeNode.noOffset]) {
    builder.setFileOffset(fileOffset);
    builder.addSubBound(type, bound, scope);
  }

  void checkAssignable(TreeNode where, AType from, AType to,
      [int fileOffset = TreeNode.noOffset]) {
    if (fileOffset == TreeNode.noOffset) {
      fileOffset = where.fileOffset;
    }
    extractor.checkAssignable(where, from, to, scope, fileOffset);
  }

  AType checkAssignableExpression(Expression from, AType to,
      [int fileOffset = TreeNode.noOffset]) {
    if (fileOffset == TreeNode.noOffset) {
      fileOffset = from.fileOffset;
    }
    var type = visitExpression(from);
    extractor.checkAssignable(from, type, to, scope, fileOffset);
    return type;
  }

  void checkConditionExpression(Expression condition) {
    // No constraints are needed, but we must visit the expression subtree.
    visitExpression(condition);
  }

  void fail(TreeNode node, String message) {
    if (!isUncheckedLibrary) {
      extractor.reportTypeError(node, message);
    }
    seenTypeError = true;
  }

  AType visitExpression(Expression node) {
    AType type = node.accept(this);
    var source = type.source;
    if (source is StorageLocation && source.owner == bank.owner) {
      node.dataflowValueOffset = source.index;
    } else {
      var newLocation = bank.newLocation();
      if (node.fileOffset != TreeNode.noOffset) {
        builder.setFileOffset(node.fileOffset);
      }
      builder.addAssignment(source, newLocation);
      type = type.withSourceAndSink(source: newLocation);
      node.dataflowValueOffset = newLocation.index;
    }
    return type;
  }

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
    augmentor = bank.getFreshAugmentor(binding.globalAugmentorScope);
    if (!identical(bank.concreteType, bank.interfaceType)) {
      checkAssignable(currentMember, bank.concreteType, bank.interfaceType);
    }
    var class_ = currentClass;
    if (class_ != null) {
      var typeParameters = class_.typeParameters;
      var thisTypeArgs = <AType>[];
      for (int i = 0; i < typeParameters.length; ++i) {
        var parameter = typeParameters[i];
        var bound = classBank.typeParameterBounds[i];
        scope.typeParameterBounds[parameter] = bound;
        // TODO
        thisTypeArgs
            .add(new TypeParameterAType(Value.bottom, bound.sink, parameter));
      }
      thisType = new InterfaceAType(
          extractor.getBaseClassValue(class_),
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
    FieldBank bank = this.bank;
    var fieldType = thisSubstitution.substituteType(bank.concreteType);
    bool treatAsExternal = node.isExternal || externalModel.forceExternal(node);
    if (node.initializer != null && !treatAsExternal) {
      checkAssignableExpression(node.initializer, fieldType, node.fileOffset);
      if (seenTypeError) {
        treatAsExternal = true;
      }
    }
    if (treatAsExternal) {
      builder.setFileOffset(node.fileOffset);
      new ExternalVisitor(extractor,
              isClean: externalModel.isCleanExternal(node),
              isCovariant: !node.isFinal,
              isContravariant: true)
          .visit(bank.concreteType);
    }
    if (externalModel.isEntryPoint(node)) {
      builder.setFileOffset(node.fileOffset);
      new ExternalVisitor(extractor,
              isClean: false, isCovariant: true, isContravariant: !node.isFinal)
          .visit(bank.concreteType);
    }
  }

  visitConstructor(Constructor node) {
    returnType = null;
    yieldType = null;
    FunctionMemberBank bank = this.bank;
    recordParameterTypes(bank, node.function);
    node.initializers.forEach(visitInitializer);
    bool treatAsExternal = node.isExternal || externalModel.forceExternal(node);
    if (!treatAsExternal) {
      handleFunctionBody(node.function);
      if (seenTypeError) {
        treatAsExternal = true;
      }
    }
    if (treatAsExternal) {
      builder.setFileOffset(node.fileOffset);
      new ExternalVisitor(extractor,
              isClean: externalModel.isCleanExternal(node),
              isCovariant: false,
              isContravariant: true)
          .visitSubterms(bank.concreteType);
    }
    if (externalModel.isEntryPoint(node)) {
      builder.setFileOffset(node.fileOffset);
      new ExternalVisitor(extractor,
              isClean: false, isCovariant: true, isContravariant: true)
          .visitSubterms(bank.concreteType);
    }
  }

  visitProcedure(Procedure node) {
    FunctionMemberBank bank = this.bank;
    var ret = thisSubstitution.substituteType(bank.concreteReturnType);
    returnType = _getInternalReturnType(node.function.asyncMarker, ret);
    yieldType = _getYieldType(node.function.asyncMarker, ret);
    recordParameterTypes(bank, node.function);
    bool treatAsExternal = node.isExternal || externalModel.forceExternal(node);
    if (treatAsExternal) {
      returnType = common.topType;
      yieldType = common.topType;
    }
    handleFunctionBody(node.function);
    if (treatAsExternal || seenTypeError) {
      builder.setFileOffset(node.fileOffset);
      new ExternalVisitor(extractor,
              isClean: externalModel.isCleanExternal(node),
              isCovariant: false,
              isContravariant: true)
          .visitSubterms(bank.concreteType);
    }
    if (externalModel.isEntryPoint(node)) {
      builder.setFileOffset(node.fileOffset);
      new ExternalVisitor(extractor,
              isClean: false, isCovariant: true, isContravariant: false)
          .visitSubterms(bank.concreteType);
    }
  }

  void recordClassTypeParameterBounds() {
    var class_ = currentClass;
    if (class_ == null) return;
    var typeParameters = class_.typeParameters;
    for (int i = 0; i < typeParameters.length; ++i) {
      scope.typeParameterBounds[typeParameters[i]] =
          classBank.typeParameterBounds[i];
    }
  }

  int getStorageOffsetFromType(AType type) {
    return (type.source as StorageLocation).index;
  }

  void recordParameterTypes(FunctionMemberBank bank, FunctionNode function) {
    for (int i = 0; i < function.typeParameters.length; ++i) {
      scope.typeParameterBounds[function.typeParameters[i]] =
          bank.typeParameterBounds[i];
    }
    for (int i = 0; i < function.positionalParameters.length; ++i) {
      var variable = function.positionalParameters[i];
      var type = bank.concretePositionalParameters[i];
      scope.variables[variable] = type;
      variable.dataflowValueOffset = getStorageOffsetFromType(type);
    }
    for (var variable in function.namedParameters) {
      var type = bank.concreteType.getNamedParameterType(variable.name);
      scope.variables[variable] = type;
      variable.dataflowValueOffset = getStorageOffsetFromType(type);
    }
    function.returnDataflowValueOffset =
        getStorageOffsetFromType(bank.concreteReturnType);
  }

  void handleFunctionBody(FunctionNode node) {
    var oldAsyncMarker = currentAsyncMarker;
    currentAsyncMarker = node.asyncMarker;
    node.positionalParameters
        .skip(node.requiredParameterCount)
        .forEach((p) => handleOptionalParameter(p, node.fileOffset));
    node.namedParameters
        .forEach((p) => handleOptionalParameter(p, node.fileOffset));
    if (node.body != null) {
      int base = controlFlow.current;
      controlFlow.branchFrom(base);
      visitStatement(node.body);
      if (controlFlow.isReachable && returnType != null) {
        builder.setFileOffset(node.fileEndOffset);
        builder.addAssignment(common.nullValue, returnType.sink);
      }
      controlFlow.resumeBranch(base);
    }
    currentAsyncMarker = oldAsyncMarker;
  }

  FunctionAType handleNestedFunctionNode(FunctionNode node,
      [VariableDeclaration selfReference]) {
    for (var parameter in node.typeParameters) {
      scope.typeParameterBounds[parameter] =
          augmentor.augmentBound(parameter.bound);
    }
    for (var parameter in node.positionalParameters) {
      parameter.dataflowValueOffset = bank.nextIndex;
      var type = augmentor.augmentType(parameter.type);
      scope.variables[parameter] = type;
    }
    for (var parameter in node.namedParameters) {
      parameter.dataflowValueOffset = bank.nextIndex;
      var type = augmentor.augmentType(parameter.type);
      scope.variables[parameter] = type;
    }
    AType augmentedReturnType = augmentor.augmentType(node.returnType);
    var functionObject = bank.newLocation();
    var type = new FunctionAType(
        functionObject,
        functionObject,
        node.typeParameters.map(getTypeParameterBound).toList(growable: false),
        node.requiredParameterCount,
        node.positionalParameters.map(getVariableType).toList(growable: false),
        node.namedParameters.map((v) => v.name).toList(growable: false),
        node.namedParameters.map(getVariableType).toList(growable: false),
        augmentedReturnType);
    addAllocationConstraints(
        functionObject, common.functionValue, type, node.fileOffset);
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

  void handleOptionalParameter(VariableDeclaration parameter, int fileOffset) {
    fileOffset = getFileOffset(fileOffset, parameter.fileEqualsOffset);
    if (parameter.initializer != null) {
      checkAssignableExpression(
          parameter.initializer, getVariableType(parameter), fileOffset);
    } else {
      builder.setFileOffset(fileOffset);
      builder.addAssignment(common.nullValue, getVariableType(parameter).sink);
    }
  }

  Substitution getReceiverType(
      TreeNode where, Expression receiver, Member member) {
    AType type = visitExpression(receiver);
    Class superclass = member.enclosingClass;
    if (superclass.supertype == null) {
      return Substitution.empty; // Members on Object are always accessible.
    }
    if (receiver is ThisExpression) {
      // Treat access on 'this' specially.  Note that this is not necessary for
      // soundness but has a large impact on precision.
      //
      // Normally we prefer to adjust the type arguments on of the receiver type
      // before changing the type of a member, but when the receiver is 'this',
      // its type can only be affected by changing the bounds on the class
      // type parameters, which is incredibly bad for precision.
      //
      // By treating 'this' specially, we cover a lot of common cases that would
      // pollute the type parameter bounds.
      //
      // TODO: Wrap type parameter lower bounds in a ValueSink that protects it
      //       from changes whenever possible.
      return augmentedHierarchy.getClassAsInstanceOf(
              currentClass, superclass) ??
          Substitution.bottomForClass(superclass);
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
          augmentedHierarchy.getClassAsInstanceOf(type.classNode, superclass);
      if (superSubstitution != null) {
        var ownSubstitution = Substitution.fromInterfaceType(type);
        return Substitution.sequence(superSubstitution, ownSubstitution);
      }
    }
    if (type is FunctionAType && superclass == coreTypes.functionClass) {
      assert(type.typeParameterBounds.isEmpty);
      return Substitution.empty;
    }
    // Note that we do not allow 'dynamic' here.  Dynamic calls should not
    // have a declared interface target.
    fail(where, '$member is not accessible on a receiver of type $type');
    // Continue type checking.
    return Substitution.bottomForClass(superclass);
  }

  Substitution getSuperReceiverType(Member member) {
    return augmentedHierarchy.getClassAsInstanceOf(
        currentClass, member.enclosingClass);
  }

  void checkTypeParameterBounds(TreeNode where, List<AType> arguments,
      List<AType> bounds, Substitution substitution, int fileOffset) {
    for (int i = 0; i < arguments.length; ++i) {
      var argument = arguments[i];
      var bound = substitution.substituteBound(bounds[i]);
      checkTypeBound(where, argument, bound, fileOffset);
    }
  }

  int getFileOffset(int fileOffset, int defaultFileOffset) {
    return fileOffset == TreeNode.noOffset ? defaultFileOffset : fileOffset;
  }

  AType handleCall(Arguments arguments, Member member, int fileOffset,
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
          augmentor.augmentTypeList(arguments.types).toList(growable: false);
      if (typeArguments.length != typeParameters.length) {
        fail(arguments, 'Wrong number of type arguments');
        return BottomAType.nonNullable;
      }
      instantiation = Substitution.instantiate(typeArguments);
    } else {
      assert(typeParameters.isEmpty);
    }
    var substitution = Substitution.either(receiver, instantiation);
    checkTypeParameterBounds(arguments, typeArguments,
        target.typeParameterBounds, substitution, fileOffset);
    for (int i = 0; i < arguments.positional.length; ++i) {
      var expectedType =
          substitution.substituteType(target.positionalParameters[i]);
      var argument = arguments.positional[i];
      checkAssignableExpression(argument, expectedType,
          getFileOffset(argument.fileOffset, fileOffset));
    }
    for (int i = 0; i < arguments.named.length; ++i) {
      var argument = arguments.named[i];
      var parameterType =
          target.interfaceType.getNamedParameterType(argument.name);
      if (parameterType == null) {
        fail(argument.value, 'Unexpected named parameter: ${argument.name}');
        break;
      }
      var expectedType = substitution.substituteType(parameterType);
      checkAssignableExpression(argument.value, expectedType,
          getFileOffset(argument.value.fileOffset, fileOffset));
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
        return common.escapingType;

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
        return common.escapingType;

      case AsyncMarker.SyncYielding:
        return returnType;

      default:
        throw 'Unexpected async marker: $asyncMarker';
    }
  }

  AType handleDowncast(AType inputType, DartType castType, int fileOffset) {
    // Handle cast to a type parameter type T specially.  For this case, we
    // generate an assignment from the input value to the lower bound of the
    // type parameter (so all instantiations of it must satisfy any value we
    // pass in here).
    //
    // This special case exists for two reasons:
    //
    // - In the general case, all casts to a type parameter type will completely
    //   corrupt that type parameter, thereby losing a ton of context-sensitive
    //   information.
    //
    // - With context-sensitive cloning, the assignment we generate here can
    //   be inlined at the call-site, effectively pushing the whole downcast
    //   back to the call-site, where it can be handled much more precisely.
    //   In particular, this is necessary for precise handling of the downcast
    //   in `List.from`, `LinkedHashSet.from`, etc.
    if (castType is TypeParameterType) {
      var bound = scope.getTypeParameterBound(castType.parameter);
      var outputLocation = bound.sink;
      builder.setFileOffset(fileOffset);
      builder.addAssignment(inputType.source, outputLocation);
      return new TypeParameterAType(
          Value.null_,
          ValueSink.unassignable('return value of an expression'),
          castType.parameter);
    }

    // Make a type filter assignment for the value being cast.
    var outputLocation = bank.newLocation();
    var typeFilter = new TypeFilter(
        castType is InterfaceType ? castType.classNode : null,
        extractor.getValueSetFlagsFromInterfaceType(castType) |
            ValueFlags.nonValueSetFlags);
    builder.setFileOffset(fileOffset);
    builder.addAssignment(inputType.source, outputLocation, typeFilter);

    // If we are casting to a generic type, e.g. List<int>, we must ensure
    // that the values read from the type arguments are sound worst-case
    // approximations, and that if anything is added into them, the cast value
    // escapes.
    var escapeTracker = bank.newLocation(); // Values added to type arguments.
    var worstCaseType =
        new DowncastTypeVisitor(this, escapeTracker).visitType(castType);
    var outputType = worstCaseType.withSourceAndSink(
        source: outputLocation,
        sink: ValueSink.unassignable('result of a downcast'));

    // If anything flows into the type arguments (e.g. something was added
    // to the list), treat the cast value as escaping, since we cannot track
    // the added values further back.
    builder.addEscape(inputType.source, escapeTracker, ValueFlags.allValueSets);

    return outputType;
  }

  @override
  AType visitAsExpression(AsExpression node) {
    AType inputType = visitExpression(node.operand);
    return handleDowncast(inputType, node.type, node.fileOffset);
  }

  final Set<TypeParameter> typeParametersUsedInDowncast =
      new Set<TypeParameter>();

  void handleTypeParameterUsedInDowncast(TypeParameter parameter) {
    if (typeParametersUsedInDowncast.add(parameter)) {
      // print('Corrupting $parameter');
      var bound = scope.getTypeParameterBound(parameter);
      builder.addAssignment(
          extractor.getWorstCaseValueForType(bound), bound.sink);
    }
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
    return common.boolType;
  }

  @override
  AType visitConditionalExpression(ConditionalExpression node) {
    int fileOffset = getFileOffset(node.fileOffset, node.condition.fileOffset);
    checkConditionExpression(node.condition);
    var type = augmentor.augmentType(node.staticType);
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    checkAssignableExpression(node.then, type, fileOffset);
    controlFlow.branchFrom(base);
    checkAssignableExpression(node.otherwise, type, fileOffset);
    controlFlow.mergeInto(base);
    return type;
  }

  void addAllocationTypeArgument(
      StorageLocation createdObject, AType typeArgument) {
    new AllocationVisitor(extractor, createdObject).visit(typeArgument);
  }

  void addAllocationConstraints(
      StorageLocation createdObject, Value value, AType type, int fileOffset) {
    builder.setFileOffset(fileOffset);
    builder.addConstraint(
        new ValueConstraint(createdObject, value, canEscape: true));
    new AllocationVisitor(extractor, createdObject).visitSubterms(type);
  }

  static final Name toStringName = new Name('toString');
  static final Name hashCodeName = new Name('hashCode');
  static final Name runtimeTypeName = new Name('runtimeType');
  static final Name equalsName = new Name('==');

  /// Returns the storage location with the concrete return value of [member]
  /// (or field value if it is a field).  The "concrete return value" is its
  /// return value that does not take into account values returned by overriding
  /// members.
  StorageLocation getConcreteReturn(Member member) {
    return binding.getFunctionBank(member).concreteReturnType.source;
  }

  StorageLocation getConcreteGetter(Member member) {
    return binding.getConcreteGetterType(member).source;
  }

  void addSpecializedInstanceMembersConstraint(
      Class class_, StorageLocation destination) {
    var toString = hierarchy.getDispatchTarget(class_, toStringName);
    var hashCode = hierarchy.getDispatchTarget(class_, hashCodeName);
    var equals = hierarchy.getDispatchTarget(class_, equalsName);
    var runtimeType = hierarchy.getDispatchTarget(class_, runtimeTypeName);
    builder.addConstraint(new InstanceMembersConstraint(
        destination,
        getConcreteReturn(toString),
        getConcreteGetter(hashCode),
        getConcreteReturn(equals),
        getConcreteGetter(runtimeType)));
  }

  @override
  AType visitConstructorInvocation(ConstructorInvocation node) {
    Constructor target = node.target;
    Arguments arguments = node.arguments;
    Class class_ = target.enclosingClass;
    node.arguments.typeDataflowValueOffset = bank.nextIndex;
    var typeArguments = augmentor.augmentTypeList(arguments.types);
    Substitution substitution =
        Substitution.fromPairs(class_.typeParameters, typeArguments);
    checkTypeParameterBounds(
        node,
        typeArguments,
        binding.getClassBank(class_).typeParameterBounds,
        substitution,
        node.fileOffset);
    handleCall(arguments, target, node.fileOffset, receiver: substitution);
    var createdObject = bank.newLocation();
    var value = extractor.getExactClassValue(class_);
    var type = new InterfaceAType(
        createdObject,
        ValueSink.unassignable('result of an expression', node),
        target.enclosingClass,
        typeArguments);
    addAllocationConstraints(createdObject, value, type, node.fileOffset);
    addSpecializedInstanceMembersConstraint(class_, createdObject);
    return type;
  }

  @override
  AType visitDirectMethodInvocation(DirectMethodInvocation node) {
    return handleCall(node.arguments, node.target, node.fileOffset,
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
    return common.doubleType;
  }

  @override
  AType visitFunctionExpression(FunctionExpression node) {
    return handleNestedFunctionNode(node.function);
  }

  @override
  AType visitIntLiteral(IntLiteral node) {
    return common.intType;
  }

  @override
  AType visitInvalidExpression(InvalidExpression node) {
    return BottomAType.nonNullable;
  }

  @override
  AType visitIsExpression(IsExpression node) {
    visitExpression(node.operand);
    return common.boolType;
  }

  @override
  AType visitLet(Let node) {
    var value = visitExpression(node.variable.initializer);
    if (node.variable.type is DynamicType) {
      scope.variables[node.variable] = value;
      node.variable.dataflowValueOffset =
          node.variable.initializer.dataflowValueOffset;
    } else {
      var type = scope.variables[node.variable] =
          augmentor.augmentType(node.variable.type);
      checkAssignable(node, value, type);
    }
    return visitExpression(node.body);
  }

  @override
  AType visitListLiteral(ListLiteral node) {
    node.typeDataflowValueOffset = bank.nextIndex;
    var typeArgument = augmentor.augmentType(node.typeArgument);
    for (var item in node.expressions) {
      checkAssignableExpression(item, typeArgument);
    }
    var createdObject = bank.newLocation();
    var value =
        node.isConst ? common.immutableListValue : common.growableListValue;
    var type = new InterfaceAType(
        createdObject,
        ValueSink.unassignable('result of an expression', node),
        coreTypes.listClass,
        <AType>[typeArgument]);
    addAllocationConstraints(createdObject, value, type, node.fileOffset);
    return type;
  }

  @override
  AType visitLogicalExpression(LogicalExpression node) {
    checkConditionExpression(node.left);
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    checkConditionExpression(node.right);
    controlFlow.resumeBranch(base);
    return common.boolType;
  }

  @override
  AType visitMapLiteral(MapLiteral node) {
    node.typeDataflowValueOffset = bank.nextIndex;
    var keyType = augmentor.augmentType(node.keyType);
    var valueType = augmentor.augmentType(node.valueType);
    for (var entry in node.entries) {
      checkAssignableExpression(entry.key, keyType);
      checkAssignableExpression(entry.value, valueType);
    }
    var createdObject = bank.newLocation();
    var value =
        node.isConst ? common.immutableMapValue : common.linkedHashMapValue;
    var type = new InterfaceAType(
        createdObject,
        ValueSink.unassignable('result of an expression', node),
        coreTypes.mapClass,
        <AType>[keyType, valueType]);
    addAllocationConstraints(createdObject, value, type, node.fileOffset);
    return type;
  }

  void handleEscapingExpression(Expression node) {
    var type = visitExpression(node);
    handleEscapingType(type);
  }

  void handleEscapingType(AType type) {
    builder.addEscape(type.source);
  }

  AType handleDynamicCallToPotentialTarget(
      TreeNode where,
      AType receiver,
      Member target,
      List<AType> typeArguments,
      List<AType> positional,
      List<AType> named,
      List<String> names) {
    if (target is Field) {
      return common.topType;
    } else {
      var function = target.function;
      // Check for arity errors
      if (positional.length < function.requiredParameterCount) {
        return BottomAType.nonNullable;
      }
      if (positional.length > function.positionalParameters.length) {
        return BottomAType.nonNullable;
      }
      for (var name in names) {
        if (!function.namedParameters.any((v) => v.name == name)) {
          return BottomAType.nonNullable;
        }
      }
      var targetType = binding.getFunctionBank(target);
      var substitution = Substitution.erasing(common.topType);
      for (int i = 0; i < positional.length; ++i) {
        var expectedType =
            substitution.substituteType(targetType.positionalParameters[i]);
        checkAssignable(where, positional[i], expectedType);
      }
      for (int i = 0; i < named.length; ++i) {
        var name = names[i];
        var parameterType =
            targetType.interfaceType.getNamedParameterType(name);
        var expectedType = substitution.substituteType(parameterType);
        checkAssignable(where, named[i], expectedType);
      }
      return substitution.substituteType(targetType.returnType);
    }
  }

  AType handleDynamicCall(
      TreeNode where, AType receiver, Name name, Arguments arguments) {
    if (name.isPrivate) {
      var targets = extractor._dynamicIndex.getGetters(name);
      var types = augmentor.augmentTypeList(arguments.types);
      var positional =
          arguments.positional.map(visitExpression).toList(growable: false);
      var named = arguments.named
          .map((arg) => visitExpression(arg.value))
          .toList(growable: false);
      var names =
          arguments.named.map((arg) => arg.name).toList(growable: false);
      var destination = bank.newLocation();
      for (var target in targets) {
        var returnType = handleDynamicCallToPotentialTarget(
            where, receiver, target, types, positional, named, names);
        builder.addAssignment(returnType.source, destination);
      }
      return new InterfaceAType(
          destination,
          ValueSink.unassignable('return value of expression'),
          coreTypes.objectClass, const []);
    } else {
      handleEscapingType(receiver);
      for (var argument in arguments.positional) {
        handleEscapingExpression(argument);
      }
      for (var argument in arguments.named) {
        handleEscapingExpression(argument.value);
      }
      return common.topType;
    }
  }

  AType handleFunctionCall(TreeNode where, FunctionAType function,
      Arguments arguments, int fileOffset) {
    if (function.requiredParameterCount > arguments.positional.length) {
      fail(where, 'Too few positional arguments');
      return BottomAType.nonNullable;
    }
    if (function.positionalParameters.length < arguments.positional.length) {
      fail(where, 'Too many positional arguments');
      return BottomAType.nonNullable;
    }
    if (function.typeParameterBounds.length != arguments.types.length) {
      fail(where, 'Wrong number of type arguments');
      return BottomAType.nonNullable;
    }
    List<AType> typeArguments = augmentor.augmentTypeList(arguments.types);
    var instantiation = Substitution.instantiate(typeArguments);
    for (int i = 0; i < typeArguments.length; ++i) {
      checkTypeBound(
          where,
          typeArguments[i],
          instantiation.substituteBound(function.typeParameterBounds[i]),
          where.fileOffset);
    }
    for (int i = 0; i < arguments.positional.length; ++i) {
      var expectedType =
          instantiation.substituteType(function.positionalParameters[i]);
      var argument = arguments.positional[i];
      checkAssignableExpression(argument, expectedType,
          getFileOffset(argument.fileOffset, fileOffset));
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
      return overloadedArithmeticOperatorNames.contains(name);
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
        return common.intType;
      }
      if (class1 == coreTypes.doubleClass || class2 == coreTypes.doubleClass) {
        return common.doubleType;
      }
    }
    return common.numType;
  }

  StorageLocation getSpecializedCallReturn(
      AType receiver, Value cleanValue, int nullabilityFlag, int fileOffset) {
    var location = bank.newLocation();
    builder.setFileOffset(fileOffset);
    builder.addAssignment(cleanValue, location);
    builder.addGuardedValueAssignment(
        Value.null_, location, receiver.source, nullabilityFlag);
    return location;
  }

  AType handleEqualsCall(MethodInvocation node) {
    var receiver = visitExpression(node.receiver);
    // TODO: Handle value escaping through == operator.
    if (node.interfaceTarget != null) {
      handleCall(node.arguments, node.interfaceTarget, node.fileOffset);
    }
    var returnValue = getSpecializedCallReturn(
        receiver, common.boolValue, ValueFlags.nullableEquals, node.fileOffset);
    return new InterfaceAType(
        returnValue,
        ValueSink.unassignable('return value of an expression', node),
        coreTypes.boolClass, const <AType>[]);
  }

  AType handleToStringCall(MethodInvocation node) {
    var receiver = visitExpression(node.receiver);
    var returnValue = getSpecializedCallReturn(receiver, common.stringValue,
        ValueFlags.nullableToString, node.fileOffset);
    return new InterfaceAType(
        returnValue,
        ValueSink.unassignable('return value of an expression', node),
        coreTypes.stringClass, const <AType>[]);
  }

  AType handleHashCodeGet(PropertyGet node) {
    var receiver = visitExpression(node.receiver);
    var returnValue = getSpecializedCallReturn(receiver, common.intValue,
        ValueFlags.nullableHashCode, node.fileOffset);
    return new InterfaceAType(
        returnValue,
        ValueSink.unassignable('return value of an expression', node),
        coreTypes.intClass, const <AType>[]);
  }

  AType handleRuntimeTypeGet(PropertyGet node) {
    var receiver = visitExpression(node.receiver);
    var returnValue = getSpecializedCallReturn(receiver, common.typeValue,
        ValueFlags.nullableRuntimeType, node.fileOffset);
    return new InterfaceAType(
        returnValue,
        ValueSink.unassignable('return value of an expression', node),
        coreTypes.intClass, const <AType>[]);
  }

  @override
  AType visitMethodInvocation(MethodInvocation node) {
    int fileOffset = getFileOffset(node.fileOffset, node.receiver.fileOffset);
    var target = node.interfaceTarget;
    String name = node.name.name;
    if (name == '==') {
      return handleEqualsCall(node);
    }
    if (name == 'toString' &&
        node.arguments.positional.length == 0 &&
        node.arguments.named.length == 0) {
      return handleToStringCall(node);
    }
    if (target == null) {
      var receiver = visitExpression(node.receiver);
      if (node.name.name == 'call' && receiver is FunctionAType) {
        return handleFunctionCall(node, receiver, node.arguments, fileOffset);
      }
      return handleDynamicCall(node, receiver, node.name, node.arguments);
    } else if (isOverloadedArithmeticOperator(target)) {
      assert(node.arguments.positional.length == 1);
      var receiver = visitExpression(node.receiver);
      var argument = visitExpression(node.arguments.positional[0]);
      return getTypeOfOverloadedArithmetic(receiver, argument);
    } else {
      return handleCall(node.arguments, target, fileOffset,
          receiver: getReceiverType(node, node.receiver, node.interfaceTarget));
    }
  }

  @override
  AType visitPropertyGet(PropertyGet node) {
    String name = node.name.name;
    if (name == 'hashCode') {
      return handleHashCodeGet(node);
    }
    if (name == 'runtimeType') {
      return handleRuntimeTypeGet(node);
    }
    if (node.interfaceTarget == null) {
      handleEscapingExpression(node.receiver);
      return common.topType;
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
      checkAssignable(node.value, value, receiver.substituteType(setterType),
          getFileOffset(node.value.fileOffset, node.fileOffset));
    } else {
      handleEscapingExpression(node.receiver);
      handleEscapingType(value);
    }
    return value;
  }

  @override
  AType visitNot(Not node) {
    checkConditionExpression(node.operand);
    return common.boolType;
  }

  @override
  AType visitNullLiteral(NullLiteral node) {
    return BottomAType.nullable;
  }

  @override
  AType visitRethrow(Rethrow node) {
    controlFlow.terminateBranch();
    return BottomAType.nonNullable;
  }

  @override
  AType visitStaticGet(StaticGet node) {
    return binding.getGetterType(node.target);
  }

  /// Special-cases calls to `List([int length])`
  ///
  /// This is to detect growability and fill fixed-length lists with nulls.
  AType handleDefaultListFactoryCall(StaticInvocation node) {
    var type = handleCall(node.arguments, node.target, node.fileOffset);
    if (node.arguments.positional.length == 0) {
      return type.withSourceAndSink(source: common.growableListValue);
    }
    InterfaceAType listType = type;
    AType contentType = listType.typeArguments[0];
    builder.addAssignment(Value.null_, contentType.sink);
    return type.withSourceAndSink(source: common.fixedLengthListValue);
  }

  Value getListValueFromGrowableFlag(Arguments arguments) {
    for (var namedArg in arguments.named) {
      if (namedArg.name == 'growable') {
        if (isTrueConstant(namedArg.value)) return common.growableListValue;
        if (isFalseConstant(namedArg.value)) return common.fixedLengthListValue;
        return common.mutableListValue;
      }
    }
    return common.growableListValue;
  }

  InterfaceAType tryUpcast(AType type, Class class_) {
    if (type is! InterfaceAType) return null;
    return augmentedHierarchy.getTypeAsInstanceOf(type, class_);
  }

  AType getDowncastedIterableContentType(
      AType iterable, DartType castType, int fileOffset) {
    if (iterable is! InterfaceAType) return null;
    InterfaceAType asIterable = augmentedHierarchy.getTypeAsInstanceOf(
        iterable, coreTypes.iterableClass);
    if (asIterable == null) return null;
    var contentType = asIterable.typeArguments[0];
    return handleDowncast(contentType, castType, fileOffset)
        .withSourceAndSink(sink: ValueSink.nowhere);
  }

  /// Special-cases calls to `List.from(Iterable<Object> elements)`.
  ///
  /// There is a downcast from the content type of `elements` to the content
  /// type of the list; this must be handled at the call-site in order to have
  /// reasonable precision.
  AType handleListFromIterableCall(StaticInvocation node) {
    AType iterable = visitExpression(node.arguments.positional[0]);
    AType content = getDowncastedIterableContentType(
        iterable, node.arguments.types[0], node.fileOffset);
    if (content == null) {
      return handleCall(node.arguments, node.target, node.fileOffset);
    }
    for (var namedArg in node.arguments.named) {
      visitExpression(namedArg.value);
    }
    return new InterfaceAType(
        getListValueFromGrowableFlag(node.arguments),
        ValueSink.unassignable('return value of an expression', node),
        coreTypes.listClass,
        <AType>[content]);
  }

  /// Special-cases calls to `LinkedHashSet.from(Iterable<Object> elements)`.
  ///
  /// There is a downcast from the content type of `elements` to the content
  /// type of the list; this must be handled at the call-site in order to have
  /// reasonable precision.
  AType handleLinkedHashSetFromIterableCall(StaticInvocation node) {
    AType iterable = visitExpression(node.arguments.positional[0]);
    AType content = getDowncastedIterableContentType(
        iterable, node.arguments.types[0], node.fileOffset);
    if (content == null) {
      return handleCall(node.arguments, node.target, node.fileOffset);
    }
    var class_ = coreTypes.getClass('dart:collection', 'LinkedHashSet');
    var value = new Value(class_, ValueFlags.other);
    return new InterfaceAType(
        value,
        ValueSink.unassignable('return value of an expression', node),
        class_,
        <AType>[content]);
  }

  @override
  AType visitStaticInvocation(StaticInvocation node) {
    Reference target = node.targetReference;
    if (target == defaultListFactoryReference) {
      return handleDefaultListFactoryCall(node);
    } else if (target == listFromIterableReference) {
      return handleListFromIterableCall(node);
    } else if (target == linkedHashSetFromIterableReference) {
      return handleLinkedHashSetFromIterableCall(node);
    }
    return handleCall(node.arguments, node.target, node.fileOffset);
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
    return common.stringType;
  }

  @override
  AType visitStringLiteral(StringLiteral node) {
    return common.stringType;
  }

  @override
  AType visitSuperMethodInvocation(SuperMethodInvocation node) {
    if (node.interfaceTarget == null) {
      return handleDynamicCall(node, thisType, node.name, node.arguments);
    } else {
      return handleCall(node.arguments, node.interfaceTarget, node.fileOffset,
          receiver: getSuperReceiverType(node.interfaceTarget));
    }
  }

  @override
  AType visitSuperPropertyGet(SuperPropertyGet node) {
    if (node.interfaceTarget == null) {
      return common.topType;
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
    return common.symbolType;
  }

  @override
  AType visitThisExpression(ThisExpression node) {
    return thisType;
  }

  @override
  AType visitThrow(Throw node) {
    // TODO escape value
    visitExpression(node.expression);
    controlFlow.terminateBranch();
    return BottomAType.nonNullable;
  }

  @override
  AType visitTypeLiteral(TypeLiteral node) {
    return common.typeType;
  }

  @override
  AType visitVariableGet(VariableGet node) {
    var variable = node.variable;
    var type = getVariableType(variable);
    if (!controlFlow.isDefinitelyInitialized(variable)) {
      builder.setFileOffset(node.variable.fileOffset);
      builder.addAssignment(Value.null_, type.sink);
    }
    return type;
  }

  @override
  AType visitVariableSet(VariableSet node) {
    var value = visitExpression(node.value);
    var variable = node.variable;
    checkAssignable(
        node.value, value, getVariableType(variable), node.fileOffset);
    controlFlow.setInitialized(variable);
    return value;
  }

  @override
  visitAssertStatement(AssertStatement node) {
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitExpression(node.condition);
    if (node.message != null) {
      visitExpression(node.message);
    }
    controlFlow.resumeBranch(base);
  }

  @override
  visitBlock(Block node) {
    for (var statement in node.statements) {
      visitStatement(statement);
      if (!controlFlow.isReachable) return;
    }
  }

  @override
  visitBreakStatement(BreakStatement node) {
    controlFlow.breakToLabel(node.target);
  }

  @override
  visitContinueSwitchStatement(ContinueSwitchStatement node) {
    controlFlow.terminateBranch();
  }

  bool isTrueConstant(Expression node) {
    return node is BoolLiteral && node.value == true;
  }

  bool isFalseConstant(Expression node) {
    return node is BoolLiteral && node.value == true;
  }

  @override
  visitDoStatement(DoStatement node) {
    visitStatement(node.body);
    checkConditionExpression(node.condition);
    if (isTrueConstant(node.condition)) {
      controlFlow.terminateBranch();
    }
  }

  @override
  visitEmptyStatement(EmptyStatement node) {}

  @override
  visitExpressionStatement(ExpressionStatement node) {
    visitExpression(node.expression);
    return node.expression is! Throw && node.expression is! Rethrow;
  }

  @override
  visitForInStatement(ForInStatement node) {
    node.variable.dataflowValueOffset = bank.nextIndex;
    scope.variables[node.variable] = augmentor.augmentType(node.variable.type);
    var iterable = visitExpression(node.iterable);
    // TODO(asgerf): Store interface targets on for-in loops or desugar them,
    // instead of doing the ad-hoc resolution here.
    if (node.isAsync) {
      checkAssignable(node, getStreamElementType(iterable),
          getVariableType(node.variable), node.fileOffset);
    } else {
      checkAssignable(node, getIterableElementType(iterable),
          getVariableType(node.variable), node.fileOffset);
    }
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitStatement(node.body);
    controlFlow.resumeBranch(base);
  }

  static final Name iteratorName = new Name('iterator');
  static final Name iteratorCurrentName = new Name('current');

  AType lookupMember(AType type, Name name) {
    if (type is InterfaceAType) {
      var member = hierarchy.getInterfaceMember(type.classNode, name);
      if (member == null) return null;
      var upcastType =
          augmentedHierarchy.getTypeAsInstanceOf(type, member.enclosingClass);
      return Substitution
          .fromInterfaceType(upcastType)
          .substituteType(binding.getGetterType(member));
    } else {
      return null;
    }
  }

  AType getIterableElementType(AType iterable) {
    // TODO: Avoid getting the nullable return type of Iterator.current.
    var iteratorType = lookupMember(iterable, iteratorName);
    if (iteratorType == null) return common.topType;
    var elementType = lookupMember(iteratorType, iteratorCurrentName);
    if (elementType == null) return common.topType;
    return elementType;
  }

  AType getStreamElementType(AType stream) {
    if (stream is InterfaceAType) {
      var asStream = augmentedHierarchy.getClassAsInstanceOf(
          stream.classNode, coreTypes.streamClass);
      if (asStream == null) return common.topType;
      var parameter = coreTypes.streamClass.typeParameters[0];
      var substitution = Substitution.sequence(
          asStream, Substitution.fromInterfaceType(stream));
      var result = substitution.getRawSubstitute(parameter);
      assert(result != null);
      return result;
    }
    return common.topType;
  }

  @override
  visitForStatement(ForStatement node) {
    node.variables.forEach(visitVariableDeclaration);
    if (node.condition != null) {
      checkConditionExpression(node.condition);
    }
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitStatement(node.body);
    node.updates.forEach(visitExpression);
    controlFlow.resumeBranch(base);
    if (isTrueConstant(node.condition)) {
      controlFlow.terminateBranch();
    }
  }

  @override
  visitFunctionDeclaration(FunctionDeclaration node) {
    handleNestedFunctionNode(node.function, node.variable);
  }

  @override
  visitIfStatement(IfStatement node) {
    checkConditionExpression(node.condition);
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitStatement(node.then);
    controlFlow.branchFrom(base);
    if (node.otherwise != null) {
      visitStatement(node.otherwise);
    }
    controlFlow.mergeInto(base);
  }

  @override
  visitInvalidStatement(InvalidStatement node) {
    controlFlow.terminateBranch();
  }

  @override
  visitLabeledStatement(LabeledStatement node) {
    int base = controlFlow.current;
    controlFlow.enterLabel(node);
    visitStatement(node.body);
    controlFlow.exitLabel(node, base);
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
        checkAssignable(node.expression, type, returnType, node.fileOffset);
      }
    }
    controlFlow.terminateBranch();
  }

  @override
  visitSwitchStatement(SwitchStatement node) {
    visitExpression(node.expression);
    bool hasDefault = false;
    int base = controlFlow.current;
    for (var switchCase in node.cases) {
      switchCase.expressions.forEach(visitExpression);
      controlFlow.branchFrom(base);
      visitStatement(switchCase.body);
      if (switchCase.isDefault) {
        hasDefault = true;
      }
    }
    controlFlow.resumeBranch(base);
    if (hasDefault) {
      // Control must break out from an enclosing labeled statement.
      controlFlow.terminateBranch();
    }
  }

  @override
  visitTryCatch(TryCatch node) {
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitStatement(node.body);
    for (var catchClause in node.catches) {
      // TODO: Set precise types on catch parameters
      scope.variables[catchClause.exception] = common.topType;
      if (catchClause.stackTrace != null) {
        scope.variables[catchClause.stackTrace] = common.topType;
      }
      controlFlow.branchFrom(base);
      visitStatement(catchClause.body);
    }
    controlFlow.mergeInto(base);
  }

  @override
  visitTryFinally(TryFinally node) {
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitStatement(node.body);
    controlFlow.branchFrom(base);
    visitStatement(node.finalizer);
    controlFlow.mergeFinally(base);
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    assert(!scope.variables.containsKey(node));
    node.dataflowValueOffset = bank.nextIndex;
    var type = scope.variables[node] = augmentor.augmentType(node.type);
    if (node.initializer != null) {
      checkAssignableExpression(node.initializer, type, node.fileEqualsOffset);
    } else {
      controlFlow.declareUninitializedVariable(node);
    }
  }

  @override
  visitWhileStatement(WhileStatement node) {
    checkConditionExpression(node.condition);
    int base = controlFlow.current;
    controlFlow.branchFrom(base);
    visitStatement(node.body);
    controlFlow.resumeBranch(base);
    if (isTrueConstant(node.condition)) {
      controlFlow.terminateBranch();
    }
  }

  @override
  visitYieldStatement(YieldStatement node) {
    if (node.isYieldStar) {
      Class container = currentAsyncMarker == AsyncMarker.AsyncStar
          ? coreTypes.streamClass
          : coreTypes.iterableClass;
      var type = visitExpression(node.expression);
      var asContainer = type is InterfaceAType
          ? augmentedHierarchy.getTypeAsInstanceOf(type, container)
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
    checkAssignableExpression(node.value, type, node.fileOffset);
  }

  @override
  visitRedirectingInitializer(RedirectingInitializer node) {
    handleCall(node.arguments, node.target, node.fileOffset);
  }

  @override
  visitSuperInitializer(SuperInitializer node) {
    handleCall(node.arguments, node.target, node.fileOffset,
        receiver: augmentedHierarchy.getClassAsInstanceOf(
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
    return common.topType;
  }

  @override
  AType visitLoadLibrary(LoadLibrary node) {
    return new InterfaceAType(
        new Value(coreTypes.futureClass, ValueFlags.other),
        ValueSink.unassignable('return value of expression', node),
        coreTypes.futureClass,
        [common.topType]);
  }

  @override
  AType visitVectorCopy(VectorCopy node) {
    throw 'Code with vectors not supported';
  }

  @override
  AType visitVectorCreation(VectorCreation node) {
    throw 'Code with vectors not supported';
  }

  @override
  AType visitVectorGet(VectorGet node) {
    throw 'Code with vectors not supported';
  }

  @override
  AType visitVectorSet(VectorSet node) {
    throw 'Code with vectors not supported';
  }

  @override
  AType visitClosureCreation(ClosureCreation node) {
    throw 'Code with closures converted not supported';
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
  final bool isClean;

  CoreTypes get coreTypes => extractor.coreTypes;
  SourceSinkTranslator get builder => extractor._builder;

  ExternalVisitor(this.extractor,
      {this.isClean, this.isCovariant, this.isContravariant}) {
    assert(isClean != null);
    assert(isCovariant != null);
    assert(isContravariant != null);
  }

  ExternalVisitor.bivariant(this.extractor)
      : isClean = false,
        isCovariant = true,
        isContravariant = true;

  ExternalVisitor.covariant(this.extractor)
      : isClean = false,
        isCovariant = true,
        isContravariant = false;

  ExternalVisitor.contravariant(this.extractor)
      : isClean = false,
        isCovariant = false,
        isContravariant = true;

  ExternalVisitor get inverseVisitor {
    return new ExternalVisitor(extractor,
        isClean: isClean,
        isCovariant: isContravariant,
        isContravariant: isCovariant);
  }

  ExternalVisitor get bivariantVisitor {
    return new ExternalVisitor(extractor,
        isClean: isClean, isCovariant: true, isContravariant: true);
  }

  void visit(AType type) {
    if (isCovariant) {
      // Simple case intuition:
      // For a function object of type `(A) => B`, the return type B will
      // get processed here.  If the function escapes, the values it returns
      // can escape too, so process B as escaping.
      if (!isClean) {
        builder.addSinkToSinkAssignment(type.sink, ValueSink.escape);
      }
    }
    if (isContravariant) {
      // Simple case intuition:
      // For a function object of type `(A) => B`, the argument type A will get
      // processed here.  If the function escapes, unknown arguments can be
      // passed to it, so mark A as having worst-case values.
      builder.addSourceToSourceAssignment(
          extractor.getWorstCaseValueForType(type, isClean: isClean),
          type.source);
    }
    type.accept(this);
  }

  void visitSubterms(AType type) {
    type.accept(this);
  }

  void visitBound(AType type) => bivariantVisitor.visit(type);
  void visitInverse(AType type) => inverseVisitor.visit(type);

  @override
  visitBottomAType(BottomAType type) {}

  @override
  visitFunctionAType(FunctionAType type) {
    type.typeParameterBounds.forEach(visitBound);
    type.positionalParameters.forEach(visitInverse);
    type.namedParameters.forEach(visitInverse);
    visit(type.returnType);
  }

  @override
  visitFunctionTypeParameterAType(FunctionTypeParameterAType type) {}

  @override
  visitInterfaceAType(InterfaceAType type) {
    type.typeArguments.forEach(visitBound);
  }

  @override
  visitTypeParameterAType(TypeParameterAType type) {}
}

class AllocationVisitor extends ATypeVisitor {
  final ConstraintExtractor extractor;
  final StorageLocation object;
  final bool isCovariant;
  final bool isContravariant;

  SourceSinkTranslator get builder => extractor._builder;

  AllocationVisitor(this.extractor, this.object,
      {this.isCovariant: true, this.isContravariant: false});

  AllocationVisitor get inverse => new AllocationVisitor(extractor, object,
      isCovariant: isContravariant, isContravariant: isCovariant);

  AllocationVisitor get bivariant => new AllocationVisitor(extractor, object,
      isCovariant: true, isContravariant: true);

  void visitSubterms(AType type) {
    type.accept(this);
  }

  void visit(AType type) {
    if (isCovariant) {
      // Simple case intuition:
      // For a function object of type `(A) => B`, the return type B will
      // get processed here.  If the function escapes, the values it returns
      // can escape too, so process B as escaping.
      builder.addEscape(type.source, object, ValueFlags.escaping);
    }
    if (isContravariant) {
      // Simple case intuition:
      // For a function object of type `(A) => B`, the argument type A will get
      // processed here.  If the function escapes, unknown arguments can be
      // passed to it, so mark A as having worst-case values.
      var sink = type.sink;
      if (sink is StorageLocation) {
        extractor._builder.addConstraint(new GuardedValueConstraint(
            sink,
            extractor.getWorstCaseValueForType(type),
            object,
            ValueFlags.escaping));
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
      bivariant.visit(argument);
    }
  }

  @override
  visitTypeParameterAType(TypeParameterAType type) {}
}

/// Builds a copy of a type with the sources and sinks replaced.
///
/// The subclass must override [convertSource] and [convertSink] to determine
/// how sources and sinks are converted.
abstract class SourceSinkConverter extends ATypeVisitor<AType> {
  ValueSource convertSource(ValueSource source, AType type);

  ValueSink convertSink(ValueSink sink, AType type);

  AType convertType(AType type) => type.accept(this);

  ASupertype convertSupertype(ASupertype type) {
    return new ASupertype(type.classNode, convertTypeList(type.typeArguments));
  }

  List<AType> convertTypeList(List<AType> types) =>
      types.map(convertType).toList(growable: false);

  @override
  AType visitBottomAType(BottomAType type) {
    return new BottomAType(
        convertSource(type.source, type), convertSink(type.sink, type));
  }

  @override
  AType visitFunctionAType(FunctionAType type) {
    return new FunctionAType(
        convertSource(type.source, type),
        convertSink(type.sink, type),
        convertTypeList(type.typeParameterBounds),
        type.requiredParameterCount,
        convertTypeList(type.positionalParameters),
        type.namedParameterNames,
        convertTypeList(type.namedParameters),
        convertType(type.returnType));
  }

  @override
  AType visitFunctionTypeParameterAType(FunctionTypeParameterAType type) {
    return type;
  }

  @override
  AType visitInterfaceAType(InterfaceAType type) {
    return new InterfaceAType(
        convertSource(type.source, type),
        convertSink(type.sink, type),
        type.classNode,
        convertTypeList(type.typeArguments));
  }

  @override
  AType visitTypeParameterAType(TypeParameterAType type) {
    return new TypeParameterAType(convertSource(type.source, type),
        convertSink(type.sink, type), type.parameter);
  }
}

/// Replaces all sinks in a type with a given sink.
class ProtectSinks extends SourceSinkConverter {
  @override
  ValueSink convertSink(ValueSink sink, AType type) {
    return ValueSink.nowhere;
  }

  @override
  ValueSource convertSource(ValueSource source, AType type) {
    return source;
  }
}

class ProtectCleanSupertype extends SourceSinkConverter {
  final CoreTypes coreTypes;
  final CommonValues common;

  ProtectCleanSupertype(this.coreTypes, this.common);

  @override
  ValueSink convertSink(ValueSink sink, AType type) {
    return sink;
  }

  @override
  ValueSource convertSource(ValueSource source, AType type) {
    if (type is InterfaceAType) {
      var class_ = type.classNode;
      if (class_ == coreTypes.intClass) return common.intValue;
      if (class_ == coreTypes.doubleClass) return common.doubleValue;
      if (class_ == coreTypes.numClass) return common.numValue;
      if (class_ == coreTypes.stringClass) return common.stringValue;
      if (class_ == coreTypes.boolClass) return common.boolValue;
    }
    return source;
  }
}

class DowncastTypeVisitor extends DartTypeVisitor<AType> {
  final ConstraintExtractorVisitor visitor;
  final StorageLocation sink;
  final List<List<TypeParameter>> _localTypeParameters =
      <List<TypeParameter>>[];

  DowncastTypeVisitor(this.visitor, this.sink);

  ConstraintExtractor get extractor => visitor.extractor;
  CommonValues get common => extractor.common;
  CoreTypes get coreTypes => extractor.coreTypes;

  AType visitType(DartType type) => type.accept(this);

  List<AType> visitTypeList(Iterable<DartType> types) {
    return types.map(visitType).toList(growable: false);
  }

  @override
  AType defaultDartType(DartType node) {
    throw 'Unexpected type in cast: $node';
  }

  @override
  AType visitBottomType(BottomType node) {
    return new BottomAType(Value.null_, sink);
  }

  @override
  AType visitDynamicType(DynamicType node) {
    return new InterfaceAType(
        common.anyValue, sink, coreTypes.objectClass, const <AType>[]);
  }

  @override
  AType visitFunctionType(FunctionType node) {
    _localTypeParameters.add(node.typeParameters);
    var type = new FunctionAType(
        common.nullableEscapingFunctionValue,
        sink,
        visitTypeList(node.typeParameters.map((t) => t.bound)),
        node.requiredParameterCount,
        visitTypeList(node.positionalParameters),
        node.namedParameters.map((t) => t.name).toList(growable: false),
        visitTypeList(node.namedParameters.map((t) => t.type)),
        visitType(node.returnType));
    _localTypeParameters.removeLast();
    return type;
  }

  @override
  AType visitInterfaceType(InterfaceType node) {
    return new InterfaceAType(extractor.getWorstCaseValue(node.classNode), sink,
        node.classNode, visitTypeList(node.typeArguments));
  }

  @override
  AType visitTypeParameterType(TypeParameterType node) {
    visitor.handleTypeParameterUsedInDowncast(node.parameter);
    // Translate function-type type parameters to De Brujin indices.
    int shift = 0;
    for (var list in _localTypeParameters.reversed) {
      int index = list.indexOf(node.parameter);
      if (index != -1) {
        return new FunctionTypeParameterAType(Value.null_, sink, shift + index);
      }
      shift += list.length;
    }
    return new TypeParameterAType(Value.null_, sink, node.parameter);
  }

  @override
  AType visitVoidType(VoidType node) {
    return new InterfaceAType(
        common.anyValue, sink, coreTypes.objectClass, const <AType>[]);
  }
}
