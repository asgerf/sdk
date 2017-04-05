library kernel.dataflow.extractor.common_values;

import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/extractor/augmented_type.dart';
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

  Value anyValue;
  Value nullableIntValue;
  Value nullableDoubleValue;
  Value nullableNumValue;
  Value nullableStringValue;
  Value nullableBoolValue;
  Value nullableFunctionValue;

  CommonValues(CoreTypes coreTypes) {
    intValue = new Value(coreTypes.intClass, ValueFlags.integer);
    doubleValue = new Value(coreTypes.doubleClass, ValueFlags.double_);
    numValue = new Value(coreTypes.numClass,
        ValueFlags.integer | ValueFlags.double_ | ValueFlags.inexactBaseClass);
    stringValue = new Value(coreTypes.stringClass, ValueFlags.string);
    boolValue = new Value(coreTypes.boolClass, ValueFlags.boolean);
    nullValue = new Value(null, ValueFlags.null_);
    functionValue = new Value(coreTypes.functionClass,
        ValueFlags.other | ValueFlags.inexactBaseClass);

    anyValue = new Value(coreTypes.objectClass, ValueFlags.all);
    nullableIntValue =
        new Value(coreTypes.intClass, ValueFlags.null_ | ValueFlags.integer);
    nullableDoubleValue =
        new Value(coreTypes.doubleClass, ValueFlags.null_ | ValueFlags.double_);
    nullableNumValue = new Value(
        coreTypes.numClass,
        ValueFlags.null_ |
            ValueFlags.integer |
            ValueFlags.double_ |
            ValueFlags.inexactBaseClass);
    nullableStringValue =
        new Value(coreTypes.stringClass, ValueFlags.null_ | ValueFlags.string);
    nullableBoolValue = new Value(coreTypes.boolClass, ValueFlags.boolean);
    nullableFunctionValue = new Value(coreTypes.functionClass,
        ValueFlags.null_ | ValueFlags.other | ValueFlags.inexactBaseClass);

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
        new Value(coreTypes.objectClass, ValueFlags.all),
        ValueSink.nowhere,
        coreTypes.objectClass, const <AType>[]);
    numType = new InterfaceAType(
        new Value(
            coreTypes.numClass,
            ValueFlags.integer |
                ValueFlags.double_ |
                ValueFlags.inexactBaseClass),
        ValueSink.nowhere,
        coreTypes.numClass,
        const <AType>[]);
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
