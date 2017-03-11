// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory_ui;

import 'dart:html';
import 'codeview.dart';
import 'searchbox.dart';

// This library contains bindings to the HTML file, possibly wrapped in a
// higher-level view object.

Element $(x) => document.getElementById(x);

class UI {
  FileUploadInputElement reportFileInput = $('report-file-input');

  FileUploadInputElement kernelFileInput = $('kernel-file-input');

  ButtonElement reloadButton = $('reload-button');

  DivElement debugBox = $('debug-box');

  CodeView codeView = new CodeView(
      $('code-view'), $('code-view-title'), $('code-view-filename'));

  SearchBox searchBox = new SearchBox($('search-input'),
      $('search-input-suggestions'), $('search-input-select'));
}

// We use a singleton class so that all fields get initialized deterministically
// instead of on first use.
UI ui = new UI();
