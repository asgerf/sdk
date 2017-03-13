library kernel.laboratory.typeview;

import 'dart:html';

import 'package:kernel/ast.dart';

import 'laboratory.dart';
import 'package:kernel/inference/value.dart';

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

  void showTypesOnLine(Source source, NamedNode owner, int lineIndex) {
    if (constraintSystem == null) return;
    if (owner is! Member) return;
    int from = source.lineStarts[lineIndex];
    int to = source.getEndOfLine(lineIndex);
    var expressions = <Expression>[];
    owner.accept(new ExpressionCollector(from, to, expressions));

    var cluster = constraintSystem.getCluster(owner.reference);
    viewElement.children.clear();
    for (var expression in expressions) {
      Value value = null;
      if (expression.inferredValueOffset != -1) {
        var location =
            cluster.getStorageLocation(expression.inferredValueOffset);
        value = report.getValue(location, report.endOfTime);
      }
      var expressionKindSpan = new SpanElement()
        ..classes.add('expression-kind')
        ..text = '${expression.runtimeType}';
      var typeSpan = new SpanElement()
        ..classes.add('type')
        ..text = '$value';
      var div = new DivElement()
        ..append(expressionKindSpan)
        ..appendText(' :: ')
        ..append(typeSpan);
      viewElement.children.add(div);
    }

    if (isEmpty) {
      hide();
    }
  }
}

class ExpressionCollector extends RecursiveVisitor {
  final int from, to;
  final List<Expression> result;

  ExpressionCollector(this.from, this.to, this.result);

  bool isInRange(TreeNode node) {
    if (node.fileOffset == TreeNode.noOffset) return false;
    return from <= node.fileOffset && node.fileOffset < to;
  }

  @override
  defaultExpression(Expression node) {
    if (isInRange(node)) {
      result.add(node);
    }
    node.visitChildren(this);
  }
}
