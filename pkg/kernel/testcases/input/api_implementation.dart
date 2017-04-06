// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class Fruit {}

abstract class Banana extends Fruit {}

abstract class Apple extends Fruit {}

abstract class FruitImpl implements Fruit {}

class BananaImpl extends FruitImpl implements Banana {}

class AppleImpl extends FruitImpl implements Apple {}

main() {
  // Can the analysis infer that the banana is always a BananaImpl and
  // the apple is always an AppleImpl?
  takeFruit(Fruit fruit) {}
  takeBanana(Banana banana) {}
  takeApple(Apple apple) {}
  takeDynamicAndDowncast(dynamic x) {
    if (x is Fruit) {
      Fruit _ = x;
    }
    if (x is Banana) {
      Banana _ = x;
    }
    if (x is Apple) {
      Apple _ = x;
    }
  }

  dynamicCall(takeFruit, "banana");
  dynamicCall(takeFruit, "apple");
  dynamicCall(takeBanana, "banana");
  dynamicCall(takeApple, "apple");
  dynamicCall(takeDynamicAndDowncast, "banana");
  dynamicCall(takeDynamicAndDowncast, "apple");
}

void dynamicCall(dynamic f, String kind) {
  f(kind == "banana" ? new BananaImpl() : new AppleImpl());
}
