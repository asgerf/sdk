// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/analysis/base.dart';
import 'element_text.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(TopLevelInferenceTest);
//    defineReflectiveTests(ApplyCheckElementTextReplacements);
  });
}

@reflectiveTest
class ApplyCheckElementTextReplacements {
  test_applyReplacements() {
    applyCheckElementTextReplacements();
  }
}

@reflectiveTest
class TopLevelInferenceTest extends BaseAnalysisDriverTest {
  test_initializer_as() async {
    var library = await _encodeDecodeLibrary(r'''
var V = 1 as num;
''');
    checkElementText(
        library,
        r'''
num V;
''');
  }

  @failingTest
  test_initializer_assignment() async {
    var library = await _encodeDecodeLibrary(r'''
var a = 1;
var b = a = 2;
var c = a += 2;
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
int a;
dynamic b;
dynamic c;
''');
  }

  test_initializer_await() async {
    var library = await _encodeDecodeLibrary(r'''
import 'dart:async';
int fValue() => 42;
Future<int> fFuture() async => 42;
var uValue = () async => await fValue();
var uFuture = () async => await fFuture();
''');
    checkElementText(
        library,
        r'''
import 'dart:async';
() → Future<int> uValue;
() → Future<int> uFuture;
int fValue() {}
Future<int> fFuture() async {}
''');
  }

  test_initializer_bitwise() async {
    var library = await _encodeDecodeLibrary(r'''
var vBitXor = 1 ^ 2;
var vBitAnd = 1 & 2;
var vBitOr = 1 | 2;
var vBitShiftLeft = 1 << 2;
var vBitShiftRight = 1 >> 2;
''');
    checkElementText(
        library,
        r'''
int vBitXor;
int vBitAnd;
int vBitOr;
int vBitShiftLeft;
int vBitShiftRight;
''');
  }

  test_initializer_cascade() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  int a;
  void m() {}
}
var vSetField = new A()..a = 1;
var vInvokeMethod = new A()..m();
var vBoth = new A()..a = 1..m();
''');
    checkElementText(
        library,
        r'''
class A {
  int a;
  void m() {}
}
A vSetField;
A vInvokeMethod;
A vBoth;
''');
  }

  test_initializer_conditional() async {
    var library = await _encodeDecodeLibrary(r'''
var V = true ? 1 : 2.3;
''');
    checkElementText(
        library,
        r'''
num V;
''');
  }

  test_initializer_functionExpression() async {
    var library = await _encodeDecodeLibrary(r'''
import 'dart:async';
var vFuture = new Future<int>(42);
var v_noParameters_inferredReturnType = () => 42;
var v_hasParameter_withType_inferredReturnType = (String a) => 42;
var v_hasParameter_withType_returnParameter = (String a) => a;
var v_async_returnValue = () async => 42;
var v_async_returnFuture = () async => vFuture;
''');
    checkElementText(
        library,
        r'''
import 'dart:async';
Future<int> vFuture;
() → int v_noParameters_inferredReturnType;
(String) → int v_hasParameter_withType_inferredReturnType;
(String) → String v_hasParameter_withType_returnParameter;
() → Future<int> v_async_returnValue;
() → Future<int> v_async_returnFuture;
''');
  }

  @failingTest
  test_initializer_functionExpressionInvocation_noTypeParameters() async {
    var library = await _encodeDecodeLibrary(r'''
var v = (() => 42)();
''');
    // TODO(scheglov) add more function expression tests
    checkElementText(
        library,
        r'''
int v;
''');
  }

  test_initializer_functionInvocation_hasTypeParameters() async {
    var library = await _encodeDecodeLibrary(r'''
T f<T>() => null;
var vHasTypeArgument = f<int>();
var vNoTypeArgument = f();
''');
    checkElementText(
        library,
        r'''
int vHasTypeArgument;
dynamic vNoTypeArgument;
T f<T>() {}
''');
  }

  test_initializer_functionInvocation_noTypeParameters() async {
    var library = await _encodeDecodeLibrary(r'''
String f(int p) => null;
var vOkArgumentType = f(1);
var vWrongArgumentType = f(2.0);
''');
    checkElementText(
        library,
        r'''
String vOkArgumentType;
String vWrongArgumentType;
String f(int p) {}
''');
  }

  test_initializer_identifier() async {
    var library = await _encodeDecodeLibrary(r'''
