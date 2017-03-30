// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests that the closed world computed from [WorldImpact]s derived from kernel
// is equivalent to the original computed from resolution.
library dart2js.kernel.closed_world_test;

import 'package:async_helper/async_helper.dart';
import 'package:compiler/src/commandline_options.dart';
import 'package:compiler/src/common.dart';
import 'package:compiler/src/common_elements.dart';
import 'package:compiler/src/common/resolution.dart';
import 'package:compiler/src/compiler.dart';
import 'package:compiler/src/elements/resolution_types.dart';
import 'package:compiler/src/elements/elements.dart';
import 'package:compiler/src/enqueue.dart';
import 'package:compiler/src/js_backend/backend.dart';
import 'package:compiler/src/js_backend/backend_helpers.dart';
import 'package:compiler/src/js_backend/backend_impact.dart';
import 'package:compiler/src/js_backend/backend_usage.dart';
import 'package:compiler/src/js_backend/custom_elements_analysis.dart';
import 'package:compiler/src/js_backend/native_data.dart';
import 'package:compiler/src/js_backend/interceptor_data.dart';
import 'package:compiler/src/js_backend/lookup_map_analysis.dart';
import 'package:compiler/src/js_backend/mirrors_analysis.dart';
import 'package:compiler/src/js_backend/mirrors_data.dart';
import 'package:compiler/src/js_backend/no_such_method_registry.dart';
import 'package:compiler/src/js_backend/resolution_listener.dart';
import 'package:compiler/src/js_backend/type_variable_handler.dart';
import 'package:compiler/src/native/enqueue.dart';
import 'package:compiler/src/kernel/world_builder.dart';
import 'package:compiler/src/options.dart';
import 'package:compiler/src/ssa/kernel_impact.dart';
import 'package:compiler/src/serialization/equivalence.dart';
import 'package:compiler/src/universe/world_builder.dart';
import 'package:compiler/src/universe/world_impact.dart';
import 'package:compiler/src/world.dart';
import 'impact_test.dart';
import '../memory_compiler.dart';
import '../serialization/helper.dart';
import '../serialization/model_test_helper.dart';

const SOURCE = const {
  'main.dart': '''
abstract class A {
  // redirecting factory in abstract class to other class
  factory A.a() = D.a;
  // redirecting factory in abstract class to factory in abstract class
  factory A.b() = B.a;
}
abstract class B implements A {
  factory B.a() => null;
}
class C implements B {
  // redirecting factory in concrete to other class
  factory C.a() = D.a;
}
class D implements C {
  D.a();
}
main(args) {
  new A.a();
  new A.b();
  new C.a();
  print(new List<String>()..add('Hello World!'));
}
'''
};

main(List<String> args) {
  Arguments arguments = new Arguments.from(args);
  Uri entryPoint;
  Map<String, String> memorySourceFiles;
  if (arguments.uri != null) {
    entryPoint = arguments.uri;
    memorySourceFiles = const <String, String>{};
  } else {
    entryPoint = Uri.parse('memory:main.dart');
    memorySourceFiles = SOURCE;
  }

  asyncTest(() async {
    enableDebugMode();
    Compiler compiler = compilerFor(
        entryPoint: entryPoint,
        memorySourceFiles: memorySourceFiles,
        options: [
          Flags.analyzeOnly,
          Flags.useKernel,
          Flags.enableAssertMessage
        ]);
    ElementResolutionWorldBuilder.useInstantiationMap = true;
    compiler.resolution.retainCachesForTesting = true;
    await compiler.run(entryPoint);
    compiler.resolutionWorldBuilder.closeWorld(compiler.reporter);

    JavaScriptBackend backend = compiler.backend;
    // Create a new resolution enqueuer and feed it with the [WorldImpact]s
    // computed from kernel through the [build] in `kernel_impact.dart`.
    ResolutionEnqueuer enqueuer = new ResolutionEnqueuer(
        compiler.enqueuer,
        compiler.options,
        compiler.reporter,
        const TreeShakingEnqueuerStrategy(),
        createResolutionEnqueuerListener(compiler),
        new ElementResolutionWorldBuilder(
            backend, compiler.resolution, const OpenWorldStrategy()),
        new ResolutionWorkItemBuilder(compiler.resolution),
        'enqueuer from kernel');
    ClosedWorld closedWorld = computeClosedWorld(compiler, enqueuer);
    BackendUsage backendUsage = compiler.backend.backendUsageBuilder.close();
    checkResolutionEnqueuers(
        backendUsage, backendUsage, compiler.enqueuer.resolution, enqueuer,
        typeEquivalence: (ResolutionDartType a, ResolutionDartType b) {
      return areTypesEquivalent(unalias(a), unalias(b));
    }, elementFilter: (Element element) {
      if (element is ConstructorElement && element.isRedirectingFactory) {
        // Redirecting factory constructors are skipped in kernel.
        return false;
      }
      if (element is ClassElement) {
        for (ConstructorElement constructor in element.constructors) {
          if (!constructor.isRedirectingFactory) {
            return true;
          }
        }
        // The class cannot itself be instantiated.
        return false;
      }
      return true;
    }, verbose: arguments.verbose);
    checkClosedWorlds(
        compiler.resolutionWorldBuilder.closedWorldForTesting, closedWorld,
        verbose: arguments.verbose);
  });
}

