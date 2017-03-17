// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.code_view;

import 'dart:html';
import 'dart:html' as html;
import 'dart:math';

import 'package:kernel/ast.dart';

import 'laboratory.dart';
import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'lexer.dart';
import 'view.dart';

class CodeView {
  final DivElement viewElement;
  final Element filenameElement;

  CodeView(this.viewElement, this.filenameElement) {
    assert(viewElement != null);
    assert(filenameElement != null);
    viewElement.onMouseMove.listen(onMouseMove);
    viewElement.onClick.listen(onClick);
  }

  bool setCurrentFile(String uri, TreeNode node) {
    String shownFilename = extractRelevantFilePath(uri);
    filenameElement.children
      ..clear()
      ..add(new OListElement()..append(new LIElement()..text = shownFilename));
    if (!view.hasSource) {
      showErrorMessage(getMissingSourceMessage(uri));
      return false;
    }
    if (!view.hasTokens) {
      print("Could not tokenize source for URI '$uri'");
    }
    ui.constraintView.remove();
    return true;
  }

  void onMouseMove(MouseEvent ev) {
    if (!view.hasAstNodes) return;
    var target = ev.target;
    if (target is! Element) return;
    Element targetElement = target;
    String indexString = targetElement.dataset['id'];
    int index = indexString == null ? -1 : int.parse(indexString);
    if (index == -1) {
      hideTypeView();
    } else if (target != ui.typeView.highlightedElement) {
      var astNode = view.astNodes[index];
      var inferredValueOffset = getInferredValueOffset(astNode);
      if (astNode != null &&
          ui.typeView.showTypeOfExpression(
              view.shownObject, astNode, inferredValueOffset)) {
        ui.typeView.setHighlightedElement(target);
      } else {
        hideTypeView();
      }
    }
    if (index != -1) {
      ev.stopPropagation();
      ui.typeView.showAt(ev.page.x, ev.page.y);
    }
  }

  /// Event handler for clicks on the whole code view.
  void onClick(MouseEvent ev) {
    if (!view.hasSource) return;
    var target = ev.target;
    if (target is! Element) return;
    Element element = target;
    while (element != viewElement && element != null) {
      if (element is LIElement) {
        onListItemClicked(element, ev);
        return;
      }
      element = element.parent;
    }
  }

  LIElement currentListItemAnchor = null;

  void onListItemClicked(LIElement listItem, MouseEvent ev) {
    String lineIndexData = listItem.dataset['lineIndex'];
    if (lineIndexData == null) return;
    ev.stopPropagation();
    if (currentListItemAnchor == listItem) {
      currentListItemAnchor?.classes?.remove(CssClass.codeLineHighlighted);
      currentListItemAnchor = null;
      ui.constraintView.remove();
      return;
    }
    int lineIndex = int.parse(lineIndexData);
    int start = view.source.lineStarts[lineIndex];
    int end = view.source.getEndOfLine(lineIndex);
    listItem.append(ui.constraintView.rootElement);
    ui.constraintView.setShownObject(view.shownObject);
    ui.constraintView.setVisibleSourceRange(start, end);
    currentListItemAnchor?.classes?.remove(CssClass.codeLineHighlighted);
    currentListItemAnchor = listItem;
    listItem.classes.add(CssClass.codeLineHighlighted);
  }

  void hideTypeView() {
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
    window.scroll(0, 0);
    if (node is Library) {
      showLibrary(node);
    } else if (node is Class) {
      showClass(node);
    } else if (node is Member) {
      showMember(node);
    } else {
      showNothing();
    }
  }

  void showLibrary(Library library) {
    view = new View(library);
    if (setCurrentFile(library.fileUri, library)) {
      setContent([makeSourceList()]);
    }
  }

  void showClass(Class node) {
    view = new View(node);
    if (setCurrentFile(node.fileUri, node)) {
      setContent([makeSourceList(node.fileOffset)]);
    }
  }

  void showMember(Member member) {
    view = new View(member);
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
    var code = view.source.source;
    int numberOfLines = view.source.lineStarts.length;
    int firstLine = 0;
    int lastLine = numberOfLines;
    if (startOffset != null) {
      firstLine = view.source.getLineFromOffset(startOffset);
      htmlList.setAttribute('start', '${1 + firstLine}');
      endOffset ??= startOffset;
      // Move startOffset back to the start of its line
      startOffset = view.source.lineStarts[firstLine];
    }
    if (endOffset != null) {
      lastLine = 1 + view.source.getLineFromOffset(endOffset);
    }
    Token token =
        getFirstTokenAfterOffset(view.tokenizedSource, startOffset ?? 0);
    for (int lineIndex = firstLine; lineIndex < lastLine; ++lineIndex) {
      int start = view.source.lineStarts[lineIndex];
      int end = lineIndex == numberOfLines - 1
          ? code.length
          : view.source.lineStarts[lineIndex + 1];

      var htmlListItem = new LIElement();
      htmlListItem.dataset['lineIndex'] = '$lineIndex';

      var htmlLine = new SpanElement();
      htmlListItem.append(htmlLine);

      int offset = start;
      while (offset < end) {
        if (token == null || end <= token.offset) {
          htmlLine.appendText(view.source.getSubstring(offset, end));
          break;
        }
        if (offset < token.offset) {
          htmlLine.appendText(view.source.getSubstring(offset, token.offset));
        }
        htmlLine.append(makeTokenElement(token));
        offset = token.end;
        token = token.next;
      }

      htmlList.append(htmlListItem);
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
    var index = view.getAstNodeIndexFromToken(token);
    if (index != -1) {
      element.dataset['id'] = '$index';
      var astNode = view.astNodes[index];
      int locationIndex = getInferredValueOffset(astNode);
      if (locationIndex != -1) {
        element.classes.add('v$locationIndex');
      }
    }
    return element;
  }

  /// Words that are not recognized as keywords by the lexer but should be
  /// highlighted as such.
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
