library kernel.laboratory.searchbox;

import 'dart:html';
import 'laboratory.dart';

import 'package:kernel/ast.dart';

class SearchBox {
  final TextInputElement inputElement;
  final DivElement suggestionBoxElement;

  SearchBox(this.inputElement, this.suggestionBoxElement) {
    inputElement.onInput.listen(onInputChanged);
  }

  final RegExp patternSeparator = new RegExp(r' |\.|::');

  void onInputChanged(Event ev) {
    suggestionBoxElement.children.clear();
    if (program == null) return;
    var matcher = new FuzzyFinder(inputElement.value.split(patternSeparator));
    matcher.scanProgram(program);
    if (matcher.suggestedNodes.isEmpty) return;
    var list = new UListElement();
    for (var node in matcher.suggestedNodes.take(10)) {
      var listItem = new LIElement()..text = '$node';
      list.children.add(listItem);
    }
    suggestionBoxElement.children.add(list);
  }

  void onProgramLoaded() {
    suggestionBoxElement.children.clear();
  }
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

  static final RegExp sanitizerRegExp = new RegExp(r'[^a-zA-Z0-9_$&\^]');

  FuzzyFinder(this.patterns) {
    for (var pattern in patterns) {
      if (pattern.isEmpty) continue;
      pattern = pattern.replaceAllMapped(sanitizerRegExp, (m) => '#');
      regexps.add(new RegExp(
          pattern.split('').join('.*').replaceAll('^', '\\^'),
          caseSensitive: false));
    }
  }

  int computeMatchPenalty(String name, String pattern) {
    // In general we can compare the match against the pattern, but simply
    // favoring short results actually works pretty well.
    // The user can always write a longer pattern to get the results with longer
    // names, whereas a short name could be unreachable if it was not favored
    // higher than the long names.
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
