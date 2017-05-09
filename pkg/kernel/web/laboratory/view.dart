// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.view;

import 'package:kernel/ast.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:path/path.dart';

import 'laboratory_data.dart';
import 'lexer.dart';

View view = new View(null);

class View {
  final Reference reference;
  final Source _source;
  final Token tokenizedSource;
  final List<TreeNode> astNodes;
  final List<Constraint> constraintList;

  factory View(Reference reference) {
    if (reference == null) {
      return new View._(null, null, null, null, null);
    }
    NamedNode node = reference.node;
    String fileUri = getFileUriFromNamedNode(node);
    Source source = program.uriToSource[fileUri];
    Token tokenizedSource = tryTokenizeSource(source);
    List<TreeNode> astNodes = <TreeNode>[];
    node.accept(new AstNodeCollector(astNodes));
    astNodes.sort((e1, e2) => e1.fileOffset.compareTo(e2.fileOffset));
    var cluster = constraintSystem.getCluster(node.reference);
    var constraintList = cluster.constraints.toList();
    constraintList.sort((c1, c2) => c1.fileOffset.compareTo(c2.fileOffset));
    return new View._(
        reference, source, tokenizedSource, astNodes, constraintList);
  }

  View._(this.reference, this._source, this.tokenizedSource, this.astNodes,
      this.constraintList);

  NamedNode get astNode => reference.node;

  String get name => getShortName(astNode);

  bool get hasObject => astNode != null;
  bool get hasTokens => tokenizedSource != null;
  bool get hasSource => _source != null;
  bool get hasAstNodes => astNodes != null;

  Library get libraryNode {
    TreeNode node = astNode;
    while (node != null && node is! Library) {
      node = node.parent;
    }
    return node;
  }

  Class get classNode {
    TreeNode node = astNode;
    while (node != null && node is! Class) {
      node = node.parent;
    }
    return node;
  }

  Member get memberNode {
    TreeNode node = astNode;
    return node is Member ? node : null;
  }

  String get fileUri => getFileUriFromNamedNode(astNode);

  int getStartOfLine(int lineIndex) {
    return _source.lineStarts[lineIndex];
  }

  int getEndOfLine(int lineIndex) {
    if (lineIndex + 1 >= _source.lineStarts.length) return _source.text.length;
    return _source.lineStarts[lineIndex + 1];
  }

  int getLineFromOffset(int offset) {
    return _source.getLineFromOffset(offset) - 1;
  }

  int get numberOfLines => _source.lineStarts.length;

  int getIndexOfLastAstNodeStrictlyBeforeOffset(int offset) {
    int first = 0, last = astNodes.length - 1;
    while (first < last) {
      int mid = last - ((last - first) >> 1);
      int pivot = astNodes[mid].fileOffset;
      if (offset <= pivot) {
        last = mid - 1;
      } else {
        first = mid;
      }
    }
    return last;
  }

  int getAstNodeIndexFromToken(Token token) {
    var index = getIndexOfLastAstNodeStrictlyBeforeOffset(token.end);
    if (index == -1) return -1;
    var expression = astNodes[index];
    if (token.offset <= expression.fileOffset &&
        expression.fileOffset < token.end) {
      return index;
    }
    return -1;
  }

  String getSourceCodeSubstring(int begin, int end) {
    return _source.getSubstring(begin, end);
  }

  Token getFirstTokenAfterOffset(int offset) {
    Token token = tokenizedSource;
    while (token != null && token.end <= offset) {
      token = token.next;
    }
    return token;
  }
}

class AstNodeCollector extends RecursiveVisitor {
  final List<TreeNode> result;

  AstNodeCollector(this.result);

  @override
  visitProcedure(Procedure node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.function.returnDataflowValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }

  @override
  visitConstructor(Constructor node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.function.returnDataflowValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }

  @override
  visitField(Field node) {
    if (node.fileOffset != TreeNode.noOffset) {
      result.add(node);
    }
    node.visitChildren(this);
  }

  @override
  defaultExpression(Expression node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.dataflowValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.dataflowValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }
}

String getFileUriFromNamedNode(NamedNode node) {
  if (node is Library) return node.fileUri;
  if (node is Class) return node.fileUri;
  if (node is Member) return node.fileUri;
  return '';
}

bool isDynamicCall(TreeNode node) {
  return node is MethodInvocation && node.interfaceTarget == null ||
      node is PropertyGet && node.interfaceTarget == null ||
      node is PropertySet && node.interfaceTarget == null;
}

int getDataflowValueOffset(TreeNode node) {
  if (node is Expression) {
    return node.dataflowValueOffset;
  } else if (node is VariableDeclaration) {
    return node.dataflowValueOffset;
  } else if (node is Field) {
    return Field.dataflowValueOffset;
  } else if (node is Member) {
    return node.function.returnDataflowValueOffset;
  }
  return -1;
}

String getMemberName(Member node) {
  var name = node.name.name;
  return name.isEmpty ? '<default>' : name;
}

String getShortName(NamedNode node) {
  if (node is Class) {
    return node.name;
  } else if (node is Member) {
    var class_ = node.enclosingClass;
    String name = getMemberName(node);
    if (class_ != null) {
      return '${class_.name}.$name';
    }
    return name;
  } else if (node is Library) {
    return getLibraryName(node);
  } else {
    throw 'Unexpected node: ${node.runtimeType}';
  }
}

String getLongName(NamedNode node) {
  if (node is Class) {
    return '${getLongName(node.enclosingLibrary)}.${node.name}';
  } else if (node is Member) {
    return '${getLongName(node.parent)}.${getMemberName(node)}';
  } else {
    return getLibraryName(node);
  }
}

String getLibraryName(Library library) {
  return library.name ?? withoutExtension(library.importUri.pathSegments.last);
}
