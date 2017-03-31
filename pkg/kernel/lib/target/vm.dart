// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library kernel.target.vm;

import '../ast.dart';
import '../class_hierarchy.dart';
import '../core_types.dart';
import '../transformations/check_dataflow.dart';
import '../transformations/continuation.dart' as cont;
import '../transformations/erasure.dart';
import '../transformations/insert_type_checks.dart';
import '../transformations/mixin_full_resolution.dart' as mix;
import '../transformations/sanitize_for_vm.dart';
import '../transformations/setup_builtin_library.dart' as setup_builtin_library;
import '../transformations/treeshaker.dart';
import 'package:kernel/kernel.dart';
import 'targets.dart';

/// Specializes the kernel IR to the Dart VM.
class VmTarget extends Target {
  final TargetFlags flags;

  VmTarget(this.flags);

  bool get strongMode => flags.strongMode;

  /// The VM patch files are not strong mode clean, so we adopt a hybrid mode
  /// where the SDK is internally unchecked, but trusted to satisfy the types
  /// declared on its interface.
  bool get strongModeSdk => strongMode;

  String get name => 'vm';

  // This is the order that bootstrap libraries are loaded according to
  // `runtime/vm/object_store.h`.
  List<String> get extraRequiredLibraries => const <String>[
        'dart:async',
        'dart:collection',
        'dart:convert',
        'dart:developer',
        'dart:_internal',
        'dart:isolate',
        'dart:math',

        // The library dart:mirrors may be ignored by the VM, e.g. when built in
        // PRODUCT mode.
        'dart:mirrors',

        'dart:profiler',
        'dart:typed_data',
        'dart:vmservice_io',
        'dart:_vmservice',
        'dart:_builtin',
        'dart:nativewrappers',
        'dart:io',
      ];

  Iterable<Uri> getDefaultEntryPointManifests(Uri sdkRoot) {
    var manifestDir = sdkRoot.resolve('runtime/bin/');
    return <Uri>[
      manifestDir.resolve('dart_entries.txt'),
      manifestDir.resolve('dart_io_entries.txt'),
      manifestDir.resolve('dart_product_entries.txt'),
    ];
  }

  ClassHierarchy _hierarchy;

  void performModularTransformations(Program program) {
    var mixins = new mix.MixinFullResolution()..transform(program);

    _hierarchy = mixins.hierarchy;
  }

  void performGlobalTransformations(Program program) {
    var coreTypes = new CoreTypes(program);

    if (strongMode) {
      doStep(TargetHooks.typeCheck, program, () {
        new InsertTypeChecks(hierarchy: _hierarchy, coreTypes: coreTypes)
            .transformProgram(program);
      });
      // new InsertCovarianceChecks(hierarchy: _hierarchy, coreTypes: coreTypes)
      //     .transformProgram(program);
    }

    if (flags.treeShake) {
      doStep(TargetHooks.treeShake, program, () {
        performTreeShaking(program);
      });
    }

    doStep(TargetHooks.dataflow, program, () {});

    if (flags.checkDataflow) {
      new CheckDataflow().transformProgram(program);
    }

    doStep(TargetHooks.async_, program, () {
      cont.transformProgram(program);
    });

    // Repair `_getMainClosure()` function in dart:_builtin.
    setup_builtin_library.transformProgram(program);

    doStep(TargetHooks.erase, program, () {
      performErasure(program);
    });

    doStep(TargetHooks.sanitize, program, () {
      new SanitizeForVM().transform(program);
    });
  }

  void performTreeShaking(Program program) {
    var coreTypes = new CoreTypes(program);
    new TreeShaker(program,
            hierarchy: _hierarchy,
            coreTypes: coreTypes,
            strongMode: strongMode,
            forceShaking: flags.forceTreeShake)
        .transform(program);
    _hierarchy = null; // Hierarchy must be recomputed.
  }

  void performErasure(Program program) {
    new Erasure().transform(program);
  }

  void doStep(String name, Program program, void step()) {
    fireHookBefore(name, program);
    step();
    fireHookAfter(name, program);
  }

  void fireHookBefore(String name, Program program) {
    var hook = flags.hooksBefore[name];
    if (hook != null) {
      hook(program);
    }
  }

  void fireHookAfter(String name, Program program) {
    var hook = flags.hooksAfter[name];
    if (hook != null) {
      hook(program);
    }
  }
}