String topLevelFunction(int p) => null;
var topLevelVariable = 0;
int get topLevelGetter => 0;
class A {
  static var staticClassVariable = 0;
  static int get staticGetter => 0;
  static String staticClassMethod(int p) => null;
  String instanceClassMethod(int p) => null;
}
var r_topLevelFunction = topLevelFunction;
var r_topLevelVariable = topLevelVariable;
var r_topLevelGetter = topLevelGetter;
var r_staticClassVariable = A.staticClassVariable;
var r_staticGetter = A.staticGetter;
var r_staticClassMethod = A.staticClassMethod;
var instanceOfA = new A();
var r_instanceClassMethod = instanceOfA.instanceClassMethod;
''');
    checkElementText(
        library,
        r'''
class A {
  static int staticClassVariable;
  static int get staticGetter {}
  static String staticClassMethod(int p) {}
  String instanceClassMethod(int p) {}
}
int topLevelVariable;
(int) → String r_topLevelFunction;
int r_topLevelVariable;
int r_topLevelGetter;
int r_staticClassVariable;
int r_staticGetter;
(int) → String r_staticClassMethod;
A instanceOfA;
(int) → String r_instanceClassMethod;
int get topLevelGetter {}
String topLevelFunction(int p) {}
''');
  }

  test_initializer_identifier_formalParameter() async {
    // TODO(scheglov) I don't understand this yet
  }

  @failingTest
  test_initializer_instanceCreation_hasTypeParameter() async {
    var library = await _encodeDecodeLibrary(r'''
class A<T> {}
var a = new A<int>();
var b = new A();
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A<T> {
}
A<int> a;
dynamic b;
''');
  }

  test_initializer_instanceCreation_noTypeParameters() async {
    var library = await _encodeDecodeLibrary(r'''
class A {}
var a = new A();
''');
    checkElementText(
        library,
        r'''
class A {
}
A a;
''');
  }

  test_initializer_is() async {
    var library = await _encodeDecodeLibrary(r'''
var a = 1.2;
var b = a is int;
''');
    checkElementText(
        library,
        r'''
double a;
bool b;
''');
  }

  @failingTest
  test_initializer_literal() async {
    var library = await _encodeDecodeLibrary(r'''
var vNull = null;
var vBoolFalse = false;
var vBoolTrue = true;
var vInt = 1;
var vIntLong = 0x9876543210987654321;
var vDouble = 2.3;
var vString = 'abc';
var vStringConcat = 'aaa' 'bbb';
var vStringInterpolation = 'aaa ${true} ${42} bbb';
var vSymbol = #aaa.bbb.ccc;
''');
    checkElementText(
        library,
        r'''
Null vNull;
bool vBoolFalse;
bool vBoolTrue;
int vInt;
int vIntLong;
double vDouble;
String vString;
String vStringConcat;
String vStringInterpolation;
Symbol vSymbol;
''');
  }

  test_initializer_literal_list_typed() async {
    var library = await _encodeDecodeLibrary(r'''
var vObject = <Object>[1, 2, 3];
var vNum = <num>[1, 2, 3];
var vNumEmpty = <num>[];
var vInt = <int>[1, 2, 3];
''');
    checkElementText(
        library,
        r'''
List<Object> vObject;
List<num> vNum;
List<num> vNumEmpty;
List<int> vInt;
''');
  }

  test_initializer_literal_list_untyped() async {
    var library = await _encodeDecodeLibrary(r'''
var vInt = [1, 2, 3];
var vNum = [1, 2.0];
var vObject = [1, 2.0, '333'];
''');
    checkElementText(
        library,
        r'''
List<int> vInt;
List<num> vNum;
List<Object> vObject;
''');
  }

  @failingTest
  test_initializer_literal_list_untyped_empty() async {
    var library = await _encodeDecodeLibrary(r'''
var vNonConst = [];
var vConst = const [];
''');
    checkElementText(
        library,
        r'''
List<dynamic> vNonConst;
List<Null> vConst;
''');
  }

  test_initializer_literal_map_typed() async {
    var library = await _encodeDecodeLibrary(r'''
var vObjectObject = <Object, Object>{1: 'a'};
var vComparableObject = <Comparable<int>, Object>{1: 'a'};
var vNumString = <num, String>{1: 'a'};
var vNumStringEmpty = <num, String>{};
var vIntString = <int, String>{};
''');
    checkElementText(
        library,
        r'''
