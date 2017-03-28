// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.type_augmentor;

import 'augmented_type.dart';
import 'binding.dart';
import '../storage_location.dart';
import '../../ast.dart';
import '../../core_types.dart';

abstract class AugmentorScope {
  TypeParameterStorageLocation getTypeParameterLocation(
      TypeParameter parameter);
}

class NullAugmentorScope extends AugmentorScope {
  TypeParameterStorageLocation getTypeParameterLocation(
      TypeParameter parameter) {
    return null;
  }
}

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
  final AugmentorScope scope;
  StorageLocation source, sink;
  int index;

  bool get isGeneratingFreshStorageLocations => scope != null;

  AugmentorVisitor.fresh(this.coreTypes, this.bank, this.scope) : index = null;

  AugmentorVisitor.reusing(this.coreTypes, this.bank, this.index)
      : scope = null;

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
    int shift = 0;
    for (int i = innerTypeParameters.length - 1; i >= 0; --i) {
      var list = innerTypeParameters[i];
      int index = list.indexOf(node.parameter);
      if (index != -1) {
        return new FunctionTypeParameterAType(source, sink, index + shift);
      }
      shift += list.length;
    }
    if (isGeneratingFreshStorageLocations) {
      var parameterLocation = scope.getTypeParameterLocation(node.parameter);
      source.parameterLocation = parameterLocation;
      sink.parameterLocation = parameterLocation;
    }
    return new TypeParameterAType(source, sink, node.parameter);
  }
}
