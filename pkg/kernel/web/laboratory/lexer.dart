// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.lexer;

import 'package:charcode/ascii.dart';
import 'package:front_end/src/scanner/errors.dart';
import 'package:front_end/src/scanner/reader.dart';
import 'package:front_end/src/scanner/scanner.dart';
import 'package:front_end/src/scanner/token.dart';
import 'package:kernel/ast.dart';

export 'package:front_end/src/scanner/token.dart' show Token, TokenType;

class Lexer extends Scanner {
  bool success = true;

  Lexer(String string) : super.create(new CharSequenceReader(string));

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

Token tryTokenizeSource(Source source) {
  if (source == null) return null;
  try {
    return new Lexer(source.text).tokenize();
  } catch (e) {
    // Ignore exception.
  }
  return null;
}
