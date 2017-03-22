// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.type_view;

import 'dart:html';

import 'package:kernel/ast.dart';
import 'package:kernel/inference/storage_location.dart';
import 'package:kernel/inference/value.dart';

import 'laboratory.dart';
import 'laboratory_ui.dart';
import 'view.dart';

class TypeView {
  final DivElement containerElement;
  final Element expressionKindElement;
  final Element storageLocationNameElement;
  final Element warningElement;
  final TableElement tableElement;

  Element highlightedElement;
  String relatedElementCssClass;

  TypeView(this.containerElement, this.expressionKindElement,
      this.storageLocationNameElement, this.warningElement, this.tableElement) {
    document.body.onMouseMove.listen((e) {
      hide();
    });
  }

  void hide() {
    containerElement.style.visibility = "hidden";
    unsetHighlightedElement();
    unsetRelatedElements();
  }

  void showAt(int left, int top) {
    containerElement.style
      ..visibility = 'visible'
      ..left = '${left}px'
      ..top = '${top + 16}px';
  }

  void setHighlightedElement(Element element) {
    if (highlightedElement != element) {
      unsetHighlightedElement();
      highlightedElement = element;
      element.classes.add(CssClass.highlightedToken);
    }
  }

  void unsetHighlightedElement() {
    highlightedElement?.classes?.remove(CssClass.highlightedToken);
    highlightedElement = null;
  }

  void unsetRelatedElements() {
    if (relatedElementCssClass != null) {
      for (var elm in document.getElementsByClassName(relatedElementCssClass)) {
        if (elm is Element) {
          elm.classes.remove(CssClass.relatedElement);
        }
      }
      relatedElementCssClass = null;
    }
  }

