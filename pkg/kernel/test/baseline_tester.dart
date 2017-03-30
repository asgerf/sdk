// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:analyzer/src/kernel/loader.dart';
import 'package:kernel/application_root.dart';
import 'package:kernel/dataflow/extractor/binding.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/target/targets.dart';
import 'package:kernel/text/ast_to_text.dart';
import 'package:kernel/verifier.dart';
import 'package:path/path.dart' as pathlib;
import 'package:test/test.dart';

final Uri testcaseDirectory = Platform.script.resolve('../testcases/');
final Uri inputDirectory = testcaseDirectory.resolve('input/');

final Uri repositoryRoot = Platform.script.resolve('../../../');
final Uri sdkDirectory = repositoryRoot.resolve('sdk');
final Uri patchedSdkDirectory =
    repositoryRoot.resolve('out/ReleaseX64/patched_sdk');

/// A target to be used for testing.
///
/// To simplify testing dependencies, we avoid transformations that rely on
/// a patched SDK or any SDK changes that have not landed in the main SDK.
abstract class TestTarget extends Target {
  /// Annotations to apply on the textual output.
  Annotator get annotator => null;

  Binding get binding => null;

  bool get usePatchedSdk => false;

  // Return a list of strings so that we can accumulate errors.
  List<String> performModularTransformations(Program program);
  List<String> performGlobalTransformations(Program program);
}

void runBaselineTests(String folderName, TestTarget target) {
  Uri outputDirectory = testcaseDirectory.resolve('$folderName/');
  var batch = new DartLoaderBatch();
  Directory directory = new Directory.fromUri(inputDirectory);
  var applicationRoot = new ApplicationRoot(directory.absolute.path);
  for (FileSystemEntity file in directory.listSync()) {
    if (file is File && file.path.endsWith('.dart')) {
      String name = pathlib.basename(file.path);
      if (name != 'generic_subclass.dart') continue;
      test(name, () async {
        Uri dartPath =
            new Uri(scheme: 'file', path: pathlib.absolute(file.path));
        String shortName = pathlib.withoutExtension(name);
        Uri filenameOfBaseline =
            outputDirectory.resolve('$shortName.baseline.txt');
        Uri filenameOfCurrent =
            outputDirectory.resolve('$shortName.current.txt');

        var program = new Program();
        var loader = await batch.getLoader(
            program,
            new DartOptions(
                strongMode: target.strongMode,
                sdk: target.usePatchedSdk
                    ? patchedSdkDirectory.path
                    : sdkDirectory.path,
                declaredVariables: target.extraDeclaredVariables,
                applicationRoot: applicationRoot));
        loader.loadProgram(dartPath, target: target);
        verifyProgram(program);
        var errors = <String>[];
        errors.addAll(target.performModularTransformations(program));
        verifyProgram(program);
        errors.addAll(target.performGlobalTransformations(program));
        verifyProgram(program);

        var buffer = new StringBuffer();
        for (var error in errors) {
          buffer.writeln('// $error');
        }
        new Printer(buffer,
                annotator: target.annotator, binding: target.binding)
            .writeLibraryFile(program.mainMethod.enclosingLibrary);
        String current = '$buffer';
        new File.fromUri(filenameOfCurrent).writeAsStringSync(current);

        var baselineFile = new File.fromUri(filenameOfBaseline);
        if (!baselineFile.existsSync()) {
          new File.fromUri(filenameOfBaseline).writeAsStringSync(current);
        } else {
          var baseline = baselineFile.readAsStringSync();
          if (baseline != current) {
            fail('Output of `$name` changed for $folderName.\n'
                'Command to reset the baseline:\n'
                '  rm $filenameOfBaseline\n'
                'Command to see the diff:\n'
                '  diff -cd $outputDirectory/$shortName.{baseline,current}.txt'
                '\n');
          }
        }
      });
    }
  }
}
