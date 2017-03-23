// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore: unused_local_variable
library micro_types;

class Foo {}

class Subclass extends Foo {}

class Subtype implements Foo {}

main(List<String> args) {
  testBasic(args.length);
  testListMutation();
  testUpcasting();
  testUpcastAndAddNull();
  testBox();
  testInitializers();
  testArithmetic();
  testGenericDowncast();
  testGenericDynamic();
  testCurry();
  testCallbackEscapeDynamic();
  testGenericCasts();
  testEscapeNonGeneric();
  testCombinators();
}

void takeExact(Foo foo) => takeExact2(foo);
void takeSubclass(Foo foo) => takeSubclass2(foo);
void takeSubtype(Foo foo) => takeSubtype2(foo);
void takeNullable(Foo foo) => takeNullable2(foo);

void takeExact2(Foo foo) {}
void takeSubclass2(Foo foo) {}
void takeSubtype2(Foo foo) {}
void takeNullable2(Foo foo) {}

void testBasic(int n) {
  Foo nullableFoo = null;
  takeExact(new Foo());
  takeSubclass(new Subclass());
  takeSubtype(new Subtype());
  Foo t = new Foo();
  t = n == 0 ? t : null;
  takeNullable(t);
}

void testListMutation() {
  List<String> nonNullable = [];
  nonNullable.add("dfg");
  String fromNonNullable = nonNullable[0];

  List<String> nullable = [];
  nullable.add("dfg");
  nullable.add(null);
  String fromNullable = nullable[1];

  List<Foo> exactList = [];
  exactList.add(new Foo());
  joinSubclassList(exactList);

  List<Foo> subclassList = [];
  subclassList.add(new Subclass());
  joinSubclassList(subclassList);

  List<Foo> subtypeList = [];
  subtypeList.add(new Subtype());
}

void joinSubclassList(List<Foo> list) {}

void testUpcasting() {
  List<Subclass> subclassList = [];
  List<Foo> upcastedSubclassList = subclassList;
}

void testUpcastAndAddNull() {
  List<Subclass> list = [];
  List<Foo> upcastedList = list;
  upcastedList.add(null);
}

void testBox() {
  {
    Box<int> box = new Box<int>(5);
    int nullableInt1 = box.getNull();
    int nullableInt2 = box.getThis().getNull();
    int nonNullableInt1 = box.field;
    int nonNullableInt2 = box.getThis().field;
  }

  {
    Box<int> boxWithNull = new Box<int>(null);
    int alwaysNull1 = boxWithNull.getNull();
    int alwaysNull2 = boxWithNull.field;
    int alwaysNull3 = boxWithNull.getThis().getNull();
    int alwaysNull4 = boxWithNull.getThis().field;
  }

  {
    Box<int> boxWithMaybeNull = new Box<int>(5 ?? null);
    int nullableInt1 = boxWithMaybeNull.getNull();
    int nullableInt2 = boxWithMaybeNull.field;
    int nullableInt3 = boxWithMaybeNull.getThis().getNull();
    int nullableInt4 = boxWithMaybeNull.getThis().field;
  }
}

class Box<T> {
  final T field;

  Box(this.field);

  T getNull() => null;
  Box<T> getThis() => this;
}

testInitializers() {
  new NullField(null);
  new ExactField(new Foo());
  new SubclassField(new Subclass());
  new SubtypeField(new Subtype());
  new DefaultValueField();
}

class NullField {
  Foo field;
  NullField(this.field);
}

class ExactField {
  Foo field;
  ExactField.actual(this.field);
  ExactField(Foo field) : this.actual(field);
}

class SubclassField {
  Foo field;
  SubclassField(this.field);
}

class SubtypeField {
  Foo field;
  SubtypeField(this.field);
}

class DefaultValueField {
  Foo field;
  DefaultValueField.inner();
  DefaultValueField() : this.inner();
}

