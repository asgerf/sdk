// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.dynamic_index;

import 'package:kernel/ast.dart';

/// An index of all members with a private name.
///
/// This is used for resolving dynamic calls with private names during
/// constraint generation.
class DynamicIndex {
  final Map<Name, List<Member>> _getters = <Name, List<Member>>{};
  final Map<Name, List<Member>> _setters = <Name, List<Member>>{};

  DynamicIndex(Program program) {
    for (var library in program.libraries) {
      for (var classNode in library.classes) {
        for (var procedure in classNode.procedures) {
          if (procedure.isStatic ||
              procedure.isAbstract ||
              !procedure.name.isPrivate) {
            continue;
          }
          var map = procedure.isSetter ? _setters : _getters;
          var list = map[procedure.name] ??= <Member>[];
          list.add(procedure);
        }
        for (var field in classNode.fields) {
          if (field.isStatic || !field.name.isPrivate) continue;
          var list = _getters[field.name] ??= <Member>[];
          list.add(field);
          if (!field.isFinal) {
            list = _setters[field.name] ??= <Member>[];
            list.add(field);
          }
        }
      }
    }
  }

  List<Member> getGetters(Name name) {
    return _getters[name] ?? const <Member>[];
  }

  List<Member> getSetters(Name name) {
    return _setters[name] ?? const <Member>[];
  }
}
