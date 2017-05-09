// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*@testedFeatures=inference*/
library test;

import 'dart:async';

main() {
  Future<int> base;
  var /*@type=Future<bool>*/ f = /*@promotedType=none*/ base
      .then(/*@returnType=bool*/ (/*@type=int*/ x) {
    return x == 0;
  });
  var /*@type=Future<bool>*/ g = /*@promotedType=none*/ base
      .then(/*@returnType=bool*/ (/*@type=int*/ x) => x == 0);
  Future<bool> b = /*@promotedType=none*/ f;
  b = /*@promotedType=none*/ g;
}
