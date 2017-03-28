import 'package:kernel/ast.dart';
import 'package:kernel/dataflow/extractor/augmented_type.dart';
import 'package:kernel/dataflow/extractor/value_sink.dart';
import 'package:kernel/dataflow/value.dart';
import 'package:test/test.dart';

FunctionAType fun(
    List<AType> typeArgs, List<AType> parameters, AType returnType) {
  return new FunctionAType(Value.bottom, ValueSink.nowhere, typeArgs, 1,
      parameters, [], [], returnType);
}

FunctionTypeParameterAType typeArg(int n) {
  return new FunctionTypeParameterAType(Value.bottom, ValueSink.nowhere, n);
}

Library dummyLibrary = new Library(Uri.parse('test:test'), name: 'test');

AType groundTerm(String name) {
  var class_ = new Class(name: name)..parent = dummyLibrary;
  return new InterfaceAType(Value.bottom, ValueSink.nowhere, class_, const []);
}

void main() {
  var bound = groundTerm('Bound');
  var arg1 = groundTerm('Arg1');
  var arg2 = groundTerm('Arg2');
  var t0 = typeArg(0);
  var t1 = typeArg(1);
  var t2 = typeArg(2);
  test('<T>() => T', () {
    expect(fun([bound], [], t0).instantiate([arg1]).returnType, equals(arg1));
  });
  test('<T>(T) => T', () {
    expect(fun([bound], [t0], t0).instantiate([arg1]).positionalParameters[0],
        equals(arg1));
  });
  test('<T>(T) => <G>(T,G) => G', () {
    var function = fun([bound], [t0], fun([bound], [t1, t0], t0));
    expect(function.instantiate([arg1]).positionalParameters[0], equals(arg1));
  });
  test('<T>(T) => <G>(T,G) => G', () {
    var function = fun([bound], [t0], fun([bound], [t1, t0], t0));
    FunctionAType function2 = function.instantiate([arg1]).returnType;
    expect(function2.returnType, equals(t0));
    expect(function2.positionalParameters[0], equals(arg1));
    expect(function2.instantiate([arg2]).positionalParameters[1], equals(arg2));
  });
  test('<T,U>(T) => <G>(T,U) => G', () {
    var function = fun([bound, bound], [t0], fun([bound], [t1, t2], t0));
    FunctionAType function2 = function.instantiate([arg1, arg2]).returnType;
    expect(function2.returnType, equals(t0));
    expect(function2.positionalParameters[0], equals(arg1));
    expect(function2.positionalParameters[1], equals(arg2));
  });
}