Map<Object, Object> vObjectObject;
Map<Comparable<int>, Object> vComparableObject;
Map<num, String> vNumString;
Map<num, String> vNumStringEmpty;
Map<int, String> vIntString;
''');
  }

  test_initializer_literal_map_untyped() async {
    var library = await _encodeDecodeLibrary(r'''
var vIntString = {1: 'a', 2: 'b'};
var vNumString = {1: 'a', 2.0: 'b'};
var vIntObject = {1: 'a', 2: 3.0};
''');
    checkElementText(
        library,
        r'''
Map<int, String> vIntString;
Map<num, String> vNumString;
Map<int, Object> vIntObject;
''');
  }

  @failingTest
  test_initializer_literal_map_untyped_empty() async {
    var library = await _encodeDecodeLibrary(r'''
var vNonConst = {};
var vConst = const {};
''');
    checkElementText(
        library,
        r'''
Map<dynamic, dynamic> vNonConst;
Map<Null, Null> vConst;
''');
  }

  test_initializer_logicalBool() async {
    var library = await _encodeDecodeLibrary(r'''
var a = true;
var b = true;
var vEq = 1 == 2;
var vAnd = a && b;
var vOr = a || b;
''');
    checkElementText(
        library,
        r'''
bool a;
bool b;
bool vEq;
bool vAnd;
bool vOr;
''');
  }

  @failingTest
  test_initializer_methodInvocation_hasTypeParameters() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  List<T> m<T>(int p) => null;
}
var vWithTypeArgument = new A().m<int>();
var vWithoutTypeArgument = new A().m();
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A {
  List<T> m<T>(int p) {}
}
List<int> vWithTypeArgument;
dynamic vWithoutTypeArgument;
''');
  }

  test_initializer_methodInvocation_noTypeParameters() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int p) => null;
}
var instanceOfA = new A();
var v1 = instanceOfA.m();
var v2 = new A().m();
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int p) {}
}
A instanceOfA;
String v1;
String v2;
''');
  }

  test_initializer_multiplicative() async {
    var library = await _encodeDecodeLibrary(r'''
var vModuloIntInt = 1 % 2;
var vModuloIntDouble = 1 % 2.0;
var vMultiplyIntInt = 1 * 2;
var vMultiplyIntDouble = 1 * 2.0;
var vMultiplyDoubleInt = 1.0 * 2;
var vMultiplyDoubleDouble = 1.0 * 2.0;
var vDivideIntInt = 1 / 2;
var vDivideIntDouble = 1 / 2.0;
var vDivideDoubleInt = 1.0 / 2;
var vDivideDoubleDouble = 1.0 / 2.0;
var vFloorDivide = 1 ~/ 2;
''');
    checkElementText(
        library,
        r'''
int vModuloIntInt;
double vModuloIntDouble;
int vMultiplyIntInt;
double vMultiplyIntDouble;
double vMultiplyDoubleInt;
double vMultiplyDoubleDouble;
num vDivideIntInt;
num vDivideIntDouble;
double vDivideDoubleInt;
double vDivideDoubleDouble;
int vFloorDivide;
''');
  }

  test_initializer_parenthesized() async {
    var library = await _encodeDecodeLibrary(r'''
var V = (42);
''');
    checkElementText(
        library,
        r'''
int V;
''');
  }

  @failingTest
  test_initializer_postfix() async {
    var library = await _encodeDecodeLibrary(r'''
var vInt = 1;
var vDouble = 2;
var vIncInt = vInt++;
var vDecInt = vInt--;
var vIncDouble = vDouble++;
var vDecDouble = vDouble--;
''');
    checkElementText(
        library,
        r'''
int vInt;
int vDouble;
int vIncInt;
int vDecInt;
double vIncDouble;
double vDecDouble;
''');
  }

  @failingTest
  test_initializer_prefix_incDec() async {
    var library = await _encodeDecodeLibrary(r'''
var vInt = 1;
var vDouble = 2.0;
var vIncInt = ++vInt;
var vDecInt = --vInt;
var vIncDouble = ++vDouble;
var vDecInt = --vDouble;
''');
    checkElementText(
        library,
        r'''
