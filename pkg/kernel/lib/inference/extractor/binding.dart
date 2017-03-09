// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.binding;

import '../../ast.dart';
import '../../core_types.dart';
import '../storage_location.dart';
import 'augmented_type.dart';
import 'package:kernel/inference/raw_binding.dart';
import 'type_augmentor.dart';

/// Constructs augmented types and generates storage location banks.
class Binding {
  final CoreTypes coreTypes;
  final RawBinding rawBinding = new RawBinding();
  final Map<Class, ClassBank> classBanks = <Class, ClassBank>{};
  final Map<Member, MemberBank> memberBanks = <Member, MemberBank>{};

  GlobalAugmentorScope _augmentorScope;

  Binding(this.coreTypes) {
    _augmentorScope = new GlobalAugmentorScope(this);
  }

  AugmentorScope get globalAugmentorScope => _augmentorScope;

  MemberBank _initializeMemberBank(Member member) {
    if (member is Field) {
      var bank =
          new FieldBank(rawBinding.getBinding(member.reference), coreTypes);
      memberBanks[member] = bank;
      bank.type =
          bank.getFreshAugmentor(_augmentorScope).augmentType(member.type);
      return bank;
    } else {
      var bank = new FunctionMemberBank(
          rawBinding.getBinding(member.reference), coreTypes);
      memberBanks[member] = bank;
      var function = member.function;
      bank.typeParameters = new List<TypeParameterStorageLocation>.generate(
          function.typeParameters.length,
          (i) => new TypeParameterStorageLocation(member, i));
      bank.type = bank
          .getFreshAugmentor(_augmentorScope)
          .augmentType(function.functionType);
      for (int i = 0; i < function.typeParameters.length; ++i) {
        StorageLocation location = bank.typeParameterBounds[i].source;
        bank.typeParameters[i].indexOfBound = location.index;
      }
      return bank;
    }
  }

  StorageLocationBank _initializeClassBank(Class class_) {
    var bank =
        new ClassBank(rawBinding.getBinding(class_.reference), coreTypes);
    classBanks[class_] = bank;
    bank.typeParameters = new List<TypeParameterStorageLocation>.generate(
        class_.typeParameters.length,
        (i) => new TypeParameterStorageLocation(class_, i));
    var augmentor = bank.getFreshAugmentor(_augmentorScope);
    bank.typeParameterBounds = class_.typeParameters
        .map((p) => augmentor.augmentBound(p.bound))
        .toList(growable: false);
    bank.supertypes = class_.supers
        .map((s) => augmentor.augmentSuper(s))
        .toList(growable: false);
    for (int i = 0; i < class_.typeParameters.length; ++i) {
      StorageLocation location = bank.typeParameterBounds[i].source;
      bank.typeParameters[i].indexOfBound = location.index;
    }
    return bank;
  }

  StorageLocation getBoundForParameter(TypeParameterStorageLocation parameter) {
    if (parameter.owner is Class) {
      var bank = getClassBank(parameter.owner);
      return bank.locations[parameter.indexOfBound];
    } else {
      var bank = getFunctionBank(parameter.owner);
      return bank.locations[parameter.indexOfBound];
    }
  }

  ClassBank getClassBank(Class class_) {
    return classBanks[class_] ?? _initializeClassBank(class_);
  }

  MemberBank getMemberBank(Member member) {
    return memberBanks[member] ?? _initializeMemberBank(member);
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

class GlobalAugmentorScope extends AugmentorScope {
  final Binding binding;

  GlobalAugmentorScope(this.binding);

  TypeParameterStorageLocation getTypeParameterLocation(
      TypeParameter parameter) {
    var parent = parameter.parent;
    if (parent is Class) {
      int index = parent.typeParameters.indexOf(parameter);
      return binding.getClassBank(parent).typeParameters[index];
    } else {
      FunctionNode function = parent;
      Member member = function.parent;
      int index = function.typeParameters.indexOf(parameter);
      return binding.getFunctionBank(member).typeParameters[index];
    }
  }
}

abstract class StorageLocationBank {
  final CoreTypes coreTypes;
  final RawMemberBinding binding;
  List<StorageLocation> get locations => binding.locations;

  StorageLocationBank(this.binding, this.coreTypes);

  NamedNode get classOrMember => binding.reference.node;

  int get nextIndex => locations.length;

  StorageLocation newLocation() {
    var location =
        new StorageLocation(classOrMember.reference, locations.length);
    locations.add(location);
    return location;
  }

  /// Returns a type augmentor that generates fresh storage locations from this
  /// bank for the types that it augments.
  TypeAugmentor getFreshAugmentor(AugmentorScope scope) {
    return new AugmentorVisitor.fresh(coreTypes, this, scope);
  }

  /// Returns a type augmentor that uses existing storage locations from this
  /// bank for the types that it augments, starting at [offset].
  TypeAugmentor getReusingAugmentor(int offset) {
    return new AugmentorVisitor.reusing(coreTypes, this, offset);
  }
}

/// The storage location bank for a member.
///
/// Provides access to the augmented public interface of the member.
abstract class MemberBank extends StorageLocationBank {
  MemberBank(RawMemberBinding binding, CoreTypes coreTypes)
      : super(binding, coreTypes);

  AType get type;
}

/// The storage location bank for a field.
class FieldBank extends MemberBank {
  AType type;

  FieldBank(RawMemberBinding binding, CoreTypes coreTypes)
      : super(binding, coreTypes);

  Field get field => binding.reference.asField;
}

/// The storage location bank for a procedure or constructor.
class FunctionMemberBank extends MemberBank {
  List<TypeParameterStorageLocation> typeParameters;
  FunctionAType type;

  FunctionMemberBank(RawMemberBinding binding, CoreTypes coreTypes)
      : super(binding, coreTypes);

  AType get returnType => type.returnType;
  List<AType> get typeParameterBounds => type.typeParameterBounds;
  List<AType> get positionalParameters => type.positionalParameters;
  List<AType> get namedParameters => type.namedParameters;

  Member get member => binding.reference.asMember;
}

/// The storage location bank for a class.
///
/// Provides access to the augmented type parameter bounds and augmented
/// [supertypes].
class ClassBank extends StorageLocationBank {
  List<TypeParameterStorageLocation> typeParameters;
  List<AType> typeParameterBounds;
  List<ASupertype> supertypes;

  ClassBank(RawMemberBinding binding, CoreTypes coreTypes)
      : super(binding, coreTypes);

  Class get classNode => binding.reference.asClass;
}