  void setRelatedElementsFromCssClass(String cssClass) {
    if (cssClass == relatedElementCssClass) return;
    unsetRelatedElements();
    relatedElementCssClass = cssClass;
    for (var elm in document.getElementsByClassName(cssClass)) {
      if (elm is Element) {
        elm.classes.add(CssClass.relatedElement);
      }
    }
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

  void _showTable(List<String> flagLabels, List<TypeViewColumn> columns) {
    assert(columns.isNotEmpty);
    const String arrow = '→';
    tableElement.children.clear();
    var firstColumn = columns.first;
    // Add base class row
    {
      var row = new TableRowElement();

      // The current base class
      {
        row.append(new TableCellElement()
          ..text = getPrettyClassName(firstColumn.baseClass)
          ..classes.add(CssClass.valueBaseClass)
          ..colSpan = 2);
      }

      // Add future base classes
      var previous = firstColumn;
      for (var column in columns.skip(1)) {
        String text = column.baseClass == previous.baseClass
            ? ''
            : '$arrow ' + getPrettyClassName(column.baseClass);
        var cell = new TableCellElement()..text = text;
        if (column.cssClass != null) {
          cell.classes.add(column.cssClass);
        }
        row.append(cell);
        previous = column;
      }

      tableElement.append(row);
    }
    // Add flag rows
    int flagIndex = -1;
    for (String flagName in flagLabels) {
      // Add a section header if the name starts with `---`
      if (flagName.startsWith(flagSeparator)) {
        var row = new TableRowElement()
          ..classes.add(CssClass.typeViewFlagSeparator)
          ..append(new TableCellElement()
            ..colSpan = 1 + columns.length
            ..text = flagName.substring(flagSeparator.length));
        tableElement.append(row);
        continue;
      }
      ++flagIndex;

      int mask = 1 << flagIndex;

      var row = new TableRowElement();
      row.append(new TableCellElement()
        ..text = flagName
        ..classes.add(CssClass.valueFlagLabel));

      bool hasFlag = firstColumn.flags & mask != 0;
      var hasFlagCss = hasFlag ? CssClass.valueFlagOn : CssClass.valueFlagOff;
      var hasFlagText = hasFlag ? 'yes' : 'no';

      row.append(new TableCellElement()..text = hasFlagText);
      row.classes.add(hasFlagCss);

      var previous = firstColumn;
      for (var column in columns.skip(1)) {
        if (column.flags & mask == previous.flags & mask) {
          row.append(new TableCellElement());
          continue;
        }
        // At this point the future value should have the flag, because flags
        // can only change from no to yes, but if there is a bug in the solver
        // it should be evident when viewing the report, so just show the data.
        bool hasFlag = column.flags & mask != 0;
        String text = hasFlag ? '$arrow yes' : '$arrow no';
        var cell = new TableCellElement()..text = text;
        if (column.cssClass != null) {
          cell.classes.add(column.cssClass);
        }
        row.append(cell);
        previous = column;
      }

      tableElement.append(row);
    }
  }

  void _showValue(Value value) {
    _showTable(ValueFlags.flagNames, [new TypeViewColumn.value(value)]);
  }

  static const String flagSeparator = '---';

  static final List<String> storageLocationLabels = <String>[]
    ..addAll(ValueFlags.flagNames)
    ..add('${flagSeparator} Outgoing')
    ..add('leadsToEscape');

  Value getLocationValue(StorageLocation location, int time) {
    Value value = report.getValue(location, time);
    while (location.parameterLocation != null) {
      location = constraintSystem.getBoundLocation(location.parameterLocation);
      value = valueLattice.joinValues(value, report.getValue(location, time));
    }
    return value;
  }

  TypeViewColumn getLocationColumn(StorageLocation location, int time,
      [String cssClass]) {
    var value = getLocationValue(location, time);
    bool leadsToEscape = report.leadsToEscape(location, time);
    int extraFlags = leadsToEscape ? 1 : 0;
    int flags = value.flags | (extraFlags << ValueFlags.numberOfFlags);
    return new TypeViewColumn(value.baseClass, flags, cssClass);
  }

  void _showLocation(StorageLocation location) {
    if (!ui.backtracker.isBacktracking) {
      _showTable(storageLocationLabels,
          [getLocationColumn(location, report.endOfTime)]);
      return;
    }
    int currentTime = ui.backtracker.currentTimestamp;
    int previousTime = currentTime - 1;
    List<TypeViewColumn> columns = [
      getLocationColumn(location, previousTime),
      getLocationColumn(location, currentTime, CssClass.typeViewNextValue),
      getLocationColumn(location, report.endOfTime, CssClass.typeViewFinalValue)
    ];
    _showTable(storageLocationLabels, columns);
  }

  bool showTypeOfExpression(
      Reference owner, TreeNode node, int inferredValueOffset) {
    if (constraintSystem == null) return false;
    expressionKindElement.text = '${node.runtimeType}';
    if (isDynamicCall(node)) {
      warningElement.text = 'Dynamic call';
      warningElement.style.display = 'block';
    } else {
      warningElement.style.display = 'none';
    }
    tableElement.children.clear();
    if (inferredValueOffset == -1) {
      storageLocationNameElement.text = '';
      var row = new TableRowElement();
      row.append(new TableCellElement()
        ..text = 'The value cannot be shown here because no inference location '
            'was stored on the node');
      tableElement.append(row);
      unsetRelatedElements();
    } else {
      var location =
          constraintSystem.getStorageLocation(owner, inferredValueOffset);
      _showLocation(location);
      var locationName = 'v${location.index}';
      storageLocationNameElement.text = locationName;
      setRelatedElementsFromCssClass(locationName);
    }
    containerElement.style.visibility = 'visible';
    return true;
  }

  void showValue(Value value) {
    _showValue(value);
    unsetRelatedElements();
    expressionKindElement.text = 'Value';
    storageLocationNameElement.text = '';
    containerElement.style.visibility = 'visible';
    warningElement.style.display = 'none';
  }

  void showStorageLocation(StorageLocation location) {
    _showLocation(location);
    if (location.owner == view.reference) {
      setRelatedElementsFromCssClass('v${location.index}');
    } else {
      unsetRelatedElements();
    }
    expressionKindElement.text = 'StorageLocation';
    storageLocationNameElement.text = '';
    containerElement.style.visibility = 'visible';
    warningElement.style.display = 'none';
  }

  /// Returns an event listener that will open the type view at the cursor and
  /// show details about [value].
  ///
  /// This event listener should be registered on the `mouseMove` event.  It is
  /// generally not necessary to register the `mouseOut` event since the body's
  /// `mouseMove` event hides the type view again.
  MouseEventListener showValueOnEvent(Value value) {
    return (MouseEvent ev) {
      ev.stopPropagation();
      showAt(ev.page.x, ev.page.y);
      if (highlightedElement != ev.target) {
        // Only rebuild the DOM if the highlighted element changed.
        showValue(value);
        setHighlightedElement(ev.target);
      }
    };
  }

  /// Returns an event listener that will open the type view at the cursor and
  /// show details about the given storage location.
  ///
  /// This event listener should be registered on the `mouseMove` event.  It is
  /// generally not necessary to register the `mouseOut` event since the body's
  /// `mouseMove` event hides the type view again.
  MouseEventListener showStorageLocationOnEvent(StorageLocation location) {
    return (MouseEvent ev) {
      ev.stopPropagation();
      showAt(ev.page.x, ev.page.y);
      if (highlightedElement != ev.target) {
        // Only rebuild the DOM if the highlighted element changed.
        showStorageLocation(location);
        setHighlightedElement(ev.target);
      }
    };
  }
}

typedef void MouseEventListener(MouseEvent ev);

class TypeViewColumn {
  final Class baseClass;
  final int flags;
  String cssClass;

  TypeViewColumn(this.baseClass, this.flags, [this.cssClass]);
  TypeViewColumn.value(Value value, [this.cssClass])
      : baseClass = value.baseClass,
        flags = value.flags;
}
