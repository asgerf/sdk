// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.external_model;

import '../../ast.dart';
import '../../core_types.dart';

abstract class ExternalModel {
  /// True if [member] does not return `null` and does not cause any objects
  /// to escape.
  bool isNicelyBehaved(Member member);
}

class VmExternalModel extends ExternalModel {
  final CoreTypes coreTypes;
  Class externalNameAnnotation;

  static final Set<String> niceMembers = new Set<String>.from([
    // doubles
    'Double_add',
    'Double_ceil',
    'Double_div',
    'Double_doubleFromInteger',
    'Double_equal',
    'Double_equalToInteger',
    'Double_flipSignBit',
    'Double_floor',
    'Double_getIsInfinite',
    'Double_getIsNaN',
    'Double_getIsNegative',
    'Double_greaterThan',
    'Double_greaterThanFromInteger',
    'Double_modulo',
    'Double_mul',
    'Double_remainder',
    'Double_round',
    'Double_sub',
    'Double_toInt',
    'Double_toString',
    'Double_toStringAsExponential',
    'Double_toStringAsFixed',
    'Double_toStringAsPrecision',
    'Double_trunc_div',
    'Double_truncate',

    // integers
    'Integer_addFromInteger',
    'Integer_bitAndFromInteger',
    'Integer_bitOrFromInteger',
    'Integer_bitXorFromInteger',
    'Integer_equalToInteger',
    'Integer_greaterThanFromInteger',
    'Integer_moduloFromInteger',
    'Integer_mulFromInteger',
    'Integer_subFromInteger',
    'Integer_truncDivFromInteger',

    // strings
    'String_charAt',
    'String_codeUnitAt',
    'String_concat',
    'String_concatRange',
    'String_getHashCode',
    'String_getLength',
    'String_toLowerCase',
    'String_toUpperCase',
    'StringBase_createFromCodePoints',
    'StringBase_joinReplaceAllResult',
    'StringBase_substringUnchecked',
    'StringBuffer_createStringFromUint16Array',
    'StringToSystemEncoding',
  ]);

  VmExternalModel(this.coreTypes) {
    externalNameAnnotation =
        coreTypes.getCoreClass('dart:_internal', 'ExternalName');
  }

  ConstructorInvocation getAnnotation(
      List<Expression> annotations, Class class_) {
    for (var annotation in annotations) {
      if (annotation is ConstructorInvocation &&
          annotation.target.enclosingClass == class_) {
        return annotation;
      }
    }
    return null;
  }

  String getAsString(Expression node) {
    return node is StringLiteral ? node.value : null;
  }

  bool isNicelyBehaved(Member member) {
    var annotation = getAnnotation(member.annotations, externalNameAnnotation);
    if (annotation == null) return false;
    if (annotation.arguments.positional.length < 1) return false;
    String name = getAsString(annotation.arguments.positional[0]);
    return niceMembers.contains(name);
  }
}
