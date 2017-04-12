library kernel.util.class_set;

import 'dart:typed_data';

import '../ast.dart';
import 'interval_list.dart';

import 'package:kernel/class_hierarchy.dart';

abstract class ClassSetDomain {
  Class get rootClass;

  ClassSet getSingleton(Class class_) {
    int index = getClassIndex(class_);
    return new ClassSet(
        this,
        new Uint32List(2)
          ..[0] = index
          ..[1] = index + 1);
  }

  ClassSet getSubtypesOf(Class class_);
  ClassSet getSubclassesOf(Class class_);

  /// Returns -1 if the class is not in the domain.
  int getClassIndex(Class class_);

  Class getClassFromIndex(int index);
}

/// An immutable set of classes, internally represented as an interval list.
class ClassSet {
  final ClassSetDomain domain;
  final Uint32List intervalList;

  ClassSet(this.domain, this.intervalList);

  bool get isEmpty => intervalList.isEmpty;

  bool get isSingleton {
    var list = intervalList;
    return list.length == 2 && list[0] + 1 == list[1];
  }

  bool contains(Class class_) {
    return intervalListContains(intervalList, domain.getClassIndex(class_));
  }

  bool containsAll(ClassSet other) {
    var joined = union(other);
    return listEquals(intervalList, joined.intervalList);
  }

  ClassSet union(ClassSet other) {
    assert(domain == other.domain);
    if (identical(intervalList, other.intervalList)) return this;
    IntervalListBuilder builder = new IntervalListBuilder();
    builder.addIntervalList(intervalList);
    builder.addIntervalList(other.intervalList);
    return new ClassSet(domain, builder.buildIntervalList());
  }

  ClassSet intersection(ClassSet other) {
    assert(domain == other.domain);
    if (identical(intervalList, other.intervalList)) return this;
    IntervalListBuilder builder = new IntervalListBuilder();
    builder.addIntervalList(intervalList);
    builder.addIntervalList(other.intervalList);
    return new ClassSet(domain, builder.buildIntervalList(2));
  }

  Class getCommonBaseClass() {
    var list = intervalList;
    if (list.isEmpty) return null;
    var domain = this.domain;
    Class candidate = domain.getClassFromIndex(list[0]);
    while (candidate != domain.rootClass) {
      if (domain.getSubclassesOf(candidate).containsAll(this)) {
        return candidate;
      }
      candidate = candidate.superclass;
    }
    return domain.rootClass;
  }

  void forEach(void callback(Class class_)) {
    for (int i = 0; i < intervalList.length; i += 2) {
      int begin = intervalList[i];
      int end = intervalList[i + 1];
      for (int j = begin; j < end; ++j) {
        callback(domain.getClassFromIndex(j));
      }
    }
  }
}

class _ClassInfo {
  final int index;
  final Uint32List subclasses;
  final Uint32List subtypes;

  _ClassInfo(this.index, this.subclasses, this.subtypes);
}

class FilteredClassSetDomain extends ClassSetDomain {
  final Map<Class, _ClassInfo> _infoFor = <Class, _ClassInfo>{};
  final List<Class> _classes = <Class>[];
  final Class rootClass;

  FilteredClassSetDomain(ClassHierarchy hierarchy, bool predicate(Class class_))
      : rootClass = hierarchy.rootClass {
    _ClassInfo visit(Class class_) {
      var info = _infoFor[class_];
      if (info != null) return info;
      var subtypes = new IntervalListBuilder();
      var subclasses = new IntervalListBuilder();
      int index = -1;
      if (predicate(class_)) {
        index = _classes.length;
        _classes.add(class_);
        subclasses.addSingleton(index);
        subtypes.addSingleton(index);
      }
      for (var subclass in hierarchy.getDirectExtendersOf(class_)) {
        var subinfo = visit(subclass);
        subclasses.addIntervalList(subinfo.subclasses);
        subtypes.addIntervalList(subinfo.subtypes);
      }
      for (var subclass in hierarchy.getDirectMixersOf(class_)) {
        var subinfo = visit(subclass);
        subtypes.addIntervalList(subinfo.subtypes);
      }
      for (var subclass in hierarchy.getDirectImplementersOf(class_)) {
        var subinfo = visit(subclass);
        subtypes.addIntervalList(subinfo.subtypes);
      }
      return _infoFor[class_] = new _ClassInfo(
          index, subclasses.buildIntervalList(), subtypes.buildIntervalList());
    }

    visit(hierarchy.rootClass);
  }

  @override
  Class getClassFromIndex(int index) {
    return _classes[index];
  }

  @override
  int getClassIndex(Class class_) {
    return _infoFor[class_].index;
  }

  @override
  ClassSet getSubclassesOf(Class class_) {
    return new ClassSet(this, _infoFor[class_].subclasses);
  }

  @override
  ClassSet getSubtypesOf(Class class_) {
    return new ClassSet(this, _infoFor[class_].subtypes);
  }
}
