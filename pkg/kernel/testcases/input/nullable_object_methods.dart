class NullableToString {
  String toString() => null;
}

class NullableRuntimeType {
  Type get runtimeType => null;
}

class NullableHashCode {
  int get hashCode => null;
}

class NullableEquals {
  bool operator ==(x) => null;
}

class NiceObject1 {
  String toString() => 'nice1';
  int get hashCode => 1;
  bool operator ==(x) => true;
}

class NiceObject2 {
  String toString() => 'nice2';
  int get hashCode => 2;
  bool operator ==(x) => true;
}

main() {
  inspectAny(new NullableToString());
  inspectAny(new NullableRuntimeType());
  inspectAny(new NullableHashCode());
  inspectAny(new NullableEquals());
  inspectAny(new NiceObject1());
  inspectAny(new NiceObject2());
  inspectAny(new Object());

  inspectNice(new NiceObject1());
  inspectNice(new NiceObject2());
}

inspectAny(Object x) {
  var string = x.toString();
  var stringFromTearOff = (x.toString)();
  var hashCode = x.hashCode;
  var runtimeType = x.runtimeType;
  var equals = x == x;
}

inspectNice(Object x) {
  var string = x.toString();
  var stringFromTearOff = (x.toString)();
  var hashCode = x.hashCode;
  var runtimeType = x.runtimeType;
  var equals = x == x;
}
