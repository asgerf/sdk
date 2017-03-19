// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.ui_component;

import 'dart:async';

typedef void Callback();

/// A base class for high-level UI objects that needs to update its HTML DOM
/// when some state has changed.
///
/// Calling [invalidate] on a UI component will cause its [buildHtml] method
/// to be invoked before returning to the event loop (using a microtask).
abstract class UIComponent {
  _State _state = _State.clean;
  final List<Callback> oneShotCallbacks = <Callback>[];
  bool _microtaskScheduled = false;

  UIComponent() {
    invalidate();
  }

  /// Ensures the HTML DOM for this component gets rebuild before returning to
  /// the event loop.
  void invalidate() {
    switch (_state) {
      case _State.clean:
        _state = _State.dirty;
        if (!_microtaskScheduled) {
          _microtaskScheduled = true;
          scheduleMicrotask(_onBuildCallback);
        }
        return;

      case _State.dirty:
        return;

      case _State.rebuilding:
        throw 'UI invalidated while building itself';
    }
  }

  void oneShotCallback(Callback callback) {
    oneShotCallbacks.add(callback);
    if (!_microtaskScheduled) {
      _microtaskScheduled = true;
      scheduleMicrotask(_onBuildCallback);
    }
  }

  void _onBuildCallback() {
    try {
      var oldState = _state;
      _state = _State.rebuilding;
      if (oldState == _State.dirty) {
        buildHtml();
      }
      for (var callback in oneShotCallbacks) {
        callback();
      }
    } finally {
      _state = _State.clean;
      _microtaskScheduled = false;
    }
  }

  /// Builds the HTML DOM for this UI component.
  ///
  /// This should not be called directly - call [invalidate] to ensure this gets
  /// called at the right time.
  void buildHtml();
}

enum _State { clean, dirty, rebuilding }
