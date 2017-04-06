class Super<T> {
  T field;

  Super(this.field);
}

class Sub<T> extends Super<T> {
  Sub(T x) : super(x);

  void setValue(T value) {
    this.field = value;
  }
}

main() {
  var obj1 = new Sub<int>(5);
  var value1 = obj1.field;

  var obj2 = new Sub<int>(5);
  obj2.setValue(null);
  var value2 = obj2.field;

  var obj3 = new Sub<int>(null);
  var value3 = obj3.field;
}
