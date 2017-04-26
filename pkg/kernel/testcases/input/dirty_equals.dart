class DirtyEquals {
  bool operator ==(Object obj) {
    if (obj is List<int>) {
      obj.add(null);
    }
    return false;
  }
}

class NotSoDirtyEquals {
  bool operator ==(Object obj) {
    if (obj is List<int>) {
      return obj.isNotEmpty && obj.last == 0;
    }
    return false;
  }
}

class CleanEquals {
  int field;

  CleanEquals(this.field);

  bool operator ==(Object other) {
    if (other is CleanEquals) {
      return field == other.field;
    }
    return false;
  }
}

class DirtyNonGenericEquals {
  int field;

  DirtyNonGenericEquals(this.field);

  bool operator ==(Object other) {
    if (other is DirtyNonGenericEquals) {
      other.field = null;
      return true;
    }
    return false;
  }
}

void callDirtyEquals(Object arg) {
  var intList = <int>[45];
  arg == intList;
  int nullableInt = intList.last;
}

void callNotSoDirtyEquals(Object arg) {
  var intList = <int>[45];
  arg == intList;
  int nonNullableInt = intList.last;
}

void callCleanEquals(Object arg) {
  var intList = <int>[45];
  arg == intList;
  int nonNullableInt = intList.last;
}

void callDirtyNonGenericEquals(DirtyNonGenericEquals arg) {
  var intList = <int>[45];
  arg == intList;
  int nonNullableInt = intList.last;
  int nullableInt = arg.field;
}

void indexOfInDirtyEquals(Object arg) {
  var list = <Object>[arg];
  var intList = <int>[45];
  list.indexOf(intList);
  int nullableInt = intList.last;
}

void indexOfInNotSoDirtyEquals(Object arg) {
  var list = <Object>[arg];
  var intList = <int>[45];
  list.indexOf(intList);
  int nonNullableInt = intList.last;
}

void indexOfInCleanEquals(Object arg) {
  var list = <Object>[arg];
  var intList = <int>[45];
  list.indexOf(intList);
  int nonNullableInt = intList.last;
}

void indexOfInDirtyNonGenericEquals(DirtyNonGenericEquals arg) {
  var list = <Object>[arg];
  var intList = <int>[45];
  list.indexOf(intList);
  int nonNullableInt = intList.last;
  int nullableInt = arg.field;
}

main() {
  callDirtyEquals(new DirtyEquals());
  callNotSoDirtyEquals(new NotSoDirtyEquals());
  callCleanEquals(new CleanEquals(0));
  callDirtyNonGenericEquals(new DirtyNonGenericEquals(0));

  indexOfInDirtyEquals(new DirtyEquals());
  indexOfInNotSoDirtyEquals(new NotSoDirtyEquals());
  indexOfInCleanEquals(new CleanEquals(0));
  indexOfInDirtyNonGenericEquals(new DirtyNonGenericEquals(0));
}
