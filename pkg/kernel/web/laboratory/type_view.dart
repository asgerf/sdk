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

  void _setShownValue(Value value) {
    tableElement.children.clear();
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

  bool showTypeOfExpression(
      NamedNode owner, TreeNode node, int inferredValueOffset) {
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
      var location = constraintSystem.getStorageLocation(
          owner.reference, inferredValueOffset);
      var value = report.getValue(location, ui.backtracker.currentTimestamp);
      _setShownValue(value);
      var locationName = 'v${location.index}';
      storageLocationNameElement.text = locationName;
      setRelatedElementsFromCssClass(locationName);
    }
    containerElement.style.visibility = 'visible';
    return true;
  }

  void showValue(Value value) {
    _setShownValue(value);
    unsetRelatedElements();
    expressionKindElement.text = 'Value';
    storageLocationNameElement.text = '';
    containerElement.style.visibility = 'visible';
    warningElement.style.display = 'none';
  }

  void showStorageLocation(StorageLocation location) {
    var value = report.getValue(location, ui.backtracker.currentTimestamp);
    _setShownValue(value);
    if (location.owner == view.shownObject.reference) {
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
