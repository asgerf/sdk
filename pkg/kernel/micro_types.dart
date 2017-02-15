// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
  testDowncast();
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
  Box<int> box = new Box<int>(5);
  int nullableInt = box.getNull();
  int nonNullableInt = box.field;

  Box<int> boxWithNull = new Box<int>(null);
  int alwaysNull1 = boxWithNull.getNull();
  int alwaysNull2 = boxWithNull.field;

  Box<int> boxWithMaybeNull = new Box<int>(5 ?? null);
  int nullableInt2 = boxWithMaybeNull.getNull();
  int nullableInt3 = boxWithMaybeNull.field;
}

class Box<T> {
  final T field;

  Box(this.field);

  T getNull() => null;
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

void testDowncast() {
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
