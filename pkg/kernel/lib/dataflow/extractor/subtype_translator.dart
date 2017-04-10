// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.constraints_from_subtyping;

import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/extractor/augmented_type.dart';
import 'package:kernel/dataflow/extractor/constraint_builder.dart';
import 'package:kernel/dataflow/extractor/constraint_extractor.dart';
import 'package:kernel/dataflow/storage_location.dart';
import 'package:kernel/dataflow/value.dart';

/// Translates subtyping judgements into constraints.
class SubtypeTranslator implements SubtypingScope {
  final ConstraintBuilder builder;
  final TypeParameterScope scope;
  final CoreTypes coreTypes;

  SubtypeTranslator(this.builder, this.scope, this.coreTypes);

  ValueLattice get lattice => builder.lattice;

  void addSubtype(AType subtype, AType supertype) {
    bool isValidSubtype = _checkSubtypeStructure(subtype, supertype);
    // If the subtype check failed, insert a type filter to weed out spurious
    // value flow.  If the check passed, the filter is unnecessary, so we leave
    // it out in order to save time for the solver (filters are expensive).
    TypeFilter filter =
        isValidSubtype ? TypeFilter.none : getTypeFilter(supertype);
    builder.addAssignmentWithFilter(subtype.source, supertype.sink, filter);
  }

  void addSubBound(AType subbound, AType superbound) {
    if (subbound is TypeParameterAType) {
      // TODO: Clean this up.
      if (superbound.source is StorageLocation) {
        StorageLocation superSource = superbound.source as StorageLocation;
        builder.addAssignment(subbound.source, superSource, ValueFlags.null_);
      }
      if (superbound.sink is StorageLocation) {
        StorageLocation superSink = superbound.sink as StorageLocation;
        builder.addAssignment(superSink, subbound.sink, ValueFlags.null_);
      }
      if (superbound is TypeParameterAType &&
          superbound.parameter == subbound.parameter) {
        return;
      }
      var bound = scope.getTypeParameterBound(subbound.parameter);
      addSubBound(bound, superbound);
    } else {
      bool ok = _checkSubtypeStructure(subbound, superbound);
      var superFilter = getTypeFilter(superbound);
      if (superbound.source is StorageLocation) {
        // Add a type filter on the upper bound if the subtype checks failed.
        TypeFilter filter = ok ? TypeFilter.none : superFilter;
        StorageLocation superSource = superbound.source as StorageLocation;
        builder.addAssignmentWithFilter(subbound.source, superSource, filter);
      }
      if (superbound.sink is StorageLocation) {
        // Because of covariant subtyping, the lower bound check is never safe,
        // so we always use a type filter here.  The filter is sound because of
        // the checks inserted for covariant subtyping.
        StorageLocation superSink = superbound.sink as StorageLocation;
        builder.addAssignmentWithFilter(superSink, subbound.sink, superFilter);
      }
    }
  }

  bool _checkSubtypeStructure(AType subtype, AType supertype) {
    if (subtype is InterfaceAType && supertype is InterfaceAType) {
      var casted = builder.getTypeAsInstanceOf(subtype, supertype.classNode);
      if (casted == null) return false;
      for (int i = 0; i < casted.typeArguments.length; ++i) {
        var subtypeArgument = casted.typeArguments[i];
        var supertypeArgument = supertype.typeArguments[i];
        addSubBound(subtypeArgument, supertypeArgument);
      }
      return true;
    }
    if (subtype is FunctionAType && supertype is FunctionAType) {
      // TODO: Instantiate one function to the other.
      for (int i = 0; i < subtype.typeParameterBounds.length; ++i) {
        if (i < supertype.typeParameterBounds.length) {
          // TODO: We should use sub bound check.
          // I'm not sure about which direction.
          addSubtype(
              supertype.typeParameterBounds[i], subtype.typeParameterBounds[i]);
        }
      }
      for (int i = 0; i < subtype.positionalParameters.length; ++i) {
        if (i < supertype.positionalParameters.length) {
          addSubtype(supertype.positionalParameters[i],
              subtype.positionalParameters[i]);
        }
      }
      for (int i = 0; i < subtype.namedParameters.length; ++i) {
        String name = subtype.namedParameterNames[i];
        int j = supertype.namedParameterNames.indexOf(name);
        if (j != -1) {
          addSubtype(supertype.namedParameters[j], subtype.namedParameters[i]);
        }
      }
      addSubtype(subtype.returnType, supertype.returnType);
      return true;
    }
    if (subtype is FunctionTypeParameterAType) {
      // TODO: Compare with bound.
      return true;
    }
    if (subtype is TypeParameterAType) {
      if (supertype is TypeParameterAType &&
          subtype.parameter == supertype.parameter) {
        return true;
      }
      var bound = scope.getTypeParameterBound(subtype.parameter);
      addSubtype(bound, supertype);
      return true;
    }
    if (subtype is BottomAType) {
      return true;
    }
    return false;
  }

  TypeFilter getTypeFilter(AType type) {
    if (type is InterfaceAType) {
      var classNode = type.classNode;
      return new TypeFilter(
          classNode, lattice.getValueSetFlagsForInterface(classNode));
    }
    if (type is FunctionAType) {
      return new TypeFilter(
          coreTypes.functionClass, ValueFlags.null_ | ValueFlags.other);
    }
    return TypeFilter.none;
  }
}
