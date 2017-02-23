// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.indexer;

import 'ast.dart';
import 'transformations/treeshaker.dart';

/// Provides name-based access to library, class, and member AST nodes.
class LookupTable {
  /// A name that can be used as a class name to access the top-level members
  /// of a library.
  static const String topLevel = '::';

  final Map<String, _LibraryIndex> _libraries = <String, _LibraryIndex>{};

  /// Indexes the libraries with the URIs given in [libraryUris].
  LookupTable(Program program, Iterable<String> libraryUris) {
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
  LookupTable.byUri(Program program, Iterable<Uri> libraryUris)
      : this(program, libraryUris.map((uri) => '$uri'));

  /// Indexes the libraries with the URIs given in [libraryUris].
  LookupTable.coreLibraries(Program program) {
    for (var library in program.libraries) {
      if (library.importUri.scheme == 'dart') {
        _libraries['${library.importUri}'] = new _LibraryIndex()
          ..build(library);
      }
    }
  }

  /// Indexes the entire program.
  ///
  /// Consider using another constructor to only index the libraries that
  /// are needed.
  LookupTable.all(Program program) {
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
    classes[LookupTable.topLevel] = new _ClassIndex.topLevel(this);
    for (var class_ in library.classes) {
      classes[class_.name] = new _ClassIndex(this, class_);
    }
  }

  String get containerName {
    // It can be helpful to indicate if the library is external, since then
    // the class might be in the library, but just not seen from this build
    // unit.
    return library.isExternal
        ? "external library '${library.importUri}'"
        : "library '${library.importUri}'";
  }

  _ClassIndex _getClassIndex(String name) {
    var indexer = classes[name];
    if (indexer == null) {
      throw "Class '$name' not found in $containerName";
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
  final _LibraryIndex parent;
  final Class class_; // Null for top-level.
  final Map<Name, Member> members = <Name, Member>{};

  Library get library => parent.library;

  _ClassIndex(this.parent, this.class_) {
    class_.procedures.forEach(addMember);
    class_.fields.forEach(addMember);
    class_.constructors.forEach(addMember);
  }

  _ClassIndex.topLevel(this.parent) : class_ = null {
    library.procedures.forEach(addMember);
    library.fields.forEach(addMember);
  }

  void addMember(Member member) {
    members[member.disambiguatedName] = member;
  }

  String get containerName {
    if (class_ == null) {
      return "top-level of ${parent.containerName}";
    } else {
      return "class '${class_.name}' in ${parent.containerName}";
    }
  }

  Member getMember(Name name) {
    var member = members[name];
    if (member == null) {
      throw "A member with disambiguated name '$name' was not found "
          "in $containerName";
    }
    return member;
  }
}
