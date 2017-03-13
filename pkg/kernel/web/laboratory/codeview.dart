// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';
import 'dart:math';
import 'dart:html' as html;

import 'laboratory_data.dart';
import 'lexer.dart';
import 'package:kernel/ast.dart';

import 'laboratory.dart';

class CodeView {
  final DivElement viewElement;
  final Element filenameElement;

  int firstLineShown = -1;
  Source source;
  NamedNode shownObject;
  LIElement hoveredListItem;
  Token tokenizedSource; // May be null, even if source is not null.

  CodeView(this.viewElement, this.filenameElement) {
    assert(viewElement != null);
    assert(filenameElement != null);
    viewElement.onMouseMove.listen(onMouseMove);
    viewElement.onMouseOut.listen(onMouseOut);
  }

  bool setCurrentFile(String uri) {
    String shownFilename = extractRelevantFilePath(uri);
    filenameElement.children
      ..clear()
      ..add(new OListElement()..append(new LIElement()..text = shownFilename));
    source = program.uriToSource[uri];
    if (source == null) {
      showErrorMessage(getMissingSourceMessage(uri));
      return false;
    }
    try {
      tokenizedSource = new Lexer(source.source).tokenize();
    } catch (e) {
      tokenizedSource = null;
      print("Could not tokenize source for URI '$uri'");
      print(e);
    }
    return true;
  }

  bool get hasSource => source != null;

  void onMouseMove(MouseEvent ev) {
    if (source == null || shownObject == null) return;
    var target = ev.target;
    if (target is LIElement && hoveredListItem != target) {
      var parent = target.parent;
      int index = parent.children.indexOf(target);
      int lineIndex = firstLineShown + index;
      ui.typeView.showTypesOnLine(source, shownObject, lineIndex);
      hoveredListItem = target;
    }
    if (hoveredListItem != null) {
      ui.typeView.showAt(ev.page.x, ev.page.y + 16);
    }
  }

  void onMouseOut(Event ev) {
    ui.typeView.hide();
  }

  String getMissingSourceMessage(String uri) {
    if (libraryIndex.containsLibrary(uri)) {
      return "Missing source for library '$uri'";
    } else {
      return "There is no library or source file for '$uri'";
    }
  }

  void showObject(NamedNode node) {
    if (node is Library) {
      showLibrary(node);
    } else if (node is Class) {
      showClass(node);
    } else if (node is Member) {
      showMember(node);
    } else {
      shownObject = null;
      showNothing();
    }
  }

  void showLibrary(Library library) {
    shownObject = library;
    if (setCurrentFile(library.fileUri)) {
      setContent([makeSourceList()]);
    }
  }

  void showClass(Class node) {
    shownObject = node;
    if (setCurrentFile(node.fileUri)) {
      setContent([makeSourceList(node.fileOffset)]);
    }
  }

  void showMember(Member member) {
    shownObject = member;
    if (!setCurrentFile(member.fileUri)) return;
    var contents = <Element>[];
    var class_ = member.enclosingClass;
    if (class_ != null) {
      contents.add(makeSourceList(class_.fileOffset));
    }
    contents.add(makeSourceList(member.fileOffset, member.fileEndOffset));
    setContent(contents);
  }

  void showErrorMessage(String message) {
    setContent([new DivElement()..text = message]);
  }

  void showNothing() {
    setContent([]);
  }

  void setContent(List<Element> content) {
    viewElement.children
      ..clear()
      ..addAll(content);
  }

  Token getFirstTokenAfterOffset(Token token, int offset) {
    while (token != null && token.end <= offset) {
      token = token.next;
    }
    return token;
  }

  /// Returns the part of the given token that is between the absolute file
  /// offsets [from] and [to].
  ///
  /// This is used to extract the part of a multi-line token that belongs on
  /// a given line.
  String clampTokenString(Token token, int from, int to) {
    if (from <= token.offset && token.end < to) {
      return token.lexeme;
    }
    int start = max(from, token.offset);
    int end = min(to, token.end);
    return token.lexeme.substring(start - token.offset, end - token.offset);
  }

  OListElement makeSourceList([int startOffset, int endOffset]) {
    var htmlList = new OListElement();
    var code = source.source;
    int numberOfLines = source.lineStarts.length;
    int firstLine = 0;
    int lastLine = numberOfLines;
    if (startOffset != null) {
      firstLine = source.getLineFromOffset(startOffset);
      htmlList.setAttribute('start', '${1 + firstLine}');
      endOffset ??= startOffset;
      // Move startOffset back to the start of its line
      startOffset = source.lineStarts[firstLine];
    }
    if (endOffset != null) {
      lastLine = 1 + source.getLineFromOffset(endOffset);
    }
    Token token = getFirstTokenAfterOffset(tokenizedSource, startOffset ?? 0);
    print('First token is $token');
    print('Previous token is ${token.previous}');
    firstLineShown = firstLine;
    for (int lineIndex = firstLine; lineIndex < lastLine; ++lineIndex) {
      int start = source.lineStarts[lineIndex];
      int end = lineIndex == numberOfLines - 1
          ? code.length
          : source.lineStarts[lineIndex + 1];

      var htmlLine = new LIElement();

      int offset = start;
      while (offset < end) {
        if (token == null || end <= token.offset) {
          htmlLine.appendText(code.substring(offset, end));
          break;
        }
        if (offset < token.offset) {
          htmlLine.appendText(code.substring(offset, token.offset));
        }
        htmlLine.append(makeTokenElement(token));
        offset = token.end;
        token = token.next;
      }

      htmlList.append(htmlLine);
    }
    return htmlList;
  }

  html.Node makeTokenElement(Token token) {
    if (token.keyword != null || keywords.contains(token.lexeme)) {
      return new SpanElement()
        ..text = token.lexeme
        ..classes.add('keyword');
    }
    if (Lexer.isUpperCaseLetter(token.lexeme.codeUnitAt(0))) {
      return new SpanElement()
        ..text = token.lexeme
        ..classes.add('typename');
    }
    return new html.Text(token.lexeme);
  }

  static final Set<String> keywords =
      new Set<String>.from(['int', 'double', 'num', 'bool', 'void']);

  String extractRelevantFilePath(String uri) {
    if (!uri.startsWith('file:')) return uri;
    var commonRootFolderNames = [
      'lib',
      'bin',
      'web',
      'test',
      'pkg',
      'packages',
    ];
    int lowestIndex = uri.length;
    for (var rootName in commonRootFolderNames) {
      int index = uri.indexOf('$rootName/');
      if (index != -1 && index < lowestIndex) {
        lowestIndex = index;
      }
    }
    if (lowestIndex != uri.length) {
      return uri.substring(lowestIndex);
    }
    return uri;
  }
}
