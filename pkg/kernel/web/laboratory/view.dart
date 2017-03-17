// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.view;

import 'laboratory_data.dart';
import 'package:kernel/ast.dart';
import 'lexer.dart';

View view = new View(null);

class View {
  final NamedNode shownObject;
  final Source source;
  final Token tokenizedSource;
  final List<TreeNode> astNodes;

  factory View(NamedNode shownObject) {
    if (shownObject == null) {
      return new View._(null, null, null, null);
    }
    String fileUri = getFileUriFromNamedNode(shownObject);
    Source source = program.uriToSource[fileUri];
    Token tokenizedSource = tryTokenizeSource(source);
    List<TreeNode> astNodes = <TreeNode>[];
    shownObject.accept(new AstNodeCollector(astNodes));
    astNodes.sort((e1, e2) => e1.fileOffset.compareTo(e2.fileOffset));
    return new View._(shownObject, source, tokenizedSource, astNodes);
  }

  View._(this.shownObject, this.source, this.tokenizedSource, this.astNodes);

  bool get hasObject => shownObject != null;
  bool get hasTokens => tokenizedSource != null;
  bool get hasSource => source != null;
  bool get hasAstNodes => astNodes != null;

  Library get libraryNode {
    TreeNode node = shownObject;
    while (node != null && node is! Library) {
      node = node.parent;
    }
    return node;
  }

  Class get classNode {
    TreeNode node = shownObject;
    while (node != null && node is! Class) {
      node = node.parent;
    }
    return node;
  }

  Member get memberNode {
    TreeNode node = shownObject;
    return node is Member ? node : null;
  }
}

class AstNodeCollector extends RecursiveVisitor {
  final List<TreeNode> result;

  AstNodeCollector(this.result);

  @override
  visitProcedure(Procedure node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.function.inferredReturnValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }

  @override
  visitConstructor(Constructor node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.function.inferredReturnValueOffset != -1) {
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
        node.inferredValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }

  @override
  visitVariableDeclaration(VariableDeclaration node) {
    if (node.fileOffset != TreeNode.noOffset &&
        node.inferredValueOffset != -1) {
      result.add(node);
    }
    node.visitChildren(this);
  }
}

String getFileUriFromNamedNode(NamedNode node) {
  if (node is Library) return node.fileUri;
  if (node is Class) return node.fileUri;
  if (node is Member) return node.fileUri;
  throw 'Not a named node: $node';
}

bool isDynamicCall(TreeNode node) {
  return node is MethodInvocation && node.interfaceTarget == null ||
      node is PropertyGet && node.interfaceTarget == null ||
      node is PropertySet && node.interfaceTarget == null;
}

int getInferredValueOffset(TreeNode node) {
  if (node is Expression) {
    return node.inferredValueOffset;
  } else if (node is VariableDeclaration) {
    return node.inferredValueOffset;
  } else if (node is Field) {
    return Field.inferredValueOffset;
  } else if (node is Member) {
    return node.function.inferredReturnValueOffset;
  }
  return -1;
}