EnqueuerListener createResolutionEnqueuerListener(Compiler compiler) {
  JavaScriptBackend backend = compiler.backend;
  return new ResolutionEnqueuerListener(
      compiler.options,
      compiler.elementEnvironment,
      compiler.commonElements,
      backend.helpers,
      backend.impacts,
      backend.backendClasses,
      backend.nativeBasicData,
      backend.interceptorDataBuilder,
      backend.backendUsageBuilder,
      backend.rtiNeedBuilder,
      backend.mirrorsDataBuilder,
      backend.noSuchMethodRegistry,
      backend.customElementsResolutionAnalysis,
      backend.lookupMapResolutionAnalysis,
      backend.mirrorsResolutionAnalysis,
      new TypeVariableResolutionAnalysis(compiler.elementEnvironment,
          backend.impacts, backend.backendUsageBuilder),
      backend.nativeResolutionEnqueuer,
      backend.kernelTask);
}

EnqueuerListener createKernelResolutionEnqueuerListener(
    CompilerOptions options, KernelWorldBuilder worldBuilder) {
  ElementEnvironment elementEnvironment = worldBuilder.elementEnvironment;
  CommonElements commonElements = worldBuilder.commonElements;
  BackendHelpers helpers =
      new BackendHelpers(elementEnvironment, commonElements);
  BackendImpacts impacts = new BackendImpacts(options, commonElements, helpers);

  // TODO(johnniwinther): Create Kernel based implementations for these:
  NativeBasicData nativeBasicData;
  RuntimeTypesNeedBuilder rtiNeedBuilder;
  MirrorsDataBuilder mirrorsDataBuilder;
  NoSuchMethodRegistry noSuchMethodRegistry;
  CustomElementsResolutionAnalysis customElementsResolutionAnalysis;
  LookupMapResolutionAnalysis lookupMapResolutionAnalysis;
  MirrorsResolutionAnalysis mirrorsResolutionAnalysis;
  NativeResolutionEnqueuer nativeResolutionEnqueuer;

  InterceptorDataBuilder interceptorDataBuilder =
      new InterceptorDataBuilderImpl(
          nativeBasicData, helpers, elementEnvironment, commonElements);
  BackendUsageBuilder backendUsageBuilder =
      new BackendUsageBuilderImpl(commonElements, helpers);

  return new ResolutionEnqueuerListener(
      options,
      elementEnvironment,
      commonElements,
      helpers,
      impacts,
      new JavaScriptBackendClasses(
          elementEnvironment, helpers, nativeBasicData),
      nativeBasicData,
      interceptorDataBuilder,
      backendUsageBuilder,
      rtiNeedBuilder,
      mirrorsDataBuilder,
      noSuchMethodRegistry,
      customElementsResolutionAnalysis,
      lookupMapResolutionAnalysis,
      mirrorsResolutionAnalysis,
      new TypeVariableResolutionAnalysis(
          elementEnvironment, impacts, backendUsageBuilder),
      nativeResolutionEnqueuer);
}

ClosedWorld computeClosedWorld(Compiler compiler, ResolutionEnqueuer enqueuer) {
  JavaScriptBackend backend = compiler.backend;

  if (compiler.deferredLoadTask.isProgramSplit) {
    enqueuer.applyImpact(backend.computeDeferredLoadingImpact());
  }
  enqueuer.open(const ImpactStrategy(), compiler.mainFunction,
      compiler.libraryLoader.libraries);
  enqueuer.forEach((work) {
    MemberElement element = work.element;
    ResolutionImpact resolutionImpact = build(compiler, element.resolvedAst);
    WorldImpact worldImpact = compiler.backend.impactTransformer
        .transformResolutionImpact(enqueuer, resolutionImpact);
    enqueuer.applyImpact(worldImpact, impactSource: element);
  });
  return enqueuer.worldBuilder.closeWorld(compiler.reporter);
}
