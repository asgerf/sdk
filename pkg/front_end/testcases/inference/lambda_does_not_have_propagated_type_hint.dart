// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*@testedFeatures=inference*/
library test;

List<String> getListOfString() => const <String>[];

void foo() {
  List myList = getListOfString();
  /*@promotedType=none*/ myList
      .map(/*@returnType=int*/ (/*@type=dynamic*/ type) => 42);
}

void bar() {
  var /*@type=dynamic*/ list;
  try {
    list = <String>[];
  } catch (/*@promotedType=none*/ _) {
    return;
  }
  /*info:DYNAMIC_INVOKE*/ /*@promotedType=none*/ list
      .map(/*@returnType=String*/ (/*@type=dynamic*/ value) => '$value');
}
