// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.searchbox;

import 'dart:async';
import 'dart:html';

import 'package:kernel/ast.dart';

import 'keycodes.dart';
import 'laboratory.dart';

class SearchBox {
  static final RegExp patternSeparator = new RegExp(r' |\.|::');

  final TextInputElement inputElement;
  final DivElement suggestionBoxContainer;
  final SelectElement suggestionBoxSelect;
  Timer hideSuggestionBoxTimer;

  bool suggestionsAreVisible = false;
  List<NamedNode> suggestedNodes = <NamedNode>[];

  SearchBox(this.inputElement, this.suggestionBoxContainer,
      this.suggestionBoxSelect) {
    inputElement.onInput.listen(onInputChanged);
    inputElement.onFocus.listen(onInputFocused);
    inputElement.onBlur.listen(onBlur);
    inputElement.onKeyDown.listen(onInputKeyDown);
    suggestionBoxSelect.onBlur.listen(onBlur);
    suggestionBoxSelect.onKeyDown.listen(onSelectKeyDown);
    suggestionBoxSelect.onDoubleClick.listen(onSelectDoubleClick);
    hideSuggestionBox();
  }

  void onInputChanged(Event ev) {
    suggestionBoxSelect.children.clear();
    if (tryPopulateSuggestionBox()) {
      showSuggestionBox();
    } else {
      hideSuggestionBox();
    }
  }

  void onInputFocused(Event ev) {
    if (suggestionBoxSelect.children.isNotEmpty) {
      showSuggestionBox();
      suggestionBoxSelect.selectedIndex = -1;
    }
    inputElement.select();
  }

  /// Event handler that fires when the text box or the suggestion box loses
  /// focus.
  void onBlur(Event ev) {
    // If focus was moved from the text box to the suggestion box, we should not
    // hide the suggestion box.  Unfortunately the timing of the blur event is
    // such that we can't yet see which element is becoming focused.
    // We use a zero-duration timer to delay the check.
    hideSuggestionBoxTimer ??= new Timer(new Duration(), () {
      hideSuggestionBoxTimer = null;
      var focusedElement = document.activeElement;
      if (focusedElement == inputElement ||
          suggestionBoxContainer.contains(focusedElement)) {
        return;
      }
      hideSuggestionBox();
    });
  }

  void onInputKeyDown(KeyboardEvent ev) {
    if (ev.which == KeyCodes.downArrow && suggestionsAreVisible) {
      ev.stopPropagation();
      suggestionBoxSelect.focus();
      suggestionBoxSelect.selectedIndex = 0;
    } else if (ev.which == KeyCodes.escape) {
      ev.stopPropagation();
      hideSuggestionBox();
    } else if (ev.which == KeyCodes.enter && suggestionsAreVisible) {
      ev.stopPropagation();
      // Pick the first suggestion.  To visually indicate what happened,
      // select it in the UI for 50 ms before closing the suggestion box.
      suggestionBoxSelect.focus();
      suggestionBoxSelect.selectedIndex = 0;
      new Timer(new Duration(milliseconds: 50), () {
        presentSelectedElement();
      });
    }
  }

  void onSelectKeyDown(KeyboardEvent ev) {
    if (ev.which == KeyCodes.upArrow &&
        suggestionBoxSelect.selectedIndex == 0) {
      ev.stopPropagation();
      inputElement.focus();
    } else if (ev.which == KeyCodes.escape) {
      ev.stopPropagation();
      hideSuggestionBox();
    } else if (ev.which == KeyCodes.enter) {
      presentSelectedElement();
    }
  }

  void onSelectDoubleClick(Event ev) {
    presentSelectedElement();
  }

  void presentSelectedElement() {
    var index = suggestionBoxSelect.selectedIndex;
    if (index >= 0 && index < suggestedNodes.length) {
      ui.codeView.showObject(suggestedNodes[index]);
    }
    hideSuggestionBox();
  }

  bool tryPopulateSuggestionBox() {
    if (program == null) return false;
    var matcher = new FuzzyFinder(inputElement.value.split(patternSeparator));
    matcher.scanProgram(program);
    if (matcher.suggestedNodes.isEmpty) return false;
    suggestedNodes = matcher.suggestedNodes.take(10).toList();
    for (var node in suggestedNodes) {
      var listItem = new OptionElement()..text = '$node';
      suggestionBoxSelect.children.add(listItem);
    }
    return true;
  }