void testArithmetic() {
  int x = 4;
  int y = 7;
  int add = x + y;
  int subtract = x - y;
  int multiply = x * y;

  num nx = 4.5;
  num ny = 7;
  num n1 = nx + ny;
  num n2 = x + ny;
  num n3 = nx + y;

  double dx = 4.0;
  double dy = 7.0;
  double d1 = dx + dy;
  double d2 = x + dy;
  double d3 = dx + y;
  double d4 = nx + dy;
  double d5 = dx + ny;
}

void testCallbacks() {
  exactCallback((foo) {});
  subclassCallback((foo) {});
  subtypeCallback((foo) {});
  nullableCallback((foo) {});
}

typedef Callback(Foo foo);

exactCallback(Callback callback) => callback(new Foo());
subclassCallback(Callback callback) => callback(new Subclass());
subtypeCallback(Callback callback) => callback(new Subtype());
nullableCallback(Callback callback) => callback(null);

class NullableArgOnThis<T> {
  T field;

  NullableArgOnThis(this.field);

  void nullableArg(T arg) {
    field = arg;
  }

  void defaultNullable([T arg]) {}
  void defaultNullable2([T arg = null]) {}

  void doSomething() {
    nullableArg(null);
  }
}

class NullableArgOnThis2<T> {
  T field;

  NullableArgOnThis2(this.field);

  void nullableArg(T arg) {
    field = arg;
  }

  void doSomething() {
    getThis().nullableArg(null);
  }

  NullableArgOnThis2<T> getThis() => this;
}

void testNullableArgOnThis() {
  var first = new NullableArgOnThis<int>(5);
  first.doSomething();
  int nullableFirst = first.field;
  var second = new NullableArgOnThis2<int>(5);
  second.doSomething();
  int nullableSecond = second.field;
}

void testOverride() {
  new OverrideSub().takeNullInSubclass(null);
  new OverrideBase().takeNullInBase(null);
  var xs = new OverrideBase().returnNullFromBase();
  var ys = new OverrideBase().returnNullFromSubclass();
  var zs = new OverrideSub().returnNullFromBase();
  var ws = new OverrideSub().returnNullFromSubclass();
}

class OverrideBase {
  void takeNullInSubclass(Object o) {}
  void takeNullInBase(Object o) {}
  Object returnNullFromBase() => null;
  Object returnNullFromSubclass() => new Object();

  void generic/*<T>*/(dynamic/*=T*/ arg) {}
}

class OverrideSub extends OverrideBase {
  void takeNullInSubclass(Object o) {}
  void takeNullInBase(Object o) {}
  Object returnNullFromBase() => new Object();
  Object returnNullFromSubclass() => null;

  void generic/*<T>*/(dynamic/*=T*/ arg) {}
}

typedef To FnCallback<From, To>(From from);

class GenericBase<E> {
  E value;
  dynamic/*=T*/ map/*<T>*/(dynamic/*=T*/ callback(E arg)) {
    return callback(value);
  }
}

class GenericSubclass<E> extends GenericBase<E> {
  dynamic/*=T*/ map/*<T>*/(dynamic/*=T*/ callback(E arg)) {
    return callback(value);
  }
}

class MutableBox<T> {
  T field;
  MutableBox(this.field);
}

void testGenericDowncast() {
  var box = new MutableBox<int>(5);
  Object upcastBox = box;
  MutableBox<int> downcastBox = upcastBox as MutableBox<int>;
  downcastBox.field = null;
  int nullableIntFromBox = box.field;

  var list = <int>[5];
  Object upcastList = list;
  List<int> downcastList = upcastList as List<int>;
  downcastList.add(null);
  int nullableIntFromList = list.last;

  var kmap = <int, int>{5: 6};
  Object upcastKMap = kmap;
  Map<int, int> downcastKMap = upcastKMap as Map<int, int>;
  downcastKMap[null] = 3;
  int nullableIntFromKMap = kmap.keys.first;

  var vmap = <int, int>{5: 6};
  Object upcastVMap = vmap;
  Map<int, int> downcastVMap = upcastVMap as Map<int, int>;
  downcastVMap[5] = null;
  int nullableIntFromVMap = vmap[5];
}

