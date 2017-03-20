// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.html_buffer;

import 'dart:html';
import 'dart:html' as html;

import 'package:kernel/ast.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';

import 'laboratory.dart';
import 'laboratory_ui.dart';

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
  final Reference reference;

  /// Click events registered by this buffer will register [currentConstraint]
  /// as the point of origin to which we should return when the browser's back
  /// button is pressed.
  Constraint currentConstraint;

  KernelHtmlBuffer(Element root, this.reference) : super(root);

  void appendReference(Reference reference) {
    append(new AnchorElement()
      ..classes.add(CssClass.reference)
      ..text = getShortName(reference.node)
      ..title = getLongName(reference.node)
      ..onClick.listen((e) {
        ui.codeView.showObject(reference);
      }));
  }

  void appendLocation(StorageLocation location) {
    if (location.owner != reference) {
      appendReference(location.owner);
      appendText('/');
    }
    var locationName = 'v${location.index}';
    var element = new SpanElement()
      ..text = locationName
      ..classes.add(CssClass.storageLocation)
      ..onMouseMove.listen(ui.typeView.showStorageLocationOnEvent(location))
      ..onClick.listen(ui.backtracker
          .investigateStorageLocationOnEvent(location, currentConstraint));
    if (location.owner == reference) {
      element.classes.add(locationName);
    }
    append(element);
  }

  void appendValue(Value value) {
    if (value.baseClass == null) {
      appendText(value.isAlwaysNull ? 'Null' : 'Nothing');
    } else {
      appendPush(new SpanElement()
        ..onMouseMove.listen(ui.typeView.showValueOnEvent(value)));
      appendText(getShortName(value.baseClass));
      appendText(value.hasExactBaseClass ? '!' : '+');
      if (value.canBeNull) {
        appendText('?');
      }
      pop();
    }
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
