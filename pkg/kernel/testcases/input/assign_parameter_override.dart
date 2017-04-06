class Superclass {
  foo(int x) {
    x = null;
  }
}

class Subclass extends Superclass {
  foo(int x) {
    print(x);
  }
}

main() {
  new Superclass().foo(4);
  new Subclass().foo(4);
}
