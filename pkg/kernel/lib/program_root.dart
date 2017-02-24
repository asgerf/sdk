library kernel.program_root;

import 'library_index.dart';
import 'package:kernel/ast.dart';

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
        table.getMember(library, klass ?? LibraryIndex.topLevel, member);
  }

  Class getClass(LibraryIndex table) {
    assert(klass != null);
    return table.getClass(library, klass);
  }
}
