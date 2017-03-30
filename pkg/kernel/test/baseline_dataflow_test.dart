// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:kernel/dataflow/dataflow.dart';
import 'package:kernel/dataflow/extractor/binding.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/transformations/insert_type_checks.dart';
import 'package:kernel/transformations/mixin_full_resolution.dart';

import 'baseline_tester.dart';

class DataflowTest extends TestTarget {
  Binding binding;

  List<String> get extraRequiredLibraries => const <String>[
        'dart:async',
        'dart:collection',
        'dart:convert',
        'dart:developer',
        'dart:_internal',
        'dart:isolate',
        'dart:math',
        'dart:mirrors',
        'dart:profiler',
        'dart:typed_data',
        'dart:vmservice_io',
        'dart:_vmservice',
        'dart:_builtin',
        'dart:nativewrappers',
        'dart:io',
      ];

  @override
  String get name => 'dataflow-test';

  @override
  bool get strongMode => true;

  @override
  bool get usePatchedSdk => true;

  @override
  List<String> performModularTransformations(Program program) {
    new MixinFullResolution().transform(program);
    return const <String>[];
  }

  @override
  List<String> performGlobalTransformations(Program program) {
    new InsertTypeChecks().transformProgram(program);
    var reporter = new DataflowReporter();
    DataflowEngine.analyzeWholeProgram(program, diagnostic: reporter);
    binding = reporter.binding;
    return reporter.errorMessages.map((error) => error.brief).toList();
  }
}

void main() {
  runBaselineTests('dataflow', new DataflowTest());
}
