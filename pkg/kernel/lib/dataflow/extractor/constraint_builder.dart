// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.dataflow.extractor.constraint_builder;

import '../../ast.dart';
import '../constraints.dart';

/// Attaches source information to constraints and adds a constraint to the
/// proper cluster in the constraint system.
class ConstraintBuilder {
  final ConstraintSystem constraintSystem;

  NamedNode _currentOwner;
  int _currentFileOffset = -1;

  ConstraintBuilder(this.constraintSystem);

  void setOwner(NamedNode owner) {
    _currentOwner = owner;
  }

  void setFileOffset(int fileOffset) {
    _currentFileOffset = fileOffset;
  }

  void addConstraint(Constraint constraint) {
    constraintSystem.addConstraint(
        constraint, _currentOwner.reference, _currentFileOffset);
  }
}