int vInt;
double vDouble;
int vIncInt;
int vDecInt;
double vIncDouble;
double vDecInt;
''');
  }

  @failingTest
  test_initializer_prefix_incDec_custom() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  B operator+(int v) => null;
}
class B {}
var a = new A();
var vInc = ++a;
var vDec = --a;
''');
    checkElementText(
        library,
        r'''
A a;
B vInc;
B vDec;
''');
  }

  test_initializer_prefix_not() async {
    var library = await _encodeDecodeLibrary(r'''
var vNot = !true;
''');
    checkElementText(
        library,
        r'''
bool vNot;
''');
  }

  test_initializer_prefix_other() async {
    var library = await _encodeDecodeLibrary(r'''
var vNegateInt = -1;
var vNegateDouble = -1.0;
var vComplement = ~1;
''');
    checkElementText(
        library,
        r'''
int vNegateInt;
double vNegateDouble;
int vComplement;
''');
  }

  test_initializer_relational() async {
    var library = await _encodeDecodeLibrary(r'''
var vLess = 1 < 2;
var vLessOrEqual = 1 <= 2;
var vGreater = 1 > 2;
var vGreaterOrEqual = 1 >= 2;
''');
    checkElementText(
        library,
        r'''
bool vLess;
bool vLessOrEqual;
bool vGreater;
bool vGreaterOrEqual;
''');
  }

  @failingTest
  test_initializer_throw() async {
    var library = await _encodeDecodeLibrary(r'''
var V = throw 42;
''');
    checkElementText(
        library,
        r'''
Null V;
''');
  }

  test_method_error_conflict_parameterType_generic() async {
    var library = await _encodeDecodeLibrary(r'''
class A<T> {
  void m(T a) {}
}
class B<E> {
  void m(E a) {}
}
class C extends A<int> implements B<double> {
  m(a) {}
}
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A<T> {
  void m(T a) {}
}
class B<E> {
  void m(E a) {}
}
class C extends A<int> implements B<double> {
  void m(dynamic a) {}
}
''');
  }

  test_method_error_conflict_parameterType_notGeneric() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  void m(int a) {}
}
class B {
  void m(String a) {}
}
class C extends A implements B {
  m(a) {}
}
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A {
  void m(int a) {}
}
class B {
  void m(String a) {}
}
class C extends A implements B {
  void m(dynamic a) {}
}
''');
  }

  test_method_error_conflict_returnType_generic() async {
    var library = await _encodeDecodeLibrary(r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> {
  T m(int a) {}
}
class C extends A<int, String> implements B<double> {
  m(a) {}
}
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> {
  T m(int a) {}
}
class C extends A<int, String> implements B<double> {
  dynamic m(int a) {}
}
''');
  }

  test_method_error_conflict_returnType_notGeneric() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  int m() {}
}
class B {
  String m() {}
}
class C extends A implements B {
  m() {}
}
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A {
  int m() {}
}
class B {
  String m() {}
}
class C extends A implements B {
  dynamic m() {}
}
''');
  }

  test_method_error_hasMethod_noParameter_required() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  void m(int a) {}
}
class B extends A {
  m(a, b) {}
}
''');
    // TODO(scheglov) test for inference failure error
    checkElementText(
        library,
        r'''
class A {
  void m(int a) {}
}
class B extends A {
  void m(int a, dynamic b) {}
}
''');
  }

  test_method_missing_hasMethod_noParameter_named() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  void m(int a) {}
}
class B extends A {
  m(a, {b}) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  void m(int a) {}
}
class B extends A {
  void m(int a, {dynamic b}) {}
}
''');
  }

  test_method_missing_hasMethod_noParameter_optional() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  void m(int a) {}
}
class B extends A {
  m(a, [b]) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  void m(int a) {}
}
class B extends A {
  void m(int a, [dynamic b]) {}
}
''');
  }

  test_method_missing_hasMethod_withoutTypes() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  m(a) {}
}
class B extends A {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  dynamic m(dynamic a) {}
}
class B extends A {
  dynamic m(dynamic a) {}
}
''');
  }

  test_method_missing_noMember() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  int foo(String a) => null;
}
class B extends A {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  int foo(String a) {}
}
class B extends A {
  dynamic m(dynamic a) {}
}
''');
  }

  test_method_missing_notMethod() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  int m = 42;
}
class B extends A {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  int m;
}
class B extends A {
  dynamic m(dynamic a) {}
}
''');
  }

  test_method_OK_sequence_extendsExtends_generic() async {
    var library = await _encodeDecodeLibrary(r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> extends A<int, T> {}
class C extends B<String> {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> extends A<int, T> {
}
class C extends B<String> {
  String m(int a) {}
}
''');
  }

  test_method_OK_sequence_inferMiddle_extendsExtends() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a) {}
}
class B extends A {
  m(a) {}
}
class C extends B {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a) {}
}
class B extends A {
  String m(int a) {}
}
class C extends B {
  String m(int a) {}
}
''');
  }

  test_method_OK_sequence_inferMiddle_extendsImplements() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a) {}
}
class B implements A {
  m(a) {}
}
class C extends B {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a) {}
}
class B implements A {
  String m(int a) {}
}
class C extends B {
  String m(int a) {}
}
''');
  }

  test_method_OK_sequence_inferMiddle_extendsWith() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a) {}
}
class B extends Object with A {
  m(a) {}
}
class C extends B {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a) {}
}
class B extends Object with A {
  synthetic B();
  String m(int a) {}
}
class C extends B {
  String m(int a) {}
}
''');
  }

  test_method_OK_single_extends_direct_generic() async {
    var library = await _encodeDecodeLibrary(r'''
