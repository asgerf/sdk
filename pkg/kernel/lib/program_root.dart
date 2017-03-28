// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.program_root;

import 'ast.dart';
import 'library_index.dart';

enum ProgramRootKind {
  /// The root is a class which will be instantiated by
  /// external / non-Dart code.
  ExternallyInstantiatedClass,

  /// The root is a setter function or a field.
  Setter,

  /// The root is a getter function or a field.
  Getter,

  /// The root is some kind of constructor.
  Constructor,

  /// The root is a field, normal procedure or constructor.
  Other,
}

/// A program root which the vm or embedder uses and needs to be retained.
class ProgramRoot {
  /// The library the root is contained in.
  final String library;

  /// The name of the class inside the library (optional).
  final String klass;

  /// The name of the member inside the library (or class, optional).
  final String member;

  /// The kind of this program root.
  final ProgramRootKind kind;

  ProgramRoot(this.library, this.klass, this.member, this.kind);

  String toString() => "ProgramRoot($library, $klass, $member, $kind)";

  String get disambiguatedName {
    if (kind == ProgramRootKind.Getter) return 'get:$member';
    if (kind == ProgramRootKind.Setter) return 'set:$member';
    return member;
  }

  Member getMember(LibraryIndex table) {
    assert(member != null);
    return table.tryGetMember(
            library, klass ?? LibraryIndex.topLevel, disambiguatedName) ??
        table.tryGetMember(library, klass ?? LibraryIndex.topLevel, member);
  }

  Class getClass(LibraryIndex table) {
    assert(klass != null);
    return table.tryGetClass(library, klass);
  }
}

void markEntryPoints(Program program, List<ProgramRoot> roots) {
  var index = new LibraryIndex(program, roots.map((r) => r.library));
  for (var root in roots) {
    if (root.member == null) continue;
    root.getMember(index)?.isEntryPoint = true;
  }
}
