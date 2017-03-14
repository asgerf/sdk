// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.ui;

import 'constraint_view.dart';
import 'dart:html';

import 'code_view.dart';
import 'search_box.dart';
import 'type_view.dart';

// This library contains bindings to the HTML file, possibly wrapped in a
// higher-level view object.

Element $(x) => document.getElementById(x);

class UI {
  BodyElement body = document.body;

  FileUploadInputElement reportFileInput = $('report-file-input');

  FileUploadInputElement kernelFileInput = $('kernel-file-input');

  ButtonElement reloadButton = $('reload-button');

  DivElement debugBox = $('debug-box');

  CodeView codeView = new CodeView($('code-view'), $('code-view-filename'));

  SearchBox searchBox = new SearchBox($('search-input'),
      $('search-input-suggestions'), $('search-input-select'));

  TypeView typeView = new TypeView(
      $('type-view'), $('type-view-expression-kind'), $('type-view-table'));

  ConstraintView constraintView = new ConstraintView($('constraint-view'));
}

// We use a singleton class (as opposed to static fields) so that all fields
// are initialized deterministically instead of on first use.
UI ui = new UI();

class CssClass {
  static const String highlightedToken = 'highlighted-token';
  static const String valueBaseClass = 'value-base-class';
  static const String valueBaseClassLabel = 'value-base-class-label';
  static const String valueFlagLabel = 'value-flag-label';
  static const String valueFlagOn = 'value-flag-on';
  static const String valueFlagOff = 'value-flag-off';
  static const String reference = 'reference';
  static const String constraintLabel = 'constraint-label';
}