class A<K, V> {
  V m(K a, double b) {}
}
class B extends A<int, String> {
  m(a, b) {}
}
''');
    checkElementText(
        library,
        r'''
class A<K, V> {
  V m(K a, double b) {}
}
class B extends A<int, String> {
  String m(int a, double b) {}
}
''');
  }

  test_method_OK_single_extends_direct_notGeneric() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a) {}
}
class B extends A {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a) {}
}
class B extends A {
  String m(int a) {}
}
''');
  }

  test_method_OK_single_extends_direct_notGeneric_named() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a, {double b}) {}
}
class B extends A {
  m(a, {b}) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a, {double b}) {}
}
class B extends A {
  String m(int a, {double b}) {}
}
''');
  }

  test_method_OK_single_extends_direct_notGeneric_positional() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a, [double b]) {}
}
class B extends A {
  m(a, [b]) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a, [double b]) {}
}
class B extends A {
  String m(int a, [double b]) {}
}
''');
  }

  test_method_OK_single_extends_indirect_generic() async {
    var library = await _encodeDecodeLibrary(r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> extends A<int, T> {}
class C extends B<String> {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> extends A<int, T> {
}
class C extends B<String> {
  String m(int a) {}
}
''');
  }

  test_method_OK_single_implements_direct_generic() async {
    var library = await _encodeDecodeLibrary(r'''
abstract class A<K, V> {
  V m(K a);
}
class B implements A<int, String> {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
abstract class A<K, V> {
  V m(K a);
}
class B implements A<int, String> {
  String m(int a) {}
}
''');
  }

  test_method_OK_single_implements_direct_notGeneric() async {
    var library = await _encodeDecodeLibrary(r'''
abstract class A {
  String m(int a);
}
class B implements A {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
abstract class A {
  String m(int a);
}
class B implements A {
  String m(int a) {}
}
''');
  }

  test_method_OK_single_implements_indirect_generic() async {
    var library = await _encodeDecodeLibrary(r'''
abstract class A<K, V> {
  V m(K a);
}
abstract class B<T1, T2> extends A<T2, T1> {}
class C implements B<int, String> {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
abstract class A<K, V> {
  V m(K a);
}
abstract class B<T1, T2> extends A<T2, T1> {
}
class C implements B<int, String> {
  int m(String a) {}
}
''');
  }

  test_method_OK_single_withExtends_notGeneric() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a) {}
}
class B extends Object with A {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a) {}
}
class B extends Object with A {
  synthetic B();
  String m(int a) {}
}
''');
  }

  test_method_OK_two_extendsImplements_generic() async {
    var library = await _encodeDecodeLibrary(r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> {
  T m(int a) {}
}
class C extends A<int, String> implements B<String> {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A<K, V> {
  V m(K a) {}
}
class B<T> {
  T m(int a) {}
}
class C extends A<int, String> implements B<String> {
  String m(int a) {}
}
''');
  }

  test_method_OK_two_extendsImplements_notGeneric() async {
    var library = await _encodeDecodeLibrary(r'''
class A {
  String m(int a) {}
}
class B {
  String m(int a) {}
}
class C extends A implements B {
  m(a) {}
}
''');
    checkElementText(
        library,
        r'''
class A {
  String m(int a) {}
}
class B {
  String m(int a) {}
}
class C extends A implements B {
  String m(int a) {}
}
''');
  }

  Future<LibraryElement> _encodeDecodeLibrary(String text) async {
    String path = _p('/test.dart');
    provider.newFile(path, text);
    UnitElementResult result = await driver.getUnitElement(path);
    return result.element.library;
  }

  String _p(String path) => provider.convertPath(path);
}
