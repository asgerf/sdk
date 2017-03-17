// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.ui_component;

import 'dart:async';
import 'dart:html';

enum _State { clean, dirty, rebuilding }

abstract class UIComponent {
  final Element root;
  _State _state = _State.clean;

  UIComponent(this.root) {
    invalidate();
  }

  void invalidate() {
    switch (_state) {
      case _State.clean:
        _state = _State.dirty;
        scheduleMicrotask(_onBuildCallback);
        break;

      case _State.dirty:
        return;

      case _State.rebuilding:
        throw 'UI invalidated while building itself';
    }
  }

  void _onBuildCallback() {
    _state = _State.rebuilding;
    buildHtml();
    _state = _State.clean;
  }

  void buildHtml();
}
