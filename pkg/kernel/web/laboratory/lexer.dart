library laboratory.lexer;

import 'package:front_end/src/scanner/errors.dart';
import 'package:front_end/src/scanner/reader.dart';
import 'package:front_end/src/scanner/scanner.dart';
import 'package:charcode/ascii.dart';

export 'package:front_end/src/scanner/token.dart' show Token, TokenType;

class Lexer extends Scanner {
  bool success = true;

  Lexer(String string) : super(new CharSequenceReader(string));

  Lexer.fromCharCodes(List<int> charCodes)
      : this(new String.fromCharCodes(charCodes));

  @override
  void reportError(
      ScannerErrorCode errorCode, int offset, List<Object> arguments) {
    success = false;
  }

  static bool isUpperCaseLetter(int charCode) {
    return $A <= charCode && charCode <= $Z;
  }
}
