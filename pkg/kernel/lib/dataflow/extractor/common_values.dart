library kernel.dataflow.extractor.common_values;

import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/extractor/augmented_type.dart';
import 'package:kernel/dataflow/extractor/backend_core_types.dart';
import 'package:kernel/dataflow/extractor/value_sink.dart';
import 'package:kernel/dataflow/value.dart';

class CommonValues {
  AType conditionType;
  AType escapingType;
  AType boolType;
  AType intType;
  AType doubleType;
  AType numType;
  AType stringType;
  AType symbolType;
  AType typeType;
  AType topType;

  Value intValue;
  Value doubleValue;
  Value numValue;
  Value stringValue;
  Value boolValue;
  Value nullValue;
  Value functionValue;
  Value growableListValue;
  Value fixedListValue;
  Value constListValue;
  Value literalMapValue;
  Value constLiteralMapValue;

  Value anyValue;
  Value nullableIntValue;
  Value nullableDoubleValue;
  Value nullableNumValue;
  Value nullableStringValue;
  Value nullableBoolValue;
  Value nullableFunctionValue;
  Value nullableEscapingFunctionValue;

  CommonValues(CoreTypes coreTypes, BackendApi backend, ValueLattice lattice) {
    // Copy over the values redeclared by this class.
    intValue = backend.intValue;
    doubleValue = backend.doubleValue;
    stringValue = backend.stringValue;
    boolValue = backend.boolValue;
    growableListValue = backend.growableListValue;
    fixedListValue = backend.fixedLengthListValue;
    constListValue = backend.immutableListValue;
    literalMapValue = backend.linkedHashMapValue;
    constLiteralMapValue = backend.immutableMapValue;

    // Build other commonly used values that are not defined by the backend.
    numValue = lattice.joinValues(intValue, doubleValue);
    nullValue = new Value(null, ValueFlags.null_);
    // TODO: Do not treat functions as base classes.
    functionValue = new Value(coreTypes.functionClass,
        ValueFlags.other | ValueFlags.inexactBaseClass);

    anyValue = new Value(coreTypes.objectClass, ValueFlags.all);
    nullableIntValue = intValue.asNullable;
    nullableDoubleValue = doubleValue.asNullable;
    nullableNumValue = numValue.asNullable;
    nullableStringValue = stringValue.asNullable;
    nullableBoolValue = boolValue.asNullable;
    nullableFunctionValue = functionValue.asNullable;
    nullableEscapingFunctionValue = new Value(
        coreTypes.functionClass,
        ValueFlags.other |
            ValueFlags.inexactBaseClass |
            ValueFlags.null_ |
            ValueFlags.escaping);

    conditionType = new InterfaceAType(
        Value.bottom, ValueSink.nowhere, coreTypes.boolClass, const <AType>[]);
    escapingType = new BottomAType(Value.bottom, ValueSink.escape);
    boolType = new InterfaceAType(
        boolValue, ValueSink.nowhere, coreTypes.boolClass, const <AType>[]);
    intType = new InterfaceAType(
        intValue, ValueSink.nowhere, coreTypes.intClass, const <AType>[]);
    doubleType = new InterfaceAType(
        doubleValue, ValueSink.nowhere, coreTypes.doubleClass, const <AType>[]);
    stringType = new InterfaceAType(
        stringValue, ValueSink.nowhere, coreTypes.stringClass, const <AType>[]);
    topType = new InterfaceAType(
        anyValue, ValueSink.nowhere, coreTypes.objectClass, const <AType>[]);
    numType = new InterfaceAType(
        numValue, ValueSink.nowhere, coreTypes.numClass, const <AType>[]);
    symbolType = new InterfaceAType(
        new Value(coreTypes.symbolClass, ValueFlags.other),
        ValueSink.nowhere,
        coreTypes.symbolClass, const <AType>[]);
    typeType = new InterfaceAType(
        new Value(coreTypes.typeClass, ValueFlags.other),
        ValueSink.nowhere,
        coreTypes.typeClass, const <AType>[]);
  }
}
