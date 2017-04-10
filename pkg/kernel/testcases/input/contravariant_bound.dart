main() {
  foo((list) {
    list.add(null);
  });
}

foo(void callback(List<String> strings)) {
  List<String> strings = ['foo'];
  callback(strings);
  String x = strings.last;
}
