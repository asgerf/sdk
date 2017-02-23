// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.indexer;

import 'ast.dart';
import 'transformations/treeshaker.dart';

/// Provides name-based access to library, class, and member AST nodes.
class Indexer {
  /// A name that can be used as a class name to access the top-level members
  /// of a library.
  static const String topLevel = '::';

  final Map<String, _LibraryIndex> _libraries = <String, _LibraryIndex>{};

  /// Indexes the libraries with the URIs given in [libraryUris].
  Indexer(Program program, Iterable<String> libraryUris) {
    for (var uri in libraryUris) {
      _libraries[uri] = new _LibraryIndex();
    }
    for (var library in program.libraries) {
      var index = _libraries['${library.importUri}'];
      if (index != null) {
        index.build(library);
      }
    }
  }

  /// Indexes the libraries with the URIs given in [libraryUris].
  Indexer.byUri(Program program, Iterable<Uri> libraryUris)
      : this(program, libraryUris.map((uri) => '$uri'));

  /// Indexes the entire program.
  ///
  /// Consider using another constructor to only index the libraries that
  /// are needed.
  Indexer.all(Program program) {
    for (var library in program.libraries) {
      _libraries['${library.importUri}'] = new _LibraryIndex()..build(library);
    }
  }

  _LibraryIndex _getLibraryIndex(String uri) {
    _LibraryIndex libraryIndex = _libraries[uri];
    if (libraryIndex == null) {
      throw "The library '$uri' has not been indexed";
    }
    return libraryIndex;
  }

  Library getLibrary(String uri) => _getLibraryIndex(uri).library;

  Class getClass(String library, String className) {
    return _getLibraryIndex(library).getClass(className);
  }

  Member getTopLevelMember(String library, String memberName) {
    return getMember(library, topLevel, memberName);
  }

  Member getMember(String library, String className, String memberName) {
    if (memberName.startsWith('_')) {
      var libraryIndex = _getLibraryIndex(library);
      var name = new Name(memberName, libraryIndex.library);
      return libraryIndex.getMember(className, name);
    } else {
      return getMemberQualified(library, className, new Name(memberName));
    }
  }

  Member getMemberQualified(String library, String className, Name memberName) {
    return _getLibraryIndex(library).getMember(className, memberName);
  }

  Member getMemberFromProgramRoot(ProgramRoot root) {
    assert(root.klass != null);
    assert(root.member != null);
    return getMember(
        root.library, root.klass ?? topLevel, root.disambiguatedMember);
  }

  Class getClassFromProgramRoot(ProgramRoot root) {
    assert(root.klass != null);
    return getClass(root.library, root.klass);
  }
}

class _LibraryIndex {
  Library library;
  final Map<String, _ClassIndex> classes = <String, _ClassIndex>{};

  void build(Library library) {
    this.library = library;
    classes[Indexer.topLevel] = new _ClassIndex.topLevel(library);
    for (var class_ in library.classes) {
      classes[class_.name] = new _ClassIndex(class_);
    }
  }

  _ClassIndex _getClassIndex(String name) {
    var indexer = classes[name];
    if (indexer == null) {
      // It can be helpful to indicate if the library is external, since then
      // the class might be in the library, but just not seen from this build
      // unit.
      String libraryName = library.isExternal
          ? "external library '${library.importUri}'"
          : "library '${library.importUri}'";
      throw "Class '$name' not found in $libraryName";
    }
    return indexer;
  }

  Class getClass(String name) {
    return _getClassIndex(name).class_;
  }

  Member getMember(String className, Name memberName) {
    return _getClassIndex(className).getMember(memberName);
  }
}

class _ClassIndex {
  final Class class_; // Null for top-level.
  final Map<Name, Member> members = <Name, Member>{};

  _ClassIndex(this.class_) {
    class_.procedures.forEach(addMember);
    class_.fields.forEach(addMember);
    class_.constructors.forEach(addMember);
  }

  _ClassIndex.topLevel(Library library) : class_ = null {
    library.procedures.forEach(addMember);
    library.fields.forEach(addMember);
  }

  void addMember(Member member) {
    members[member.disambiguatedName] = member;
  }

  Member getMember(Name name) {
    return members[name];
  }
}
