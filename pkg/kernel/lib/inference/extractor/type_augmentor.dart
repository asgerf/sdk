// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.type_augmentor;

import 'augmented_type.dart';
import 'binding.dart';
import '../storage_location.dart';
import '../../ast.dart';
import '../../core_types.dart';

/// Translates ordinary Dart types into augmented types.
///
/// Augmented types are tied to specific storage locations - the augmentor takes
/// these from the given [bank] sequentially from the current [index].
///
/// This is a stateful object.  The [index] will advance as types are augmented.
/// If [index] is `null`, fresh storage locations are generated from the bank
/// on-the-fly.
abstract class TypeAugmentor {
  StorageLocationBank get bank;
  int index;

  AType augmentType(DartType type);
  AType augmentBound(DartType type);
  ASupertype augmentSuper(Supertype type);
  List<AType> augmentTypeList(List<DartType> types);
  List<AType> augmentBoundList(List<DartType> types);
  List<ASupertype> augmentSuperList(List<Supertype> types);
}

class AugmentorVisitor extends DartTypeVisitor<AType> implements TypeAugmentor {
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
