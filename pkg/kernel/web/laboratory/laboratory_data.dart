library laboratory_data;

import 'package:kernel/ast.dart';
import 'package:kernel/class_hierarchy.dart';
import 'package:kernel/core_types.dart';
import 'package:kernel/inference/constraints.dart';
import 'package:kernel/inference/extractor/binding.dart';
import 'package:kernel/inference/report/report.dart';
import 'package:kernel/library_index.dart';
import 'package:kernel/type_environment.dart';

Program program;
LibraryIndex libraryIndex;
ConstraintSystem constraintSystem;
CoreTypes coreTypes;
ClassHierarchy classHierarchy;
TypeEnvironment typeEnvironment;
Binding binding;
Report report;
