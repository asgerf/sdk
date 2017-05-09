// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This is an interface to the Dart Kernel parser and Kernel binary generator.
///
/// It is used by the kernel-isolate to load Dart source code and generate
/// Kernel binary format.
///
/// This is either invoked as the root script of the Kernel isolate when used
/// as a part of
///
///         dart --dfe=utils/kernel-service/kernel-service.dart ...
///
/// invocation or it is invoked as a standalone script to perform training for
/// the app-jit snapshot
///
///         dart utils/kernel-service/kernel-service.dart --train <source-file>
///
///
library runtime.tools.kernel_service;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:front_end/src/fasta/vm.dart'
    show CompilationResult, Status, parseScript;

const bool verbose = const bool.fromEnvironment('DFE_VERBOSE');

const bool strongMode = const bool.fromEnvironment('DFE_STRONG_MODE');

Future<CompilationResult> _processLoadRequestImpl(String inputFilePathOrUri) {
  Uri scriptUri = Uri.parse(inputFilePathOrUri);

  // Because we serve both Loader and bootstrapping requests we need to
  // duplicate the logic from _resolveScriptUri(...) here and attempt to
  // resolve schemaless uris using current working directory.
  if (!scriptUri.hasScheme) {
    // Script does not have a scheme, assume that it is a path,
    // resolve it against the working directory.
    scriptUri = Uri.base.resolveUri(new Uri.file(inputFilePathOrUri));
  }

  if (!scriptUri.isScheme('file')) {
    // TODO(vegorov): Reuse loader code to support other schemes.
    return new Future<CompilationResult>.value(new CompilationResult.error(
        "Expected 'file' scheme for a script uri: got ${scriptUri.scheme}"));
  }

  return parseScript(scriptUri, verbose: verbose, strongMode: strongMode);
}

// Process a request from the runtime. See KernelIsolate::CompileToKernel in
// kernel_isolate.cc and Loader::SendKernelRequest in loader.cc.
Future _processLoadRequest(request) async {
  if (verbose) {
    print("DFE: request: $request");
    print("DFE: Platform.packageConfig: ${Platform.packageConfig}");
    print("DFE: Platform.resolvedExecutable: ${Platform.resolvedExecutable}");
  }

  int tag = request[0];
  final SendPort port = request[1];
  final String inputFileUrl = request[2];

  CompilationResult result;
  try {
    result = await _processLoadRequestImpl(inputFileUrl);
  } catch (error, stack) {
    result = new CompilationResult.crash(error, stack);
  }

  if (verbose) {
    print("DFE:> ${result}");
  }

  // Check whether this is a Loader request or a bootstrapping request from
  // KernelIsolate::CompileToKernel.
  final isBootstrapRequest = tag == null;
  if (isBootstrapRequest) {
    port.send(result.toResponse());
  } else {
    // See loader.cc for the code that handles these replies.
    if (result.status != Status.ok) {
      tag = -tag;
    }
    port.send([tag, inputFileUrl, inputFileUrl, null, result.payload]);
  }
}

train(String scriptUri) {
  // TODO(28532): Enable on Windows.
  if (Platform.isWindows) return;

  var tag = 1;
  var responsePort = new RawReceivePort();
  responsePort.handler = (response) {
    if (response[0] == tag) {
      // Success.
      responsePort.close();
    } else if (response[0] == -tag) {
      // Compilation error.
      throw response[4];
    } else {
      throw "Unexpected response: $response";
    }
  };
  var request = [tag, responsePort.sendPort, scriptUri];
  _processLoadRequest(request);
}

main([args]) {
  if (args?.length == 2 && args[0] == '--train') {
    // This entry point is used when creating an app snapshot. The argument
    // provides a script to compile to warm-up generated code.
    train(args[1]);
  } else {
    // Entry point for the Kernel isolate.
    return new RawReceivePort()..handler = _processLoadRequest;
  }
}
