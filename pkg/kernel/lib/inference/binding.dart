// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.strong_inference.binding;

import '../ast.dart';
import '../core_types.dart';
import 'atype.dart';
import 'key.dart';
import 'value.dart';

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
        .map((p) => modifiers.augmentBound(p.bound))
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
  final List<Key> keys = <Key>[];

  ModifierBank(this.coreTypes);

  TreeNode get classOrMember;

  Key newKey() {
    var key = new Key(classOrMember, keys.length);
    keys.add(key);
    return key;
  }

  AType augmentType(DartType type) {
    return new TypeAugmentor(coreTypes, this).makeType(type);
  }

  List<AType> augmentTypeList(Iterable<DartType> types) {
    return types.map(augmentType).toList(growable: false);
  }

  Bound augmentBound(DartType type) {
    return new TypeAugmentor(coreTypes, this).makeBound(type);
  }

  List<Bound> augmentBoundList(Iterable<DartType> types) {
    return types.map(augmentBound).toList(growable: false);
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

  Member get classOrMember => member;
}

class ClassBank extends ModifierBank {
  final Class classNode;
  List<Bound> typeParameters;
  List<ASupertype> supertypes;

  ClassBank(this.classNode, CoreTypes coreTypes) : super(coreTypes);

  Class get classOrMember => classNode;
}

class TypeAugmentor extends DartTypeVisitor<AType> {
  final CoreTypes coreTypes;
  final ModifierBank modifiers;
  final List<List<TypeParameter>> innerTypeParameters = <List<TypeParameter>>[];

  TypeAugmentor(this.coreTypes, this.modifiers);

  Bound makeBound(DartType type) {
    return new Bound(type.accept(this), modifiers.newKey());
  }

  AType makeType(DartType type) {
    return type.accept(this);
  }

  ASupertype makeSuper(Supertype type) {
    return new ASupertype(type.classNode,
        type.typeArguments.map(makeType).toList(growable: false));
  }

  visitInvalidType(InvalidType node) {
    return new InterfaceAType(
        modifiers.newKey(), coreTypes.objectClass, const <Bound>[]);
  }

  visitDynamicType(DynamicType node) {
    return new InterfaceAType(
        modifiers.newKey(), coreTypes.objectClass, const <Bound>[]);
  }

  visitVoidType(VoidType node) {
    return new ConstantAType(Value.nullValue);
  }

  visitBottomType(BottomType node) {
    return new ConstantAType(Value.nullValue);
  }

  visitInterfaceType(InterfaceType node) {
    return new InterfaceAType(modifiers.newKey(), node.classNode,
        node.typeArguments.map(makeBound).toList(growable: false));
  }

  visitFunctionType(FunctionType node) {
    innerTypeParameters.add(node.typeParameters);
    var type = new FunctionAType(
        modifiers.newKey(),
        node.typeParameters
            .map((p) => makeBound(p.bound))
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
    int offset = 0;
    for (int i = innerTypeParameters.length - 1; i >= 0; --i) {
      var list = innerTypeParameters[i];
      int index = list.indexOf(node.parameter);
      if (index != -1) {
        return new NullabilityType(
            new FunctionTypeParameterAType(index + offset), modifiers.newKey());
      }
      offset += list.length;
    }
    return new NullabilityType(
        new TypeParameterAType(node.parameter), modifiers.newKey());
  }
}
