library kernel.laboratory.typeview;

import 'dart:html';

import 'package:kernel/ast.dart';

import 'laboratory.dart';

class TypeView {
  final DivElement viewElement;

  TypeView(this.viewElement);

  void hide() {
    viewElement.style.visibility = "hidden";
  }

  bool get isEmpty => viewElement.children.isEmpty;

  void showAt(int left, int top) {
    if (isEmpty) return;
    viewElement.style
      ..visibility = 'visible'
      ..left = '${left}px'
      ..top = '${top}px';
  }

  bool showTypeOfExpression(NamedNode owner, Expression expression) {
    if (constraintSystem == null) return false;
    String message;
    if (expression.inferredValueOffset == -1) {
      message = 'no offset';
    } else {
      var location = constraintSystem.getStorageLocation(
          owner.reference, expression.inferredValueOffset);
      var value = report.getValue(location, report.endOfTime);
      message = '$value';
    }
    viewElement.children.clear();
    var expressionKindSpan = new SpanElement()
      ..classes.add('expression-kind')
      ..text = '${expression.runtimeType}';
    var typeSpan = new SpanElement()
      ..classes.add('type')
      ..text = '$message';
    var div = new DivElement()
      ..append(expressionKindSpan)
      ..appendText(' :: ')
      ..append(typeSpan);
    viewElement.children.add(div);
    return true;
  }
}
