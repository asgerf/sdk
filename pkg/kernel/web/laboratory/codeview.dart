// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';

import 'package:kernel/ast.dart';

import 'laboratory.dart';

class CodeView {
  final DivElement viewElement;

  CodeView(this.viewElement) {
    assert(viewElement != null);
  }

  void showLibrary(String library) {
    Source source = program.uriToSource[library];
    if (source == null) {
      if (libraryIndex.containsLibrary(library)) {
        source = new Source([0], "Missing library source for '$library'");
      } else {
        source = new Source([0], "There is no library for '$library'");
      }
    }
    showSource(source);
  }

  void showSource(Source source) {
    var htmlList = new OListElement();
    var code = source.source;
    int numberOfLines = source.lineStarts.length;
    for (int lineIndex = 0; lineIndex < numberOfLines; ++lineIndex) {
      int start = source.lineStarts[lineIndex];
      int end = lineIndex == numberOfLines - 1
          ? code.length
          : source.lineStarts[lineIndex + 1];
      String lineText = code.substring(start, end);
      var htmlLine = new LIElement()..text = lineText;
      htmlList.append(htmlLine);
    }
    viewElement.children
      ..clear()
      ..add(htmlList);
  }
}
