// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.binding;

import '../../ast.dart';
import '../../core_types.dart';
import '../storage_location.dart';
import 'augmented_type.dart';

/// Constructs augmented types and generates storage location banks.
class Binding {
  final CoreTypes coreTypes;
  final Map<Class, ClassBank> classBanks = <Class, ClassBank>{};
  final Map<Member, MemberBank> memberBanks = <Member, MemberBank>{};

  Binding(this.coreTypes);

  MemberBank _initializeMemberBank(Member member) {
    if (member is Field) {
      var bank = new FieldBank(member, coreTypes);
      bank.type = bank.getAugmentor().augmentType(member.type);
      return bank;
    } else {
      var bank = new FunctionMemberBank(member, coreTypes);
      var function = member.function;
      bank.type = bank.getAugmentor().augmentType(function.functionType);
      return bank;
    }
  }

  StorageLocationBank _initializeClassBank(Class class_) {
    var bank = new ClassBank(class_, coreTypes);
    var augmentor = bank.getAugmentor();
    bank.typeParameters = class_.typeParameters
        .map((p) => augmentor.augmentBound(p.bound))
        .toList(growable: false);
    bank.supertypes = class_.supers
        .map((s) => augmentor.augmentSuper(s))
        .toList(growable: false);
    return bank;
  }

  ClassBank getClassBank(Class class_) {
    return classBanks[class_] ??= _initializeClassBank(class_);
  }

  MemberBank getMemberBank(Member member) {
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
      var bank = getFunctionBank(member);
      return member.isGetter ? bank.type.returnType : bank.type;
    }
    throw '$member cannot be used as a getter';
  }

  AType getSetterType(Member member) {
    if (member is Field) return getFieldType(member);
    if (member is Procedure && member.isSetter) {
      var bank = getFunctionBank(member);
      return bank.type.positionalParameters[0];
    }
    throw '$member cannot be used as a setter';
  }
}

abstract class StorageLocationBank {
  final CoreTypes coreTypes;
  final List<StorageLocation> locations = <StorageLocation>[];

  StorageLocationBank(this.coreTypes);

  TreeNode get classOrMember;

  int get nextIndex => locations.length;

  StorageLocation newLocation() {
    var location = new StorageLocation(classOrMember, locations.length);
    locations.add(location);
    return location;
  }

  Augmentor getAugmentor([int offset]) {
    return new AugmentorVisitor(coreTypes, this, offset);
  }
}

abstract class MemberBank extends StorageLocationBank {
  MemberBank(CoreTypes coreTypes) : super(coreTypes);

  AType get type;
}

class FieldBank extends MemberBank {
  final Field field;
  AType type;

  FieldBank(this.field, CoreTypes coreTypes) : super(coreTypes);

  Member get classOrMember => field;
}

class FunctionMemberBank extends MemberBank {
  final Member member;
  FunctionAType type;

  FunctionMemberBank(this.member, CoreTypes coreTypes) : super(coreTypes);

  AType get returnType => type.returnType;
  List<AType> get typeParameters => type.typeParameters;
  List<AType> get positionalParameters => type.positionalParameters;
  List<AType> get namedParameters => type.namedParameters;

  Member get classOrMember => member;
}

class ClassBank extends StorageLocationBank {
  final Class classNode;
  List<AType> typeParameters;
  List<ASupertype> supertypes;

  ClassBank(this.classNode, CoreTypes coreTypes) : super(coreTypes);

  Class get classOrMember => classNode;
}

abstract class Augmentor {
  int index;
  AType augmentType(DartType type);
  AType augmentBound(DartType type);
  ASupertype augmentSuper(Supertype type);
  List<AType> augmentTypeList(List<DartType> types);
  List<AType> augmentBoundList(List<DartType> types);
  List<ASupertype> augmentSuperList(List<Supertype> types);
}

class AugmentorVisitor extends DartTypeVisitor<AType> implements Augmentor {
  final CoreTypes coreTypes;
  final StorageLocationBank bank;
  final List<List<TypeParameter>> innerTypeParameters = <List<TypeParameter>>[];
  StorageLocation source, sink;
  int index;

  AugmentorVisitor(this.coreTypes, this.bank, this.index);

  AType augmentType(DartType type) {
    source = sink = nextLocation();
    return type.accept(this);
  }

  AType augmentBound(DartType type) {
    source = nextLocation();
    sink = nextLocation();
    return type.accept(this);
  }

  ASupertype augmentSuper(Supertype type) {
    return new ASupertype(type.classNode,
        type.typeArguments.map(augmentType).toList(growable: false));
  }

  List<AType> augmentTypeList(List<DartType> types) {
    return types.map(augmentType).toList(growable: false);
  }

  List<AType> augmentBoundList(List<DartType> types) {
    return types.map(augmentBound).toList(growable: false);
  }

  List<ASupertype> augmentSuperList(List<Supertype> types) {
    return types.map(augmentSuper).toList(growable: false);
  }

  StorageLocation nextLocation() {
    if (index == null) {
      return bank.newLocation();
    } else {
      return bank.locations[index++];
    }
  }

  visitInvalidType(InvalidType node) {
    return new InterfaceAType(
        source, sink, coreTypes.objectClass, const <AType>[]);
  }

  visitDynamicType(DynamicType node) {
    return new InterfaceAType(
        source, sink, coreTypes.objectClass, const <AType>[]);
  }

  visitVoidType(VoidType node) {
    return new BottomAType(source, sink);
  }

  visitBottomType(BottomType node) {
    return new BottomAType(source, sink);
  }

  visitInterfaceType(InterfaceType node) {
    return new InterfaceAType(source, sink, node.classNode,
        node.typeArguments.map(augmentBound).toList(growable: false));
  }

  visitFunctionType(FunctionType node) {
    innerTypeParameters.add(node.typeParameters);
    var type = new FunctionAType(
        source,
        sink,
        node.typeParameters
            .map((p) => augmentBound(p.bound))
            .toList(growable: false),
        node.requiredParameterCount,
        node.positionalParameters.map(augmentType).toList(growable: false),
        node.namedParameters.map((t) => t.name).toList(growable: false),
        node.namedParameters
            .map((t) => augmentType(t.type))
            .toList(growable: false),
        augmentType(node.returnType));
    innerTypeParameters.removeLast();
    return type;
  }

  visitTypeParameterType(TypeParameterType node) {
    for (int i = innerTypeParameters.length - 1; i >= 0; --i) {
      var list = innerTypeParameters[i];
      int index = list.indexOf(node.parameter);
      if (index != -1) {
        return new FunctionTypeParameterAType(source, sink, index);
      }
    }
    source.isNullabilityKey = true;
    sink.isNullabilityKey = true;
    return new TypeParameterAType(source, sink, node.parameter);
  }
}
