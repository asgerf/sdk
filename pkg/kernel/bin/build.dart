library kernel.build;

import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:kernel/analyzer/loader.dart';
import 'package:kernel/kernel.dart';
import 'package:kernel/target/targets.dart';
import 'package:kernel/target/vm.dart';
import 'package:meta/meta.dart';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart';
import 'package:kernel/verifier.dart';

String tryPath(Uri uri) {
  var path = uri.path;
  if (new File(path).existsSync()) {
    return path;
  }
  return null;
}

String currentSdk() {
  var repo = Platform.script.resolve('../../..');
  var buildDirs = [
    'out/ReleaseX64',
    'out/ReleaseIA32',
    'out/DebugX64',
    'out/DebugIA32',
    'xcodebuild/ReleaseX64',
    'xcodebuild/ReleaseIA32',
    'xcodebuild/DebugX64',
    'xcodebuild/DebugIA32',
  ];
  for (var path in buildDirs) {
    var patchedSdkDir = repo.resolve('$path/patched_sdk').path;
    if (new Directory(patchedSdkDir).existsSync()) {
      print('Found SDK in $patchedSdkDir');
      return patchedSdkDir;
    }
  }
  print('Could not find patched_sdk directory. Try recompiling');
  exit(1);
  return null;
}

var parser = new ArgParser(allowTrailingOptions: true)
  ..addOption('lib',
      valueHelp: 'path', help: 'The lib directory', defaultsTo: 'lib')
  ..addOption('build',
      valueHelp: 'path', help: 'The output directory', defaultsTo: 'build')
  ..addFlag('verify', help: 'Verify IR', defaultsTo: true);

void main(List<String> args) {
  ArgResults options = parser.parse(args);

  DartOptions dartOptions = new DartOptions(sdk: currentSdk());
  TargetFlags targetFlags = new TargetFlags();

  var builder = new Builder(
      target: new VmTarget(targetFlags),
      batch: new DartLoaderBatch(),
      libDirectory: options['lib'],
      buildDirectory: options['build'],
      verify: options['verify'],
      dartOptions: dartOptions);

  builder.watch();
}

class Builder {
  final DartLoaderBatch batch;
  final Target target;
  final String buildDirectory;
  final String libDirectory;
  final DartOptions dartOptions;
  final bool verify;
  StreamSubscription _subscription;

  Builder(
      {@required this.target,
      @required this.batch,
      @required this.buildDirectory,
      @required this.libDirectory,
      @required this.dartOptions,
      this.verify: true}) {
    assert(target != null);
    assert(batch != null);
    assert(buildDirectory != null);
    assert(libDirectory != null);
    assert(dartOptions != null);
  }

  void buildAll() {}

  Future watch() async {
    unwatch();
    Watcher watcher = new Watcher(libDirectory);
    _subscription = watcher.events.listen(_onWatchEvent);
    return watcher.ready.then((_) {
      print('Watching $libDirectory');
    });
  }

  void unwatch() {
    _subscription?.cancel();
    _subscription = null;
  }

  bool get isWatching => _subscription != null;

  void _onWatchEvent(WatchEvent event) {
    print(event);
    String path = event.path;
    if (!path.toLowerCase().endsWith('.dart')) return;
    ChangeType type = event.type;
    if (type == ChangeType.ADD || type == ChangeType.MODIFY) {
      _subscription.pause(buildDartFile(path));
    } else if (type == ChangeType.REMOVE) {
      _subscription.pause(removeBuildArtifactsForDartFile(path));
    }
  }

  Future<Program> buildProgram(String path) async {
    Repository repository = new Repository();
    var loader = await batch.getLoader(repository, dartOptions,
        packageDiscoveryPath: path);
    loader.loadLibrary(Uri.base.resolve(path));
    var program = new Program(repository.libraries);
    return program;
  }

  String getBinaryPathForDartFile(String dartFile) {
    var relativeDir = relative(dirname(dartFile), from: libDirectory);
    var binaryName = basenameWithoutExtension(dartFile) + '.dill';
    var binaryPath = join(buildDirectory, relativeDir, binaryName);
    return normalize(binaryPath);
  }

  Future buildDartFile(String dartFile) async {
    print('Building $dartFile');
    String activity;
    try {
      activity = 'compile $dartFile';
      var program = await buildProgram(dartFile);
      if (verify) {
        activity = 'verify $dartFile';
        verifyProgram(program);
      }
      var binaryFile = getBinaryPathForDartFile(dartFile);
      activity = 'create directory for $binaryFile';
      await new Directory(dirname(binaryFile)).create(recursive: true);
      activity = 'write binary to $binaryFile';
      writeProgramToBinary(program, binaryFile);
      print('Finished building $dartFile to $binaryFile');
    } catch (e) {
      print('Failed to $activity');
      print(e);
    }
  }

  Future removeBuildArtifactsForDartFile(String dartFile) async {
    print('Removing build artifacts for $dartFile');
    return deleteBinaryFile(getBinaryPathForDartFile(dartFile));
  }

  Future deleteBinaryFile(String binaryFile) async {
    if (!binaryFile.endsWith('.dill')) {
      // Sanity check to prevent data loss.
      throw "Refusing to remove non-dill file '$binaryFile'";
    }
    return new File(binaryFile).delete();
  }
}
