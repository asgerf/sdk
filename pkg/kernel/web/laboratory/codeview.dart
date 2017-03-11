// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:html';

import 'package:kernel/ast.dart';
import 'package:path/path.dart';

import 'laboratory.dart';

class CodeView {
  final DivElement viewElement;
  final Element titleElement;
  final Element filenameElement;

  CodeView(this.viewElement, this.titleElement, this.filenameElement) {
    assert(viewElement != null);
  }

  String getMissingSourceMessage(String library) {
    if (libraryIndex.containsLibrary(library)) {
      return "Missing library source for '$library'";
    } else {
      return "There is no library for '$library'";
    }
  }

  void showLibrary(String library) {
    setTitle(basename(library), library);
    Source source = program.uriToSource[library];
    if (source == null) {
      showErrorMessage(getMissingSourceMessage(library));
      return;
    }
    setContent([makeSourceList(source)]);
  }

  void showMember(Member member) {
    setTitle('$member'.replaceAll('::', '.'), member.fileUri);
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

  void setTitle(String bigTitle, String uri) {
    titleElement?.text = bigTitle;
    filenameElement?.text = extractRelevantFilePath(uri);
  }
}
