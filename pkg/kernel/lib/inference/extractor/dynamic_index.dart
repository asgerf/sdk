// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.inference.extractor.dynamic_index;

import 'package:kernel/ast.dart';

class DynamicIndex {
  final Map<Name, List<Member>> getters = <Name, List<Member>>{};
  final Map<Name, List<Member>> setters = <Name, List<Member>>{};

  DynamicIndex(Program program) {
    for (var library in program.libraries) {
      for (var classNode in library.classes) {
        for (var procedure in classNode.procedures) {
          if (procedure.isStatic ||
              procedure.isAbstract ||
              !procedure.name.isPrivate) {
            continue;
          }
          var map = procedure.isSetter ? setters : getters;
          var list = map[procedure.name] ??= <Member>[];
          list.add(procedure);
        }
        for (var field in classNode.fields) {
          if (field.isStatic || !field.name.isPrivate) continue;
          var list = getters[field.name] ??= <Member>[];
          list.add(field);
          if (!field.isFinal) {
            list = setters[field.name] ??= <Member>[];
            list.add(field);
          }
        }
      }
    }
  }

  List<Member> getGetters(Name name) {
    return getters[name] ?? const <Member>[];
  }

  List<Member> getSetters(Name name) {
    return setters[name] ?? const <Member>[];
  }
}
