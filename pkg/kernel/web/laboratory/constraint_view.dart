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

class ConstraintView {
  final DivElement containerElement;
  NamedNode shownObject;

  ConstraintView(this.containerElement);

  void hide() {
    containerElement.style.visibility = 'hidden';
  }

  void show(NamedNode shownObject) {
    this.shownObject = shownObject;
    containerElement.style.visibility = 'visible';
    containerElement.children.clear();
    var cluster = constraintSystem.getCluster(shownObject.reference);
    if (cluster == null) return;
    var buffer = new KernelHtmlBuffer(containerElement, shownObject);
    var visitor = new ConstraintRowEmitter(buffer);
    buffer.appendPush(new TableElement());
    for (var constraint in cluster.constraints) {
      buffer.appendPush(new TableRowElement());
      constraint.accept(visitor);
      buffer.pop(); // End row.
    }
    buffer.pop(); // End the table.
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

  @override
  visitEscapeConstraint(EscapeConstraint constraint) {
    buffer
      ..append(titleCell('Escape'))
      ..appendPush(new TableCellElement())
      ..appendLocation(constraint.escaping)
      ..pop(); // cell
  }

  @override
  visitSubtypeConstraint(SubtypeConstraint constraint) {
    buffer
      ..append(titleCell('Subtype'))
      ..appendPush(new TableCellElement())
      ..appendLocation(constraint.destination)
      ..pop()
      ..appendPush(new TableCellElement())
      ..appendText(' <- ')
      ..pop()
      ..appendPush(new TableCellElement())
      ..appendLocation(constraint.source)
      ..pop();
  }

  @override
  visitTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    buffer.append(titleCell('TypeArgument'));
  }

  @override
  visitValueConstraint(ValueConstraint constraint) {
    buffer
      ..append(titleCell('Value'))
      ..appendPush(new TableCellElement())
      ..appendLocation(constraint.destination)
      ..pop()
      ..appendPush(new TableCellElement())
      ..appendText(' <- ')
      ..pop()
      ..appendPush(new TableCellElement())
      ..appendValue(constraint.value)
      ..pop();
  }
}
