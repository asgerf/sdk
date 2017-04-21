import 'dart:collection';

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

  {
    var stuff = new Set<String>.from(<String>["hello", null]);
    var nullableString = stuff.first;
  }

  {
    var stuff = new Set<String>.from(<String>["hello", "world"]);
    var nonNullableString = stuff.first;
  }

  {
    var stuff = new Set<String>.from(<String>["hello", "world"]);
    stuff.add(null);
    var nullableString = stuff.first;
  }

  {
    var stuff = new Set<String>.from(<Object>["hello", "world"]);
    var nonNullableString = stuff.first;
  }

  {
    var stringList = <String>["hello", "world"];
    var stuff = new Set<String>.from(stringList);
    stuff.add(null);
    var nonNullableString = stringList[n];
  }

  {
    var stuff = new Queue<String>.from(<String>["hello", null]);
    var nullableString = stuff.first;
  }

  {
    var stuff = new Queue<String>.from(<String>["hello", "world"]);
    var nonNullableString = stuff.first;
  }

  {
    var stuff = new Queue<String>.from(<String>["hello", "world"]);
    stuff.add(null);
    var nullableString = stuff.first;
  }

  {
    var stuff = new Queue<String>.from(<Object>["hello", "world"]);
    var nonNullableString = stuff.first;
  }

  {
    var stringList = <String>["hello", "world"];
    var stuff = new Queue<String>.from(stringList);
    stuff.add(null);
    var nonNullableString = stringList[n];
  }
}
