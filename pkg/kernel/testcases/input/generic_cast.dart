class CastToT<T> {
  final List<T> list = <T>[];

  void tryAdd(Object x) {
    list.add(x as T);
  }
}

class CastFromT<T> {
  final List<T> list = <T>[];

  String tryGetString() => list[0] as String;
}

class CastCompoundToT<T> {
  final List<T> list = <T>[];

  void tryAddAll(Object x) {
    list.addAll(x as List<T>);
  }
}

class CastCompoundToT2<T> {
  final List<T> list = <T>[];

  void tryAddAll(Object x) {
    list.addAll(x as List<T>);
  }
}

class CastCompoundFromT<T> {
  final List<T> list = <T>[];

  List<T> tryGetMemberAsList() {
    return list[0] as List<T>;
  }
}

main(List<String> args) {
  int n = args.length;
  {
    var object = new CastToT<String>();
    object.tryAdd("hello");
    var string = object.list[0];
  }

  {
    var object = new CastFromT<String>();
    object.list.add("hello");
    var string = object.tryGetString();
  }

  {
    var object = new CastCompoundToT<String>();
    object.list.add("hello");
    object.tryAddAll(<String>[null]);
    var nullableString = object.list[n];
  }

  {
    var object = new CastCompoundToT2<String>();
    object.list.add(null);
    object.tryAddAll(<String>["hello"]);
    var nullableString = object.list[n];
  }

  {
    var object = new CastCompoundFromT<Object>();
    object.list.add(<Object>["hello"]);
    var list = object.tryGetMemberAsList();
    var string = list[n];
  }
}
