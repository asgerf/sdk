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

class ConstraintView {
  final DivElement containerElement;
  ConstraintFormatter constraintFormatter;
  NamedNode shownObject;

  HtmlBuffer buffer;

  ConstraintView(this.containerElement) {
    constraintFormatter = new ConstraintFormatter(this);
  }

  void hide() {
    containerElement.style.visibility = 'hidden';
  }

  void show(NamedNode shownObject) {
    this.shownObject = shownObject;
    containerElement.style.visibility = 'visible';
    containerElement.children.clear();
    var cluster = constraintSystem.getCluster(shownObject.reference);
    if (cluster == null) return;
    buffer = new HtmlBuffer(containerElement);
    for (var constraint in cluster.constraints) {
      buffer.appendPush(new DivElement());
      _appendConstraint(constraint);
      buffer.pop();
    }
  }

  void _appendText(String text) {
    buffer.appendText(text);
  }

  void _appendClass(Class node) {
    _appendText('$node');
  }

  String getShortName(NamedNode node) {
    if (node is Class) {
      return node.name;
    } else if (node is Member) {
      var class_ = node.enclosingClass;
      if (class_ != null) {
        return '${class_.name}.${node.name}';
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

  void _appendReference(NamedNode node) {
    buffer.append(new AnchorElement()
      ..classes.add(CssClass.reference)
      ..text = getShortName(node)
      ..title = getLongName(node)
      ..onClick.listen((e) {
        ui.codeView.showObject(node);
      }));
  }

  void _appendConstraint(Constraint constraint) {
    constraint.accept(constraintFormatter);
  }

  void _appendLocation(StorageLocation location) {
    if (location.owner == shownObject.reference) {
      buffer.appendText('v${location.index}');
    } else {
      _appendReference(location.owner.node);
      _appendText('/v${location.index}');
    }
  }

  void _appendValue(Value value) {
    _appendText('$value');
  }
}

class ConstraintFormatter extends ConstraintVisitor<Null> {
  final ConstraintView main;

  ConstraintFormatter(this.main);

  HtmlBuffer get buffer => main.buffer;

  @override
  visitEscapeConstraint(EscapeConstraint constraint) {
    main
      .._appendText('Escape ')
      .._appendLocation(constraint.escaping);
  }

  @override
  visitSubtypeConstraint(SubtypeConstraint constraint) {
    main
      .._appendLocation(constraint.source)
      .._appendText(' -> ')
      .._appendLocation(constraint.destination);
  }

  @override
  visitTypeArgumentConstraint(TypeArgumentConstraint constraint) {
    main._appendText('TypeArgumentConstraint');
  }

  @override
  visitValueConstraint(ValueConstraint constraint) {
    main
      .._appendValue(constraint.value)
      .._appendText(' -> ')
      .._appendLocation(constraint.destination);
  }
}
