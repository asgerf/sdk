// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.ui;

import 'dart:html';

import 'code_view.dart';
import 'constraint_view.dart';
import 'search_box.dart';
import 'backtracker.dart';
import 'type_view.dart';

// This library contains bindings to the HTML file, possibly wrapped in a
// higher-level view object.

Element $(String x) => document.getElementById(x);

class UI {
  BodyElement body = document.body;

  DivElement fileSelectDiv = $('file-select');
  FileUploadInputElement reportFileInput = $('report-file-input');
  FileUploadInputElement kernelFileInput = $('kernel-file-input');
  ButtonElement reloadButton = $('reload-button');

  DivElement debugBox = $('debug-box');

  DivElement mainContentDiv = $('main-content');

  InputElement trackEscapeCheckbox = $('track-escape-checkbox');

  CodeView codeView =
      new CodeView($('code-view-body'), $('code-view-filename'));

  SearchBox searchBox = new SearchBox($('search-input'),
      $('search-input-suggestions'), $('search-input-select'));

  TypeView typeView = new TypeView(
      $('type-view-container'),
      $('type-view-expression-kind'),
      $('type-view-storage-location-name'),
      $('type-view-warning'),
      $('type-view-table'));

  ConstraintView constraintView = new ConstraintView(
      $('constraint-view-table'), $('constraint-view-header'));

  Backtracker backtracker = new Backtracker($('backtracker-container'),
      $('backtracker-progress'), $('backtracker-reset-button'));
}

// We use a singleton class (as opposed to static fields) so that all fields
// are initialized deterministically instead of on first use.
UI ui = new UI();

class CssClass {
  static const String codeLine = 'code-line';
  static const String codeLineWithConstraints = 'code-line-with-constraints';
  static const String constraintEscape = 'constraint-escape';
  static const String constraintFocused = 'constraint-focused';
  static const String constraintGuard = 'constraint-guard';
  static const String constraintLabel = 'constraint-label';
  static const String constraintLineNumber = 'constraint-line-number';
  static const String highlightedToken = 'highlighted-token';
  static const String reference = 'reference';
  static const String relatedElement = 'related-element';
  static const String right = 'right';
  static const String storageLocation = 'storage-location';
  static const String typeViewBaseClass = 'type-view-base-class';
  static const String typeViewFinalValue = 'type-view-final-value';
  static const String typeViewFlagLabel = 'type-view-flag-label';
  static const String typeViewFlagOff = 'type-view-flag-off';
  static const String typeViewFlagOn = 'type-view-flag-on';
  static const String typeViewFlagSeparator = 'type-view-flag-separator';
  static const String typeViewNextValue = 'type-view-next-value';
}
