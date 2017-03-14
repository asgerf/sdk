// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.html_buffer;

import 'dart:html';
import 'dart:html' as html;

import 'package:kernel/ast.dart';
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
  final NamedNode shownObject;

  KernelHtmlBuffer(Element root, this.shownObject) : super(root);

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
