library kernel.text.printable;

import 'ast_to_text.dart' show Printer;
export 'ast_to_text.dart' show Printer;

abstract class Printable {
  void printTo(Printer printer);

  static String show(Printable printable) {
    var buffer = new StringBuffer();
    printable.printTo(new Printer(buffer));
    return '$buffer';
  }
}
