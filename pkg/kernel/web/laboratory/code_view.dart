// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.code_view;

import 'dart:html';
import 'dart:html' as html;
import 'dart:math';

import 'history_manager.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';

import 'laboratory.dart';
import 'laboratory_data.dart';
import 'laboratory_ui.dart';
import 'lexer.dart';
import 'type_view.dart';
import 'ui_component.dart';
import 'view.dart';

class CodeViewSection {
  int firstLineIndex;
  OListElement listElement;

  CodeViewSection(this.firstLineIndex, this.listElement);

  LIElement getLineNumberItem(int lineIndex) {
    int index = lineIndex - firstLineIndex;
    if (index < 0 || index >= listElement.children.length) return null;
    return listElement.children[index];
  }
}

class CodeView extends UIComponent {
  final DivElement viewElement;
  final Element filenameElement;

  final List<CodeViewSection> sections = <CodeViewSection>[];

  LIElement _focusedListItem = null;

  CodeView(this.viewElement, this.filenameElement) {
    assert(viewElement != null);
    assert(filenameElement != null);
    viewElement.onMouseMove.listen(onMouseMove);
    viewElement.onClick.listen(onClick);
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
              view.reference, astNode, inferredValueOffset)) {
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

  void onListItemClicked(LIElement listItem, MouseEvent ev) {
    String lineIndexData = listItem.dataset['lineIndex'];
    if (lineIndexData == null) return;
    ev.stopPropagation();
    if (_focusedListItem == listItem) {
      closeConstraintView();
    } else {
      int lineIndex = int.parse(lineIndexData);
      openConstraintViewAt(listItem, lineIndex);
    }
  }

  void closeConstraintView() {
    _focusedListItem?.classes?.remove(CssClass.codeLineWithConstraints);
    _focusedListItem = null;
    ui.constraintView.hide();
  }

  void openConstraintViewAt(LIElement listItem, int lineIndex) {
    int start = view.getStartOfLine(lineIndex);
    int end = view.getEndOfLine(lineIndex);
    ui.constraintView.setVisibleSourceRange(start, end);
    listItem.append(ui.constraintView.rootElement);
    _focusedListItem?.classes?.remove(CssClass.codeLineWithConstraints);
    _focusedListItem = listItem;
    listItem.classes.add(CssClass.codeLineWithConstraints);
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

  MouseEventListener showObjectOnEvent(
      Reference reference, Constraint referee) {
    return (MouseEvent event) {
      if (referee != null && referee != ui.constraintView.focusedConstraint) {
        history.push(
            new HistoryItem(referee.owner, constraintIndex: referee.index));
      }
      history.push(new HistoryItem(reference));
      showObject(reference);
    };
  }

  void showObject(Reference reference) {
    view = new View(reference);
    window.scroll(0, 0);
    ui.constraintView.hide();
    ui.typeView.hide();
    invalidate();
  }

  void showConstraint(Constraint constraint) {
    if (view.reference != constraint.owner) {
      view = new View(constraint.owner);
      invalidate();
    }
    addOneShotAnimation(() {
      int lineIndex = view.getLineFromOffset(constraint.fileOffset);
      for (var section in sections) {
        var listItem = section.getLineNumberItem(lineIndex);
        if (listItem == null) continue;
        openConstraintViewAt(listItem, lineIndex);
        ui.constraintView.focusConstraint(constraint);
      }
    });
  }

  @override
  void buildHtml() {
    if (view == null) {
      throw 'View became null when building HTML';
    }
    if (!view.hasSource) return;
    String shownFilename = extractRelevantFilePath(view.fileUri);
    filenameElement.children
      ..clear()
      ..add(new OListElement()..append(new LIElement()..text = shownFilename));
    if (!view.hasSource) {
      _showErrorMessage(getMissingSourceMessage(view.fileUri));
      return;
    }
    if (!view.hasTokens) {
      print("Could not tokenize source for URI '${view.fileUri}'");
    }
    sections.clear();
    var node = view.astNode;
    if (node is Library) {
      setContent([makeSourceList()]);
    } else if (node is Class) {
      setContent([makeSourceList(node.fileOffset)]);
    } else if (node is Member) {
      var contents = <Element>[];
      var class_ = node.enclosingClass;
      if (class_ != null) {
        contents.add(makeSourceList(class_.fileOffset));
      }
      contents.add(makeSourceList(node.fileOffset, node.fileEndOffset));
      setContent(contents);
    } else {
      setContent([]);
    }
  }

  void _showErrorMessage(String message) {
    setContent([new DivElement()..text = message]);
  }

  void setContent(List<Element> content) {
    viewElement.children
      ..clear()
      ..addAll(content);
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
    int firstLine = 0;
    int lastLine = view.numberOfLines;
    if (startOffset != null) {
      firstLine = view.getLineFromOffset(startOffset);
      htmlList.setAttribute('start', '${1 + firstLine}');
      endOffset ??= startOffset;
      // Move startOffset back to the start of its line
      startOffset = view.getStartOfLine(firstLine);
    }
    if (endOffset != null) {
      lastLine = 1 + view.getLineFromOffset(endOffset);
    }
    var section = new CodeViewSection(firstLine, htmlList);
    Token token = view.getFirstTokenAfterOffset(startOffset ?? 0);
    for (int lineIndex = firstLine; lineIndex < lastLine; ++lineIndex) {
      int start = view.getStartOfLine(lineIndex);
      int end = view.getEndOfLine(lineIndex);

      var htmlListItem = new LIElement();
      htmlListItem.dataset['lineIndex'] = '$lineIndex';

      var htmlLine = new SpanElement()..classes.add(CssClass.codeLine);
      htmlListItem.append(htmlLine);

      int offset = start;
      while (offset < end) {
        if (token == null || end <= token.offset) {
          htmlLine.appendText(view.getSourceCodeSubstring(offset, end));
          break;
        }
        if (offset < token.offset) {
          htmlLine
              .appendText(view.getSourceCodeSubstring(offset, token.offset));
        }
        htmlLine.append(makeElementFromToken(token, start, end));
        offset = token.end;
        token = token.next;
      }

      htmlList.append(htmlListItem);
    }
    sections.add(section);
    return htmlList;
  }

  html.Node makeElementFromToken(Token token, int start, int end) {
    var element = new SpanElement()..text = clampTokenString(token, start, end);
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
