// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library parser.main;

import 'dart:convert' show
    LineSplitter,
    UTF8;

import 'dart:io' show
    File;

import 'package:scanner/src/token.dart' show
    Token;

import 'package:scanner/io.dart' show
    readBytesFromFileSync;

import 'package:scanner/scanner.dart' show
    scan;

import 'listener.dart' show
    Listener;

import 'top_level_parser.dart' show
    TopLevelParser;

class DebugListener extends Listener {
  void handleIdentifier(Token token) {
    logEvent("Identifier: ${token.value}");
  }

  void logEvent(String name) {
    print(name);
  }
}

main(List<String> arguments) async {
  for (String argument in arguments) {
    if (argument.startsWith("@")) {
      Uri uri = Uri.base.resolve(argument.substring(1));
      await for (String file in new File.fromUri(uri).openRead()
                     .transform(UTF8.decoder)
                     .transform(const LineSplitter())) {
        outLine(uri.resolve(file));
      }
    } else {
      outLine(Uri.base.resolve(argument));
    }
  }
}

void outLine(Uri uri) {
  new TopLevelParser(new DebugListener()).parseUnit(
      scan(readBytesFromFileSync(uri)).tokens);
}
