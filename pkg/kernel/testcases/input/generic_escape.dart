class Generic<T> {
  void escapeMe(dynamic object, T arg) {
    object.foo(arg);
  }
}

class Something {
  void foo(List<int> list) {
    list.add(null);
  }
}

main() {
  var list = <int>[1, 2, 3];
  new Generic<List<int>>().escapeMe(new Something(), list);
  int nullableInt = list.last;
}
