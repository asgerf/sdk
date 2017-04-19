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

  new Generic2<NullableToString>().inspect(new NullableToString());
  new Generic2<NullableRuntimeType>().inspect(new NullableRuntimeType());
  new Generic2<NullableHashCode>().inspect(new NullableHashCode());
  new Generic2<NullableEquals>().inspect(new NullableEquals());
  new Generic2<NiceObject1>().inspect(new NiceObject1());
  new Generic2<NiceObject2>().inspect(new NiceObject2());
}

inspectAny(Object x) {
  var string = x.toString();
  var stringFromTearOff = (x.toString)();
  var hashCode = x.hashCode;
  var runtimeType = x.runtimeType;
  var equals = x == x;
  new Generic1<Object>().inspect(x);
}

inspectNice(Object x) {
  var string = x.toString();
  var stringFromTearOff = (x.toString)();
  var hashCode = x.hashCode;
  var runtimeType = x.runtimeType;
  var equals = x == x;
}

class Generic1<T> {
  inspect(T x) {
    var string = x.toString();
    var stringFromTearOff = (x.toString)();
    var hashCode = x.hashCode;
    var runtimeType = x.runtimeType;
    var equals = x == x;
  }
}

class Generic2<T> {
  inspect(T x) {
    var string = x.toString();
    var stringFromTearOff = (x.toString)();
    var hashCode = x.hashCode;
    var runtimeType = x.runtimeType;
    var equals = x == x;
  }
}
