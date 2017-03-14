// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';
import 'dart:math';
import 'dart:html' as html;

import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'lexer.dart';
import 'package:kernel/ast.dart';

import 'laboratory.dart';

class CodeView {
  final DivElement viewElement;
  final Element filenameElement;

  int firstLineShown = -1;
  Source source;
  NamedNode shownObject;
  Element hoveredSpan;
  Token tokenizedSource; // May be null, even if source is not null.

  List<Expression> expressions;

  CodeView(this.viewElement, this.filenameElement) {
    assert(viewElement != null);
    assert(filenameElement != null);
    viewElement.onMouseMove.listen(onMouseMove);
    viewElement.onMouseOut.listen(onMouseOut);
  }

  bool setCurrentFile(String uri, TreeNode node) {
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
      tokenizedSource = new Lexer.fromCharCodes(source.source).tokenize();
    } catch (e) {
      tokenizedSource = null;
      print("Could not tokenize source for URI '$uri'");
      print(e);
    }
    expressions = <Expression>[];
    node?.accept(new ExpressionCollector(expressions));
    expressions.sort((e1, e2) => e1.fileOffset.compareTo(e2.fileOffset));
    return true;
  }

  bool get hasSource => source != null;

  void onMouseMove(MouseEvent ev) {
    if (source == null || shownObject == null) return;
    var target = ev.target;
    if (target is! Element) return;
    Element targetElement = target;
    String indexString = targetElement.dataset['id'];
    int index = indexString == null ? -1 : int.parse(indexString);
    if (index == -1) {
      hideTypeView();
    } else if (index != -1 && hoveredSpan != target) {
      hoveredSpan?.classes?.remove(CssClass.highlightedToken);
      var expression = expressions[index];
      if (expression != null &&
          ui.typeView.showTypeOfExpression(shownObject, expression)) {
        hoveredSpan = target;
        hoveredSpan.classes.add(CssClass.highlightedToken);
      } else {
        hideTypeView();
      }
    }
    if (hoveredSpan != null) {
      ui.typeView.showAt(ev.page.x, ev.page.y + 16);
    }
  }

  void hideTypeView() {
    hoveredSpan?.classes?.remove(CssClass.highlightedToken);
    hoveredSpan = null;
    ui.typeView.hide();
  }

  void onMouseOut(Event ev) {
    hideTypeView();
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
    if (setCurrentFile(library.fileUri, library)) {
      setContent([makeSourceList()]);
    }
  }

  void showClass(Class node) {
    shownObject = node;
    if (setCurrentFile(node.fileUri, node)) {
      setContent([makeSourceList(node.fileOffset)]);
    }
  }

  void showMember(Member member) {
    shownObject = member;
    if (!setCurrentFile(member.fileUri, member)) return;
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

  int getIndexOfLastExpressionStrictlyBeforeOffset(int offset) {
    int first = 0, last = expressions.length - 1;
    while (first < last) {
      int mid = last - ((last - first) >> 1);
      int pivot = expressions[mid].fileOffset;
      if (offset <= pivot) {
        last = mid - 1;
      } else {
        first = mid;
      }
    }
    return last;
  }

  int getExpressionIndexFromToken(Token token) {
    var index = getIndexOfLastExpressionStrictlyBeforeOffset(token.end);
    if (index == -1) return -1;
    var expression = expressions[index];
    if (token.offset <= expression.fileOffset &&
        expression.fileOffset < token.end) {
      return index;
    }
    return -1;
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
          htmlLine.appendText(source.getSubstring(offset, end));
          break;
        }
        if (offset < token.offset) {
          htmlLine.appendText(source.getSubstring(offset, token.offset));
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
    var element = new SpanElement()..text = token.lexeme;
    if (token.keyword != null || keywords.contains(token.lexeme)) {
      element.classes.add('keyword');
    } else if (Lexer.isUpperCaseLetter(token.lexeme.codeUnitAt(0))) {
      element.classes.add('typename');
    }
    var index = getExpressionIndexFromToken(token);
    if (index != -1) {
      element.dataset['id'] = '$index';
    }
    return element;
  }

  /// Words that are recognized as keywords but should be highlighted as such.
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

class ExpressionCollector extends RecursiveVisitor {
  final List<Expression> result;

  ExpressionCollector(this.result);

  @override
  defaultExpression(Expression node) {
    if (node.fileOffset != TreeNode.noOffset) {
      result.add(node);
    }
    node.visitChildren(this);
  }
}