  void hideSuggestionBox() {
    suggestionBoxContainer.style.visibility = "hidden";
    hideSuggestionBoxTimer?.cancel();
    hideSuggestionBoxTimer = null;
    suggestionsAreVisible = false;
  }

  void showSuggestionBox() {
    hideSuggestionBoxTimer?.cancel();
    hideSuggestionBoxTimer = null;
    var rect = inputElement.getBoundingClientRect();
    suggestionBoxContainer.style
      ..left = '${rect.left}px'
      ..top = '${rect.bottom}px'
      ..visibility = "visible";
    suggestionsAreVisible = true;
  }

  void onProgramLoaded() {}
}

class Suggestion implements Comparable<Suggestion> {
  final NamedNode node;
  final int penalty;

  Suggestion(this.node, this.penalty);

  int compareTo(Suggestion other) => penalty.compareTo(other.penalty);
}

class FuzzyFinder {
  final List<String> patterns;
  final List<RegExp> regexps = <RegExp>[];
  final List<Suggestion> suggestions = <Suggestion>[];

  Iterable<NamedNode> get suggestedNodes => suggestions.map((s) => s.node);

  static const int maximumCandidates = 1000;

  bool get hasMaximumCandidates => suggestedNodes.length >= maximumCandidates;

  /// Matches characters that should be escaped in the regular expression.
  static final RegExp escapeRegExp = new RegExp(r'[^a-zA-Z0-9$_]');

  String escapeChar(String char) {
    return escapeRegExp.hasMatch(char) ? '\\$char' : char;
  }

  FuzzyFinder(this.patterns) {
    for (var pattern in patterns) {
      if (pattern.isEmpty) continue;
      regexps.add(new RegExp(pattern.split('').map(escapeChar).join('.*'),
          caseSensitive: false));
    }
  }

  int computeMatchPenalty(String name, String pattern) {
    // In general we can compare the match against the pattern, but simply
    // favoring short results actually works pretty well.
    // The user can always write a longer pattern to get the results with longer
    // names.
    return name.length;
  }

  void scanProgram(Program program) {
    if (regexps.isEmpty) return;
    for (var library in program.libraries) {
      scanLibrary(library);
      if (hasMaximumCandidates) break;
    }
    suggestions.sort();
  }

  void scanLibrary(Library library) {
    int regexpIndex = 0;
    int penalty = 0;
    if (library.name != null && regexps[0].hasMatch(library.name)) {
      ++regexpIndex;
      penalty = computeMatchPenalty(library.name, patterns[0]);
      if (regexps.length == 1) {
        suggestions.add(new Suggestion(library, penalty));
        return;
      }
    }
    if (library.importUri.scheme == 'dart') {
      // Slightly disfavor core library results.  For example, vm_service::main
      // should occur after the application's own main method.
      penalty += 1;
    }
    for (var class_ in library.classes) {
      scanClass(class_, regexpIndex, penalty);
      if (hasMaximumCandidates) break;
    }
    if (regexpIndex + 1 == regexps.length) {
      var regexp = regexps[regexpIndex];
      var pattern = patterns[regexpIndex];
      for (var field in library.fields) {
        scanMember(field, regexp, pattern, penalty);
        if (hasMaximumCandidates) break;
      }
      for (var procedure in library.procedures) {
        scanMember(procedure, regexp, pattern, penalty);
        if (hasMaximumCandidates) break;
      }
    }
  }

  void scanClass(Class class_, int regexpIndex, int penalty) {
    assert(regexpIndex < regexps.length);
    if (regexps[regexpIndex].hasMatch(class_.name)) {
      penalty += computeMatchPenalty(class_.name, patterns[regexpIndex]);
      ++regexpIndex;
      if (regexpIndex == regexps.length) {
        suggestions.add(new Suggestion(class_, penalty));
        return;
      }
    }
    if (regexpIndex + 1 == regexps.length) {
      var regexp = regexps[regexpIndex];
      var pattern = patterns[regexpIndex];
      for (var member in class_.members) {
        scanMember(member, regexp, pattern, penalty);
        if (hasMaximumCandidates) break;
      }
    }
  }

  void scanMember(Member member, RegExp regexp, String pattern, int penalty) {
    var name = member.name.name;
    if (regexp.hasMatch(name)) {
      penalty += computeMatchPenalty(name, pattern);
      // Ensure members are listed below classes with the same name.
      penalty += 1;
      suggestions.add(new Suggestion(member, penalty));
    }
  }
}
