// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.ui_component;

import 'dart:async';

typedef void AnimationCallback();

/// A base class for high-level UI objects that needs to update its HTML DOM
/// when some state has changed.
///
/// Calling [invalidate] on a UI component will cause its [buildHtml] method
/// to be invoked before returning to the event loop (using a microtask).
///
/// UI components manipulate their DOM in three stages:
///
/// 1. Static: The part of the DOM is hand-written in the .html file.
///    These are given as arguments in the constructor.
///
/// 2. Constructed: The part of the DOM built by [buildHtml].
///    This is rebuilt from scratch after [invalidate] has been called.
///
/// 3. Animated: Small actions based on DOM built above, such as animations,
///    scrolling a specific part into view, or highlighting based on cursor
///    movement.  These are registered using [addOneShotAnimation].
///
abstract class UIComponent {
  static const int _dirtyBit = 1 << 0;
  static const int _rebuildingBit = 1 << 1;
  static const int _microtaskScheduledBit = 1 << 2;

  int _state = 0;
  final List<AnimationCallback> _oneShotAnimations = <AnimationCallback>[];

  UIComponent() {
    invalidate();
  }

  bool get isRebuilding => _state & _rebuildingBit != 0;

  /// Ensures the HTML DOM for this component gets rebuild before returning to
  /// the event loop.
  void invalidate() {
    if (isRebuilding) {
      throw 'Cannot invalidate UI while updating UI';
    }
    _state |= _dirtyBit;
    _ensureMicrotaskScheduled();
  }

  void addOneShotAnimation(AnimationCallback callback) {
    if (isRebuilding) {
      throw 'Cannot register animation while updating UI';
    }
    _oneShotAnimations.add(callback);
    _ensureMicrotaskScheduled();
  }

  void _ensureMicrotaskScheduled() {
    if (_state & _microtaskScheduledBit == 0) {
      _state |= _microtaskScheduledBit;
      scheduleMicrotask(_microtaskCallback);
    }
  }

  void _microtaskCallback() {
    try {
      _state |= _rebuildingBit;
      if (_state & _dirtyBit != 0) {
        buildHtml();
      }
      for (var animation in _oneShotAnimations) {
        animation();
      }
    } finally {
      _oneShotAnimations.clear();
      _state = 0; // Not dirty, not rebuilding, and microtask not scheduled.
    }
  }

  /// Builds the HTML DOM for this UI component.
  ///
  /// This should not be called directly - call [invalidate] to ensure this gets
  /// called at the right time.
  void buildHtml();
}
