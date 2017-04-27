class TearOffEscape {
  void dynamicCall(List<int> list) {
    int nullableInt = list.last;
  }

  void staticDirtyCall(List<int> list) {
    int nullableInt = list.last;
  }

  void staticCleanCall(List<int> list) {
    int nonNullableInt = list.last;
  }
}

class Generic<T> {
  T field;

  Generic(this.field);

  void assign(List<T> list) {
    field = list.last;
  }
}

void main() {
  var tearOffEscape = new TearOffEscape();
  doDynamicCall(tearOffEscape.dynamicCall);
  doStaticDirtyCall(tearOffEscape.staticDirtyCall);
  doStaticCleanCall(tearOffEscape.staticCleanCall);

  var dirty = new Generic<int>(0);
  var clean = new Generic<int>(0);
  doGenericDynamicCall(dirty.assign);
  doGenericCleanCall(clean.assign);
  int nullableInt = dirty.field;
  int nonNullableInt = clean.field;
}

void doDynamicCall(dynamic callback) {
  callback(<int>[45, null]);
}

void doStaticDirtyCall(void callback(List<int> list)) {
  callback(<int>[45, null]);
}

void doStaticCleanCall(void callback(List<int> list)) {
  callback(<int>[45]);
}

void doGenericDynamicCall(dynamic callback) {
  callback(<int>[45, null]);
}

void doGenericCleanCall(void callback(List<int> list)) {
  callback(<int>[45]);
}
