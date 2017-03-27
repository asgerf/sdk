// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.data;

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/inference/value.dart';
import 'package:kernel/library_index.dart';
import 'package:kernel/type_environment.dart';

Program program;
LibraryIndex libraryIndex;
ConstraintSystem constraintSystem;
CoreTypes coreTypes;
ClassHierarchy classHierarchy;
TypeEnvironment typeEnvironment;
Report report;
ValueLattice valueLattice;
