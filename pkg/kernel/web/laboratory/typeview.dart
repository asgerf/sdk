library kernel.laboratory.typeview;

import 'dart:html';

import 'laboratory_ui.dart';
import 'package:kernel/ast.dart';

import 'laboratory.dart';
import 'package:kernel/inference/value.dart';

class TypeView {
  final DivElement containerElement;
  final Element expressionKindElement;
  final TableElement tableElement;

  TypeView(
      this.containerElement, this.expressionKindElement, this.tableElement);

  void hide() {
    containerElement.style.visibility = "hidden";
  }

  void showAt(int left, int top) {
    containerElement.style
      ..visibility = 'visible'
      ..left = '${left}px'
      ..top = '${top}px';
  }

  String getPrettyClassName(Class class_) {
    if (class_ == null) return 'no base class';
    var library = class_.enclosingLibrary;
    if (library.name != null) {
      return '${library.name}.${class_.name}';
    } else {
      return class_.name;
    }
  }

  bool showTypeOfExpression(NamedNode owner, Expression expression) {
    if (constraintSystem == null) return false;
    expressionKindElement.text = '${expression.runtimeType}';
    tableElement.children.clear();
    if (expression.inferredValueOffset == -1) {
      var row = new TableRowElement();
      row.append(new TableCellElement()
        ..text = 'The value cannot be shown here because no inference location '
            'was stored on the expression');
      tableElement.append(row);
    } else {
      var location = constraintSystem.getStorageLocation(
          owner.reference, expression.inferredValueOffset);
      var value = report.getValue(location, report.endOfTime);
      // Add base class row
      {
        var row = new TableRowElement();

        row.append(new TableCellElement()
          ..text = getPrettyClassName(value.baseClass)
          ..classes.add(CssClass.valueBaseClass)
          ..colSpan = 2);

        tableElement.append(row);
      }
      // Add flag rows
      for (int i = 0; i < ValueFlags.numberOfFlags; ++i) {
        var row = new TableRowElement();

        bool hasFlag = (value.flags & (1 << i) != 0);
        var hasFlagCss = hasFlag ? CssClass.valueFlagOn : CssClass.valueFlagOff;

        String flagName = ValueFlags.flagNames[i];
        row.append(new TableCellElement()
          ..text = flagName
          ..classes.add(CssClass.valueFlagLabel));

        var hasFlagText = hasFlag ? 'yes' : 'no';
        row.append(new TableCellElement()..text = hasFlagText);
        row.classes.add(hasFlagCss);

        tableElement.append(row);
      }
    }
    containerElement.style.visibility = 'visible';
    return true;
  }
}
