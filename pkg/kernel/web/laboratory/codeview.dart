// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';

import 'package:kernel/ast.dart';
import 'package:path/path.dart';

import 'laboratory.dart';

class CodeView {
  final DivElement viewElement;
  final Element filenameElement;

  int firstLineShown = -1;

  CodeView(this.viewElement, this.filenameElement) {
    assert(viewElement != null);
    assert(filenameElement != null);
    viewElement.onClick.listen(onClick);
  }

  void onClick(MouseEvent ev) {
    var target = ev.target;
    if (target is LIElement) {
      var parent = target.parent;
      int index = parent.children.indexOf(target);
      int lineIndex = firstLineShown + index;

      print('Clicking on line index ${lineIndex}');
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
    if (source == null) {
      showErrorMessage(getMissingSourceMessage(uri));
      return;
    }
    setContent([makeSourceList(source)]);
  }

  void showLibrary(Library library) {
    showFileContents(library.fileUri);
  }

  void showMember(Member member) {
    setFilename(member.fileUri);
    Source source = program.uriToSource[member.fileUri];
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
