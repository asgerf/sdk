class Container<E> {
  E nullableField;
  E nonNullableField;

  Container(this.nonNullableField, this.nullableField);

  void makeNull() {
    nullableField = null;
  }
}

main() {
  var container = new Container<String>('foo', 'bar');
  container.makeNull();
  var nonNullable = container.nonNullableField;
  var nullable = container.nullableField;
}
