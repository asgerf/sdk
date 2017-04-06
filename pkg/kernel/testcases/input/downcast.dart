class Baseclass {}

class Subclass extends Baseclass {}

class Subtype implements Baseclass {}

class Unrelated {}

main() {
  downcastSomething(new Baseclass(), 0);
  downcastSomething(new Subclass(), 1);
  downcastSomething(new Subtype(), 2);
  downcastSomething(new Unrelated(), 3);
}

void downcastSomething(Object x, int n) {
  if (n == 0) takeBaseclass(x as Baseclass);
  if (n == 1) takeSubclass(x as Subclass);
  if (n == 2) takeSubtype(x as Subtype);
  if (n == 3) takeUnrelated(x as Unrelated);
}

void takeBaseclass(Baseclass x) {}
void takeSubclass(Subclass x) {}
void takeSubtype(Subtype x) {}
void takeUnrelated(Unrelated x) {}
