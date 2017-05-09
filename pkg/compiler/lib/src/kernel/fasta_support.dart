// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Additions to Fasta for generating .dill (Kernel IR) files with dart2js patch
/// files and native hooks.
library compiler.src.kernel.fasta_support;

// TODO(sigmund): get rid of this file. Fasta should be agnostic of the
// target platform, at which point this should not be necessary. In particular,
// we need to:
//  - add a fasta flag to configure the platform library location.
//  - add a fasta flag to specify which sdk libraries should be built-in
//    (that would replace `loadExtraRequiredLibraries`).
//  - add flags to fasta to turn on various transformations.
//  - get rid of `native` in dart2js patches or unify the syntax with the VM.

import 'dart:async' show Future;
import 'dart:io' show exitCode;

import 'package:front_end/physical_file_system.dart';
import 'package:kernel/ast.dart' show Source;

import 'package:front_end/src/fasta/compiler_context.dart' show CompilerContext;
import 'package:front_end/src/fasta/dill/dill_target.dart' show DillTarget;
import 'package:front_end/src/fasta/fasta.dart' show CompileTask;
import 'package:front_end/src/fasta/kernel/kernel_target.dart'
    show KernelTarget;
import 'package:front_end/src/fasta/loader.dart' show Loader;
import 'package:front_end/src/fasta/parser/parser.dart' show optional;
import 'package:front_end/src/fasta/scanner/token.dart' show Token;
import 'package:front_end/src/fasta/ticker.dart' show Ticker;
import 'package:front_end/src/fasta/translate_uri.dart' show TranslateUri;

/// Generates a platform.dill file containing the compiled Kernel IR of the
/// dart2js SDK.
Future compilePlatform(Uri patchedSdk, Uri output, {Uri packages}) async {
  Uri deps = Uri.base.resolveUri(new Uri.file("${output.toFilePath()}.d"));
  TranslateUri uriTranslator = await TranslateUri.parse(
      PhysicalFileSystem.instance, patchedSdk, packages);
  var ticker = new Ticker(isVerbose: false);
  var dillTarget = new DillTargetForDart2js(ticker, uriTranslator);
  var kernelTarget =
      new KernelTargetForDart2js(dillTarget, uriTranslator, false);

  kernelTarget.read(Uri.parse("dart:core"));
  await dillTarget.writeOutline(null);
  await kernelTarget.writeOutline(output);

  if (exitCode != 0) return null;
  await kernelTarget.writeProgram(output);
  await kernelTarget.writeDepsFile(output, deps);
}

/// Extends the internal fasta [CompileTask] to use a dart2js-aware [DillTarget]
/// and [KernelTarget].
class Dart2jsCompileTask extends CompileTask {
  Dart2jsCompileTask(CompilerContext c, Ticker ticker) : super(c, ticker);

  @override
  DillTarget createDillTarget(TranslateUri uriTranslator) {
    return new DillTargetForDart2js(ticker, uriTranslator);
  }

  @override
  KernelTarget createKernelTarget(
      DillTarget dillTarget, TranslateUri uriTranslator, bool strongMode) {
    return new KernelTargetForDart2js(
        dillTarget, uriTranslator, strongMode, c.uriToSource);
  }
}

/// Specializes [KernelTarget] to build kernel for dart2js: no transformations
/// are run, JS-specific libraries are included in the SDK, and native clauses
/// have no string parameter.
class KernelTargetForDart2js extends KernelTarget {
  KernelTargetForDart2js(
      DillTarget target, TranslateUri uriTranslator, bool strongMode,
      [Map<String, Source> uriToSource])
      : super(PhysicalFileSystem.instance, target, uriTranslator, strongMode,
            uriToSource);

  @override
  Token skipNativeClause(Token token) => _skipNative(token);

  @override
  String extractNativeMethodName(Token token) => null;

  @override
  void loadExtraRequiredLibraries(Loader loader) => _loadExtras(loader);

  @override
  void runBuildTransformations() {}

  @override
  void runLinkTransformations(_) {}
}

/// Specializes [DillTarget] to build kernel for dart2js: JS-specific libraries
/// are included in the SDK, and native clauses have no string parameter.
class DillTargetForDart2js extends DillTarget {
  DillTargetForDart2js(Ticker ticker, TranslateUri uriTranslator)
      : super(ticker, uriTranslator);

  @override
  Token skipNativeClause(Token token) => _skipNative(token);

  @override
  String extractNativeMethodName(Token token) => null;

  @override
  void loadExtraRequiredLibraries(Loader loader) => _loadExtras(loader);
}

/// We use native clauses of this form in our dart2js patch files:
///
///     methodDeclaration() native;
///
/// The default front_end parser doesn't support this, so it will trigger an
/// error recovery condition. This function is used while parsing to detect this
/// form and continue parsing.
///
/// Note that `native` isn't part of the Dart Language Specification, and the VM
/// uses it a slightly different form. We hope to remove this syntax in our
/// dart2js patch files and replace it with the external modifier.
Token _skipNative(Token token) {
  if (!optional("native", token)) return null;
  if (!optional(";", token.next)) return null;
  return token;
}

void _loadExtras(Loader loader) {
  for (String uri in _extraDart2jsLibraries) {
    loader.read(Uri.parse(uri));
  }
}

const _extraDart2jsLibraries = const <String>[
  'dart:async',
  'dart:collection',
  'dart:mirrors',
  'dart:_native_typed_data',
  'dart:_internal',
  'dart:_js_helper',
  'dart:_interceptors',
  'dart:_foreign_helper',
  'dart:_js_mirrors',
  'dart:_js_names',
  'dart:_js_embedded_names',
  'dart:_isolate_helper',
];
