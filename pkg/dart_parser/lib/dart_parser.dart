// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library dart_parser;

import 'package:dart_scanner/src/token.dart' show
    Token;

import 'src/listener.dart' show
    Listener;

import 'src/parser.dart' show
    Parser;

import 'src/listener.dart' show
    ParserError;

export 'src/listener.dart' show
    ParserError;

List<ParserError> parse(Token tokens) {
  Listener listener = new Listener();
  Parser parser = new Parser(listener);
  parser.parseUnit(tokens);
  return listener.recoverableErrors;
}