void testGenericDynamic() {
  var box = new MutableBox<int>(5);
  dynamic dynamicBox = box;
  dynamicBox.field = null;
  int nullableIntFromBox = box.field;

  var list = <int>[5];
  dynamic dynamicList = list;
  dynamicList.add(null);
  int nullableIntFromList = list.last;

  var kmap = <int, int>{5: 6};
  dynamic dynamicKMap = kmap;
  dynamicKMap[null] = 3;
  int nullableIntFromKMap = kmap.keys.first;

  var vmap = <int, int>{5: 6};
  dynamic dynamicVMap = vmap;
  dynamicVMap[5] = null;
  int nullableIntFromVMap = vmap[5];
}

typedef void TakeIntFunction(int x);

void testCurry() {
  void takeInt(int x) {}
  takeInt(5);

  var closure = (int x) {};
  closure(5);

  TakeIntFunction curryNonNullable() => (int x) {};
  curryNonNullable()(5);

  TakeIntFunction curryNullable() => (int x) {};
  curryNullable()(5);
  curryNullable()(null);
}

void testCallbackEscapeDynamic() {
  void takeNullable(int x) {}
  dynamic dynamicTakeNullable = takeNullable;
  dynamicTakeNullable(5);
  dynamicTakeNullable(null);

  TakeIntFunction curryNullable() => (int x) {};
  dynamic dynamicCurryNullable = curryNullable;
  dynamicCurryNullable()(5);
  dynamicCurryNullable()(null);
}

class Generic<T> {
  final T field;

  Generic(this.field);

  Object nullableReturnFromT(T x) {
    return x;
  }
}

void testGenericCasts() {
  Generic<int> generic = new Generic<int>(null);
  Object nullableReturn = generic.nullableReturnFromT(null);
  Object nullableField = generic.field;
}

class Escaping {
  static void escape(dynamic x) {
    x.escapingField = null;
    x.escapingMethod(null);
    x.escapingIdentity(null);
  }

  static int globalVar = 0;
  int escapingField = 0;
  int dependentField = 0;

  void escapingMethod(int x) {
    globalVar = x;
    dependentField = escapingField;
  }

  int escapingIdentity(int x) => x;
  int identity(int x) => x;
}

class EscapingThis {
  static void escape(dynamic obj) {
    obj.escapingField2 = null;
  }

  int escapingField2 = 5;

  void escapeThis() {
    escape(this);
  }
}

class EscapingBaseClass {
  int escapingField3 = 7;
}

class EscapingSubclass extends EscapingBaseClass {
  static void escape(dynamic x) {
    x.escapingField3 = null;
  }
}

void testEscapeNonGeneric() {
  var escaped = new Escaping();
  Escaping.escape(escaped);
  int nullableInt1 = escaped.escapingField;
  int nullableInt2 = Escaping.globalVar;
  int nonNullableInt3 = escaped.escapingIdentity(3);
  int nullableInt4 = escaped.dependentField;

  var nonEscaped = new Escaping();
  nonEscaped.escapingMethod(5);
  int nonNullableInt5 = nonEscaped.escapingField;
  int nonNullableInt6 = nonEscaped.escapingIdentity(5);
  int nonNullableInt7 = nonEscaped.identity(6);
  int nonNullableInt8 = escaped.dependentField;

  var escapedThis = new EscapingThis();
  escapedThis.escapeThis();
  int nullableInt9 = escapedThis.escapingField2;

  var nonEscapedThis = new EscapingThis();
  int nonNullableInt10 = nonEscapedThis.escapingField2;

  var escapedSubclass = new EscapingSubclass();
  EscapingSubclass.escape(escapedSubclass);
  int nullableInt11 = escapedSubclass.escapingField3;

  var nonEscapedSubclass = new EscapingSubclass();
  int nonNullableInt12 = nonEscapedSubclass.escapingField3;
}

void testCombinators() {
  var nonNullable = ['foo', 'bar', 'baz'];
  nonNullable.forEach((x) {
    print(x);
  });
  var nonNullableMapped = nonNullable.map((x) => x).first;

  var nullable = ['foo', 'bar', null, 'baz'];
  nullable.forEach((x) {
    print(x);
  });
  var nullableMapped = nullable.map((x) => x).first;
}
