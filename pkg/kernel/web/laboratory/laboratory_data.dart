// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.laboratory.data;

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/dataflow/constraints.dart';
import 'package:kernel/dataflow/report/report.dart';
import 'package:kernel/dataflow/value.dart';
import 'package:kernel/library_index.dart';

// Extracted from dill file
Program program;
LibraryIndex libraryIndex;
CoreTypes coreTypes;
ClassHierarchy classHierarchy;
ValueLattice valueLattice;

// Extracted from report file
ConstraintSystem constraintSystem;
Report report;
