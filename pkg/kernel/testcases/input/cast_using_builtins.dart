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

  {
    var map = new Map<String, int>.from(<String, int>{"foo": 45});
    var nonNullableString = map.keys.first;
    int nonNullableInt = map.values.first;
  }

  {
    var map = new Map<String, int>.from(<String, int>{"foo": null, "bar": 45});
    var nonNullableString = map.keys.first;
    int nullableInt = map.values.first;
  }

  {
    var map = new Map<String, int>.from(<String, int>{null: 45, "bar": 45});
    var nullableString = map.keys.first;
    int nonNullableInt = map.values.first;
  }

  {
    var map = new Map<String, int>.from(<Object, Object>{null: 45, "bar": 45});
    var nullableString = map.keys.first;
    int nonNullableInt = map.values.first;
  }

  {
    var originalMap = <String, int>{"foo": 45};
    var map = new Map<String, int>.from(originalMap);
    map["bar"] = null;
    var nonNullableString = originalMap.keys.first;
    int nonNullableInt = originalMap.values.first;
  }

  {
    var map = new Map<String, int>.from(<String, int>{"foo": 45});
    map["bar"] = null;
    var nonNullableString = map.keys.first;
    int nullableInt = map.values.first;
  }

  {
    var map = new Map<String, int>.from(<String, int>{"foo": 45});
    map[null] = 45;
    var nullableString = map.keys.first;
    int nonNullableInt = map.values.first;
  }
}
