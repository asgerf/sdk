library kernel.laboratory.typeview;

import 'dart:html';

import 'package:kernel/ast.dart';

import 'laboratory.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/extractor/binding.dart';
import 'package:kernel/inference/value.dart';

class TypeView {
  final DivElement viewElement;

  TypeView(this.viewElement);

  void setPosition(int left, int top) {
    viewElement.style
      ..left = '$left px'
      ..top = '$top px';
  }

  void showTypesOnLine(Source source, NamedNode owner, int lineIndex) {
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
      viewElement.children
          .add(new DivElement()..text = '${expression.runtimeType} :: $value');
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
