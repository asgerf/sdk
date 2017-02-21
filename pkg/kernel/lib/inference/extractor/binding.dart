// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.binding;

import '../../ast.dart';
import '../../core_types.dart';
import '../storage_location.dart';
import 'augmented_type.dart';
import 'type_augmentor.dart';

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

  TypeAugmentor getAugmentor([int offset]) {
    return new AugmentorVisitor(coreTypes, this, offset);
  }
}

/// The storage location bank for a member.
///
/// Provides access to the augmented public interface of the member.
abstract class MemberBank extends StorageLocationBank {
  MemberBank(CoreTypes coreTypes) : super(coreTypes);

  AType get type;
}

/// The storage location bank for a field.
class FieldBank extends MemberBank {
  final Field field;
  AType type;

  FieldBank(this.field, CoreTypes coreTypes) : super(coreTypes);

  Member get classOrMember => field;
}

/// The storage location bank for a procedure or constructor.
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

/// The storage location bank for a class.
///
/// Provides access to the augmented type parameter bounds and augmented
/// [supertypes].
class ClassBank extends StorageLocationBank {
  final Class classNode;
  List<AType> typeParameters;
  List<ASupertype> supertypes;

  ClassBank(this.classNode, CoreTypes coreTypes) : super(coreTypes);

  Class get classOrMember => classNode;
}
