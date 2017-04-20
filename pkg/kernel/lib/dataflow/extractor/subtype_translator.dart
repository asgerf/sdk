// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.constraints_from_subtyping;

import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/extractor/augmented_hierarchy.dart';
import 'package:kernel/dataflow/extractor/augmented_type.dart';
import 'package:kernel/dataflow/extractor/common_values.dart';
import 'package:kernel/dataflow/extractor/constraint_extractor.dart';
import 'package:kernel/dataflow/extractor/source_sink_translator.dart';
import 'package:kernel/dataflow/value.dart';

/// Translates subtyping judgements into constraints.
class SubtypeTranslator extends SourceSinkTranslator {
  final CoreTypes coreTypes;

  SubtypeTranslator(
      ConstraintSystem constraintSystem,
      AugmentedHierarchy hierarchy,
      ValueLattice lattice,
      CommonValues common,
      this.coreTypes)
      : super(constraintSystem, hierarchy, lattice, common);

  /// Generates constraints to ensure [subtype] is subtype of [supertype],
  /// which includes all the derived subtyping judgements that arise from
  /// checking that judgement.
  void addSubtype(AType subtype, AType supertype, TypeParameterScope scope) {
    bool isValidSubtype = _checkSubtypeStructure(subtype, supertype, scope);
    // If the subtype check failed, insert a type filter to weed out spurious
    // value flow.  If the check passed, the filter is unnecessary, so we leave
    // it out in order to save time for the solver (filters are expensive).
    TypeFilter filter =
        isValidSubtype ? TypeFilter.none : getTypeFilter(supertype);
    addAssignment(subtype.source, supertype.sink, filter);
  }

  /// Generates constraints to ensure [subbound] is a subbound of [superbound],
  /// that is, its upper bound is a subtype thereof and its lower bound is a
  /// supertype thereof.
  void addSubBound(AType subbound, AType superbound, TypeParameterScope scope) {
    if (subbound is TypeParameterAType) {
      // TODO: Clean this up.
      addSourceToSourceAssignment(
          subbound.source, superbound.source, TypeFilter.null_);
      addSinkToSinkAssignment(superbound.sink, subbound.sink, TypeFilter.null_);
      if (superbound is TypeParameterAType &&
          superbound.parameter == subbound.parameter) {
        return;
      }
      var bound = scope.getTypeParameterBound(subbound.parameter);
      addSubBound(bound, superbound, scope);
    } else {
      bool ok = _checkSubtypeStructure(subbound, superbound, scope);
      // Add a type filter on the upper bound if the subtype checks failed.
      addSourceToSourceAssignment(subbound.source, superbound.source,
          ok ? TypeFilter.none : getTypeFilter(superbound));
      // Because of covariant subtyping, the lower bound check is never safe,
      // so we always use a type filter here.  The filter is sound because of
      // the checks inserted for covariant subtyping.
      addSinkToSinkAssignment(
          superbound.sink, subbound.sink, getTypeFilter(subbound));
    }
  }

  /// Determines if [subtype] is a subtype of [supertype], and recursively
  /// generates constraints for the underlying subtyping judgements that from
  /// this judgement.
  bool _checkSubtypeStructure(
      AType subtype, AType supertype, TypeParameterScope scope) {
    if (subtype is InterfaceAType && supertype is InterfaceAType) {
      var casted = hierarchy.getTypeAsInstanceOf(subtype, supertype.classNode);
      if (casted == null) return false;
      for (int i = 0; i < casted.typeArguments.length; ++i) {
        var subtypeArgument = casted.typeArguments[i];
        var supertypeArgument = supertype.typeArguments[i];
        addSubBound(subtypeArgument, supertypeArgument, scope);
      }
      return true;
    }
    if (subtype is FunctionAType && supertype is FunctionAType) {
      // TODO: Instantiate one function to the other.
      for (int i = 0; i < subtype.typeParameterBounds.length; ++i) {
        if (i < supertype.typeParameterBounds.length) {
          // TODO: We should use sub bound check.
          // I'm not sure about which direction.
          addSubtype(supertype.typeParameterBounds[i],
              subtype.typeParameterBounds[i], scope);
        }
      }
      for (int i = 0; i < subtype.positionalParameters.length; ++i) {
        if (i < supertype.positionalParameters.length) {
          addSubtype(supertype.positionalParameters[i],
              subtype.positionalParameters[i], scope);
        }
      }
      for (int i = 0; i < subtype.namedParameters.length; ++i) {
        String name = subtype.namedParameterNames[i];
        int j = supertype.namedParameterNames.indexOf(name);
        if (j != -1) {
          addSubtype(
              supertype.namedParameters[j], subtype.namedParameters[i], scope);
        }
      }
      addSubtype(subtype.returnType, supertype.returnType, scope);
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
      addSubtype(bound, supertype, scope);
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
