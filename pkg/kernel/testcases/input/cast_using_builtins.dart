main(List<String> args) {
  int n = args.length;
  {
    var list = new List<String>.from(<String>["hello", null]);
    var nullableString = list[n];
  }

  {
    var list = new List<String>.from(<String>["hello", "world"]);
    var nonNullableString = list[n];
  }

  {
    var list = new List<String>.from(<String>["hello", "world"]);
    list[0] = null;
    var nullableString = list[n];
  }

  {
    var list = new List<String>.from(<Object>["hello", "world"]);
    var nonNullableString = list[n];
  }

  {
    var stringList = <String>["hello", "world"];
    var list = new List<String>.from(stringList);
    list[0] = null;
    var nonNullableString = stringList[n];
  }
}
