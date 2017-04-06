T identity<T>(T x) => x;

T nullifier<T>(T x) => null;

main() {
  takeIdentityFunction(identity, true);
  takeNullifier(nullifier, true);
}

takeIdentityFunction(T id<T>(T x), bool b) {
  String nonNullableString = id("string");
  String nullableString = id(b ? null : "hello");

  int nonNullableInt = id(45);
  int nullableInt = id(b ? null : 45);
}

takeNullifier(T nu<T>(T x), bool b) {
  String nonNullableString = nu("string");
  String nullableString = nu(b ? null : "hello");

  int nonNullableInt = nu(45);
  int nullableInt = nu(b ? null : 45);
}
