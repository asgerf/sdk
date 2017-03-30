var global;

class Super<T> {
  void method(T x) {
    global = x;
  }
}

class Sub<T> extends Super<T> {}

main() {
  new Sub<int>().method(5);
  print(global);
}
