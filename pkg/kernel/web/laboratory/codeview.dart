// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';

import 'laboratory_data.dart';
import 'package:kernel/ast.dart';
import 'package:kernel/ast.dart';
import 'package:path/path.dart';

import 'laboratory.dart';

class CodeView {
  final DivElement viewElement;
  final Element filenameElement;

  int firstLineShown = -1;
  Source shownSource;
  NamedNode shownObject;

  CodeView(this.viewElement, this.filenameElement) {
    assert(viewElement != null);
    assert(filenameElement != null);
    viewElement.onClick.listen(onClick);
  }

  void onClick(MouseEvent ev) {
    if (shownSource == null || shownObject == null) return;
    var target = ev.target;
    if (target is LIElement) {
      var parent = target.parent;
      int index = parent.children.indexOf(target);
      int lineIndex = firstLineShown + index;
      var rect = target.getBoundingClientRect();
      ui.typeView.showTypesOnLine(shownSource, shownObject, lineIndex);
      ui.typeView.setPosition(rect.right, rect.top);
    }
  }

  String getMissingSourceMessage(String uri) {
    if (libraryIndex.containsLibrary(uri)) {
      return "Missing source for library '$uri'";
    } else {
      return "There is no library or source file for '$uri'";
    }
  }

  void showFileContents(String uri) {
    setFilename(uri);
    Source source = program.uriToSource[uri];
    shownSource = source;
    if (source == null) {
      showErrorMessage(getMissingSourceMessage(uri));
      return;
    }
    setContent([makeSourceList(source)]);
  }

  void showObject(NamedNode node) {
    if (node is Library) {
      showLibrary(node);
    } else if (node is Class) {
      showClass(node);
    } else if (node is Member) {
      showMember(node);
    } else {
      shownObject = null;
      showNothing();
    }
  }

  void showLibrary(Library library) {
    shownObject = library;
    showFileContents(library.fileUri);
  }

  void showClass(Class node) {
    shownObject = node;
    setFilename(node.fileUri);
    Source source = program.uriToSource[node.fileUri];
    shownSource = source;
    if (source == null) {
      showErrorMessage(getMissingSourceMessage(node.fileUri));
      return;
    }
    setContent([makeSourceList(source, node.fileOffset)]);
  }

  void showMember(Member member) {
    shownObject = member;
    setFilename(member.fileUri);
    Source source = program.uriToSource[member.fileUri];
    shownSource = source;
    if (source == null) {
      showErrorMessage(getMissingSourceMessage(member.fileUri));
      return;
    }
    var contents = <Element>[];
    var class_ = member.enclosingClass;
    if (class_ != null) {
      contents.add(makeSourceList(source, class_.fileOffset));
    }
    contents
        .add(makeSourceList(source, member.fileOffset, member.fileEndOffset));
    setContent(contents);
  }

  void showErrorMessage(String message) {
    setContent([new DivElement()..text = message]);
  }

  void showNothing() {
    setContent([]);
  }

  void setContent(List<Element> content) {
    viewElement.children
      ..clear()
      ..addAll(content);
  }

  OListElement makeSourceList(Source source, [int startOffset, int endOffset]) {
    var htmlList = new OListElement();
    var code = source.source;
    int numberOfLines = source.lineStarts.length;
    int firstLine = 0;
    int lastLine = numberOfLines;
    if (startOffset != null) {
      firstLine = source.getLineFromOffset(startOffset);
      htmlList.setAttribute('start', '${1 + firstLine}');
      endOffset ??= startOffset;
    }
    if (endOffset != null) {
      lastLine = 1 + source.getLineFromOffset(endOffset);
    }
    firstLineShown = firstLine;
    for (int lineIndex = firstLine; lineIndex < lastLine; ++lineIndex) {
      int start = source.lineStarts[lineIndex];
      int end = lineIndex == numberOfLines - 1
          ? code.length
          : source.lineStarts[lineIndex + 1];
      String lineText = code.substring(start, end);
      var htmlLine = new LIElement()..text = lineText;
      htmlList.append(htmlLine);
    }
    return htmlList;
  }

  String extractRelevantFilePath(String uri) {
    if (!uri.startsWith('file:')) return uri;
    var commonRootFolderNames = [
      'lib',
      'bin',
      'web',
      'test',
      'pkg',
      'packages',
    ];
    int lowestIndex = uri.length;
    for (var rootName in commonRootFolderNames) {
      int index = uri.indexOf('$rootName/');
      if (index != -1 && index < lowestIndex) {
        lowestIndex = index;
      }
    }
    if (lowestIndex != uri.length) {
      return uri.substring(lowestIndex);
    }
    return uri;
  }

  void setFilename(String uri) {
    uri = extractRelevantFilePath(uri);
    filenameElement.children
      ..clear()
      ..add(new OListElement()..append(new LIElement()..text = uri));
  }
}
