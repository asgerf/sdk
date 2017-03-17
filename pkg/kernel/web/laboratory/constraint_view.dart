// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.constraint_view;

import 'dart:html';

import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';

import 'html_buffer.dart';
import 'laboratory.dart';
import 'laboratory_ui.dart';
import 'ui_component.dart';

class ConstraintView extends UIComponent {
  final DivElement containerElement;
  final TableElement tableElement;
  final TableRowElement headerRowElement;
  NamedNode shownObject;
  SourceRange visibleSourceRange = SourceRange.everything;

  LIElement currentListItemAnchor;

  ConstraintView(
      this.containerElement, this.tableElement, this.headerRowElement)
      : super(containerElement);

  Source get shownSource => ui.codeView.source;

  void hide() {
    containerElement.style.visibility = 'hidden';
  }

  void reset() {
    unsetAnchor();
    unsetVisibleSourceRange();
  }

  void setVisibleSourceRange(int start, int end) {
    visibleSourceRange = new SourceRange(start, end);
    invalidate();
  }

  void unsetVisibleSourceRange() {
    if (visibleSourceRange != SourceRange.everything) {
      visibleSourceRange = SourceRange.everything;
      invalidate();
    }
  }

  void anchorAtListItem(LIElement listItem) {
    currentListItemAnchor?.classes?.remove(CssClass.codeLineHighlighted);
    currentListItemAnchor = listItem;
    listItem.classes.add(CssClass.codeLineHighlighted);
    listItem.append(tableElement..remove());
    invalidate();
  }

  void unsetAnchor() {
    if (currentListItemAnchor != null) {
      currentListItemAnchor.classes.remove(CssClass.codeLineHighlighted);
      containerElement.append(tableElement..remove());
      currentListItemAnchor = null;
      hide();
    }
  }

  bool get shouldShowLineNumberSeparators => currentListItemAnchor == null;

  void show(NamedNode shownObject) {
    this.shownObject = shownObject;
    invalidate();
  }

  @override
  void buildHtml() {
    if (shownObject == null ||
        constraintSystem == null ||
        currentListItemAnchor == null) {
      hide();
      return;
    }
    var cluster = constraintSystem.getCluster(shownObject.reference);
    if (cluster == null) {
      hide();
      return;
    }
    containerElement.style.visibility = 'visible';
    tableElement.children.clear();
    tableElement.append(headerRowElement);
    var buffer = new KernelHtmlBuffer(tableElement, shownObject);
    var visitor = new ConstraintRowEmitter(buffer);
    var constraintList = cluster.constraints.toList();
    constraintList.sort((c1, c2) => c1.fileOffset.compareTo(c2.fileOffset));
    int currentLineIndex = -2;
    bool isEmpty = true;
    for (var constraint in constraintList) {
      if (!visibleSourceRange.contains(constraint.fileOffset)) continue;

      if (shouldShowLineNumberSeparators) {
        // Add a line number separator if we are at a different line number.
        int lineIndex = getLineFromOffset(constraint.fileOffset);
        if (lineIndex != currentLineIndex) {
          currentLineIndex = lineIndex;
          var row = new TableRowElement();
          row.classes.add(CssClass.constraintLineNumber);
          buffer.appendPush(row);
          if (lineIndex == -1) {
            buffer.append(new TableCellElement()
              ..colSpan = 4
              ..text = 'Missing source information'
              ..style.textAlign = 'right');
          } else {
            buffer.append(new TableCellElement()..colSpan = 3);
            buffer
                .append(new TableCellElement()..text = 'Line ${1 + lineIndex}');
          }
          buffer.pop();
        }
      }

      // Add the constraint details.
      buffer.appendPush(new TableRowElement());
      constraint.accept(visitor);
      buffer.pop(); // End row.

      isEmpty = false;
    }

    if (isEmpty) {
      hide();
      return;
    }
  }

  int getLineFromOffset(int offset) {
    if (offset == -1) return -1;
    return shownSource?.getLineFromOffset(offset) ?? -1;
  }
}

class ConstraintRowEmitter extends ConstraintVisitor<Null> {
  final KernelHtmlBuffer buffer;

  ConstraintRowEmitter(this.buffer);

  TableCellElement titleCell(String name) {
    return new TableCellElement()
      ..text = name
      ..classes.add(CssClass.constraintLabel);
  }

  TableCellElement rightAlignedCell() {
    return new TableCellElement()..classes.add(CssClass.right);
  }

  TableCellElement separator() {
    return new TableCellElement()..text = '\u2190';
  }

  @override
  visitEscapeConstraint(EscapeConstraint constraint) {
    buffer
      ..appendPush(rightAlignedCell()..classes.add(CssClass.constraintEscape))
      ..appendText('escape')
      ..pop()
      ..append(separator())
      ..appendPush(new TableCellElement())
      ..appendLocation(constraint.escaping)
      ..pop()
      ..append(titleCell('Escape'));
  }

  @override
  visitSubtypeConstraint(SubtypeConstraint constraint) {
    buffer
      ..appendPush(rightAlignedCell())
      ..appendLocation(constraint.destination)
      ..pop()
      ..append(separator())
      ..appendPush(new TableCellElement())
      ..appendLocation(constraint.source)
      ..pop()
      ..append(titleCell('Subtype'));
  }

  @override
  visitTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    buffer
      ..appendPush(rightAlignedCell())
      ..appendLocation(constraint.typeArgument)
      ..pop()
      ..append(separator())
      ..appendPush(new TableCellElement())
      ..appendValue(constraint.value)
      ..appendPush(new SpanElement()..classes.add(CssClass.constraintGuard))
      ..appendText(' if ')
      ..appendLocation(constraint.createdObject)
      ..appendText(' escapes')
      ..pop()
      ..pop()
      ..append(titleCell('TypeArgument'));
  }

  @override
  visitValueConstraint(ValueConstraint constraint) {
    buffer
      ..appendPush(rightAlignedCell())
      ..appendLocation(constraint.destination)
      ..pop()
      ..append(separator())
      ..appendPush(new TableCellElement())
      ..appendValue(constraint.value)
      ..pop()
      ..append(titleCell('Value'));
  }
}

class SourceRange {
  final int start, end;

  SourceRange(this.start, this.end);

  static final SourceRange everything = new SourceRange(-1, -1);

  bool get isEverything => start == -1 && end == -1;

  bool contains(int offset) {
    return isEverything || (start <= offset && offset < end);
  }
}
