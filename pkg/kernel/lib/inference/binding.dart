// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.strong_inference.binding;

import '../ast.dart';
import '../core_types.dart';
import 'augmented_type.dart';
import 'package:kernel/inference/key.dart';

/// Constructs augmented types and type modifier variables.
class Binding {
  final CoreTypes coreTypes;
  final Map<Class, ClassBank> classBanks = <Class, ClassBank>{};
  final Map<Member, ModifierBank> memberBanks = <Member, ModifierBank>{};

  Binding(this.coreTypes);

  ModifierBank _initializeMemberBank(Member member) {
    if (member is Field) {
      var modifiers = new FieldBank(member, coreTypes);
      modifiers.type = modifiers.augmentType(member.type);
      return modifiers;
    } else {
      var modifiers = new FunctionMemberBank(member, coreTypes);
      var function = member.function;
      modifiers.type = modifiers.augmentType(function.functionType);
      return modifiers;
    }
  }

  ModifierBank _initializeClassBank(Class class_) {
    var modifiers = new ClassBank(class_, coreTypes);
    modifiers.typeParameters = class_.typeParameters
        .map((p) => modifiers.augmentType(p.bound))
        .toList(growable: false);
    modifiers.supertypes = class_.supers
        .map((s) => modifiers.augmentSuper(s))
        .toList(growable: false);
    return modifiers;
  }

  ClassBank getClassBank(Class class_) {
    return classBanks[class_] ??= _initializeClassBank(class_);
  }

  ModifierBank getMemberBank(Member member) {
    return memberBanks[member] ??= _initializeMemberBank(member);
  }

  FieldBank getFieldBank(Field field) {
    return getMemberBank(field);
  }

  FunctionMemberBank getFunctionBank(Member member) {
    return getMemberBank(member);
  }

  List<ASupertype> getSupertypes(Class class_) {
    return getClassBank(class_).supertypes;
  }

  AType getFieldType(Field node) {
    return getFieldBank(node).type;
  }

  AType getGetterType(Member member) {
    if (member is Field) return getFieldType(member);
    if (member is Procedure) {
      var modifiers = getFunctionBank(member);
      return member.isGetter ? modifiers.type.returnType : modifiers.type;
    }
    throw '$member cannot be used as a getter';
  }

  AType getSetterType(Member member) {
    if (member is Field) return getFieldType(member);
    if (member is Procedure && member.isSetter) {
      var modifiers = getFunctionBank(member);
      return modifiers.type.positionalParameters[0];
    }
    throw '$member cannot be used as a setter';
  }
}

abstract class ModifierBank {
  final CoreTypes coreTypes;
  final List<Key> modifiers = <Key>[];

  ModifierBank(this.coreTypes);

  TreeNode get classOrMember;

  Key newModifier() {
    var modifier = new Key(classOrMember, modifiers.length);
    modifiers.add(modifier);
    return modifier;
  }

  AType augmentType(DartType type) {
    return new TypeAugmentor(coreTypes, this).makeType(type);
  }

  List<AType> augmentTypeList(Iterable<DartType> types) {
    return types.map(augmentType).toList(growable: false);
  }

  ASupertype augmentSuper(Supertype type) {
    return new TypeAugmentor(coreTypes, this).makeSuper(type);
  }

  List<ASupertype> augmentSuperList(Iterable<Supertype> types) {
    return types.map(augmentSuper).toList(growable: false);
  }
}

class FieldBank extends ModifierBank {
  final Field field;
  AType type;

  FieldBank(this.field, CoreTypes coreTypes) : super(coreTypes);

  Member get classOrMember => field;
}

class FunctionMemberBank extends ModifierBank {
  final Member member;
  FunctionAType type;

  FunctionMemberBank(this.member, CoreTypes coreTypes) : super(coreTypes);

  AType get returnType => type.returnType;
  List<AType> get typeParameters => type.typeParameters;
  List<AType> get positionalParameters => type.positionalParameters;
  List<AType> get namedParameters => type.namedParameters;

  Member get classOrMember => member;
}

class ClassBank extends ModifierBank {
  final Class classNode;
  List<AType> typeParameters;
  List<ASupertype> supertypes;

  ClassBank(this.classNode, CoreTypes coreTypes) : super(coreTypes);

  Class get classOrMember => classNode;
}

class TypeAugmentor extends DartTypeVisitor<AType> {
  final CoreTypes coreTypes;
  final ModifierBank modifiers;
  final List<List<TypeParameter>> innerTypeParameters = <List<TypeParameter>>[];

  TypeAugmentor(this.coreTypes, this.modifiers);

  AType makeType(DartType type) {
    return type.accept(this);
  }

  ASupertype makeSuper(Supertype type) {
    return new ASupertype(type.classNode,
        type.typeArguments.map(makeType).toList(growable: false));
  }

  visitInvalidType(InvalidType node) {
    return new InterfaceAType(modifiers.newModifier(), modifiers.newModifier(),
        coreTypes.objectClass, const <AType>[]);
  }

  visitDynamicType(DynamicType node) {
    return new InterfaceAType(modifiers.newModifier(), modifiers.newModifier(),
        coreTypes.objectClass, const <AType>[]);
  }

  visitVoidType(VoidType node) {
    var key = modifiers.newModifier();
    return new BottomAType(key, key);
  }

  visitBottomType(BottomType node) {
    var key = modifiers.newModifier();
    return new BottomAType(key, key);
  }

  visitInterfaceType(InterfaceType node) {
    return new InterfaceAType(
        modifiers.newModifier(),
        modifiers.newModifier(),
        node.classNode,
        node.typeArguments.map(makeType).toList(growable: false));
  }

  visitFunctionType(FunctionType node) {
    innerTypeParameters.add(node.typeParameters);
    var type = new FunctionAType(
        modifiers.newModifier(),
        modifiers.newModifier(),
        node.typeParameters
            .map((p) => makeType(p.bound))
            .toList(growable: false),
        node.requiredParameterCount,
        node.positionalParameters.map(makeType).toList(growable: false),
        node.namedParameters.map((t) => t.name).toList(growable: false),
        node.namedParameters
            .map((t) => makeType(t.type))
            .toList(growable: false),
        makeType(node.returnType));
    innerTypeParameters.removeLast();
    return type;
  }

  visitTypeParameterType(TypeParameterType node) {
    for (int i = innerTypeParameters.length - 1; i >= 0; --i) {
      var list = innerTypeParameters[i];
      int index = list.indexOf(node.parameter);
      if (index != -1) {
        var key = modifiers.newModifier();
        return new FunctionTypeParameterAType(key, key, index);
      }
    }
    return new PlaceholderAType(node.parameter);
  }
}
