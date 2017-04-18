// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.backend_core_types;

import 'package:kernel/ast.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/value.dart';

abstract class BackendCoreTypes {
  Value get intValue;
  Value get doubleValue;
  Value get stringValue;
  Value get boolValue;
  Value get growableListValue;
  Value get fixedLengthListValue;
  Value get immutableListValue;
  Value get linkedHashMapValue;
  Value get immutableMapValue;
  Value get typeValue;

  Procedure get listFactory;
}

class VmCoreTypes extends BackendCoreTypes {
  final Value intValue;
  final Value doubleValue;
  final Value stringValue;
  final Value boolValue;
  final Value growableListValue;
  final Value fixedLengthListValue;
  final Value immutableListValue;
  final Value linkedHashMapValue;
  final Value immutableMapValue;
  final Value typeValue;

  final Procedure listFactory;

  VmCoreTypes(CoreTypes coreTypes)
      : intValue = new Value(
            coreTypes.getClass('dart:core', '_IntegerImplementation'),
            ValueFlags.integer | ValueFlags.inexactBaseClass),
        doubleValue = new Value(
            coreTypes.getClass('dart:core', '_Double'), ValueFlags.double_),
        stringValue = new Value(coreTypes.getClass('dart:core', '_StringBase'),
            ValueFlags.string | ValueFlags.inexactBaseClass),
        boolValue = new Value(coreTypes.boolClass, ValueFlags.boolean),
        growableListValue = new Value(
            coreTypes.getClass('dart:core', '_GrowableList'), ValueFlags.other),
        fixedLengthListValue = new Value(
            coreTypes.getClass('dart:core', '_List'), ValueFlags.other),
        immutableListValue = new Value(
            coreTypes.getClass('dart:core', '_ImmutableList'),
            ValueFlags.other),
        linkedHashMapValue = new Value(
            coreTypes.getClass('dart:collection', 'LinkedHashMap'),
            ValueFlags.other),
        immutableMapValue = new Value(
            coreTypes.getClass('dart:core', '_ImmutableMap'), ValueFlags.other),
        typeValue = new Value(coreTypes.getClass('dart:core', '_AbstractType'),
            ValueFlags.other | ValueFlags.inexactBaseClass),
        listFactory = coreTypes.getMember('dart:core', 'List', '_internal');
}
