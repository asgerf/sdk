// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.constraint_view;

import 'dart:html';
import 'dart:html' as html;
import 'laboratory.dart';

import 'laboratory_ui.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';

class HtmlBuffer {
  final List<Element> containerStack = <Element>[];

  HtmlBuffer(Element root) {
    containerStack.add(root);
  }

  void append(html.Node node) {
    containerStack.last.append(node);
  }

  void appendText(String text) {
    containerStack.last.appendText(text);
  }

  void appendPush(html.Element node) {
    containerStack.last.append(node);
    containerStack.add(node);
  }

  void pop() {
    containerStack.removeLast();
  }
}

class KernelHtmlBuffer extends HtmlBuffer {
  final NamedNode shownObject;
  ConstraintRowEmitter constraintRowEmitter;

  KernelHtmlBuffer(Element root, this.shownObject) : super(root) {
    constraintRowEmitter = new ConstraintRowEmitter(this);
  }

  void appendReference(NamedNode node, {bool hint: true}) {
    var element = new AnchorElement()
      ..classes.add(CssClass.reference)
      ..text = getShortName(node)
      ..onClick.listen((e) {
        ui.codeView.showObject(node);
      });
    if (hint) {
      element.title = getLongName(node);
    }
    append(element);
  }

  void appendLocation(StorageLocation location) {
    if (location.owner == shownObject?.reference) {
      appendText('v${location.index}');
    } else {
      appendReference(location.owner.node);
      appendText('/v${location.index}');
    }
  }

  void appendValue(Value value) {
    if (value.baseClass == null) {
      appendText(value.isAlwaysNull ? 'Null' : 'Nothing');
    } else {
      appendPush(new SpanElement()
        ..onMouseMove.listen(ui.typeView.showValueOnEvent(value)));
      appendReference(value.baseClass, hint: false);
      appendText(value.hasExactBaseClass ? '!' : '+');
      if (value.canBeNull) {
        appendText('?');
      }
      pop();
    }
  }

  String getShortName(NamedNode node) {
    if (node is Class) {
      return node.name;
    } else if (node is Member) {
      var class_ = node.enclosingClass;
      if (class_ != null) {
        return '${class_.name}.${node.name.name}';
      }
      return node.name.name;
    } else if (node is Library) {
      return node.name ?? '${node.importUri}';
    } else {
      throw 'Unexpected node: ${node.runtimeType}';
    }
  }

  String getLongName(NamedNode node) {
    return '$node';
  }
}

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
