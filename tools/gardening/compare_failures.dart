// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Compares the test log of a build step with previous builds.
///
/// Use this to detect flakiness of failures, especially timeouts.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

main(List<String> args) async {
  if (args.length != 1) {
    print('Usage: compare_failures <log-uri>');
    exit(1);
  }
  String url = args.first;
  if (!url.endsWith('/text')) {
    // Use the text version of the stdio log.
    url += '/text';
  }
  Uri uri = Uri.parse(url);
  HttpClient client = new HttpClient();
  BuildUri buildUri = new BuildUri(uri);
  List<BuildResult> results = await readBuildResults(client, buildUri);
  print(generateBuildResultsSummary(buildUri, results));
  client.close();
}

/// Creates a [BuildResult] for [buildUri] and, if it contains failures, the
/// [BuildResult]s for the previous 5 builds.
Future<List<BuildResult>> readBuildResults(
    HttpClient client, BuildUri buildUri) async {
  List<BuildResult> summaries = <BuildResult>[];
  BuildResult firstSummary = await readBuildResult(client, buildUri);
  summaries.add(firstSummary);
  if (firstSummary.hasFailures) {
    for (int i = 0; i < 5; i++) {
      buildUri = buildUri.prev();
      summaries.add(await readBuildResult(client, buildUri));
    }
  }
  return summaries;
}

/// Reads the content of [uri] as text.
Future<String> readUriAsText(HttpClient client, Uri uri) async {
  HttpClientRequest request = await client.getUrl(uri);
  HttpClientResponse response = await request.close();
  return UTF8.decode(await response.expand((l) => l).toList());
}

/// Parses the [buildUri] test log and creates a [BuildResult] for it.
Future<BuildResult> readBuildResult(
    HttpClient client, BuildUri buildUri) async {
  Uri uri = buildUri.toUri();
  log('Reading $uri');
  String text = await readUriAsText(client, uri);

  bool inFailure = false;
  List<String> currentFailure;
  bool parsingTimingBlock = false;

  List<TestFailure> failures = <TestFailure>[];
  List<Timing> timings = <Timing>[];
  for (String line in text.split('\n')) {
    if (currentFailure != null) {
      if (line.startsWith('!@@@STEP_CLEAR@@@')) {
        failures.add(new TestFailure(buildUri, currentFailure));
        currentFailure = null;
      } else {
        currentFailure.add(line);
      }
    } else if (inFailure && line.startsWith('@@@STEP_FAILURE@@@')) {
      inFailure = false;
    } else if (line.startsWith('!@@@STEP_FAILURE@@@')) {
      inFailure = true;
    } else if (line.startsWith('FAILED:')) {
      currentFailure = <String>[];
      currentFailure.add(line);
    }
    if (line.startsWith('--- Total time:')) {
      parsingTimingBlock = true;
    } else if (parsingTimingBlock) {
      if (line.startsWith('0:')) {
        timings.addAll(parseTimings(buildUri, line));
      } else {
        parsingTimingBlock = false;
      }
    }
  }
  return new BuildResult(buildUri, failures, timings);
}

/// Generate a summary of the timeouts and other failures in [results].
String generateBuildResultsSummary(
    BuildUri buildUri, List<BuildResult> results) {
  StringBuffer sb = new StringBuffer();
  sb.write('Results for $buildUri:\n');
  Set<TestConfiguration> timeoutIds = new Set<TestConfiguration>();
  for (BuildResult result in results) {
    timeoutIds.addAll(result.timeouts.map((TestFailure failure) => failure.id));
  }
  if (timeoutIds.isNotEmpty) {
    int firstBuildNumber = results.first.buildUri.buildNumber;
    int lastBuildNumber = results.last.buildUri.buildNumber;
    Map<TestConfiguration, Map<int, Map<String, Timing>>> map =
        <TestConfiguration, Map<int, Map<String, Timing>>>{};
    Set<String> stepNames = new Set<String>();
    for (BuildResult result in results) {
      for (Timing timing in result.timings) {
        Map<int, Map<String, Timing>> builds =
            map.putIfAbsent(timing.step.id, () => <int, Map<String, Timing>>{});
        stepNames.add(timing.step.stepName);
        builds.putIfAbsent(timing.uri.buildNumber, () => <String, Timing>{})[
            timing.step.stepName] = timing;
      }
    }
    sb.write('Timeouts for ${buildUri} :\n');
    map.forEach((TestConfiguration id, Map<int, Map<String, Timing>> timings) {
      if (!timeoutIds.contains(id)) return;
      sb.write('$id\n');
      sb.write(
          '${' ' * 8} ${stepNames.map((t) => padRight(t, 14)).join(' ')}\n');
      for (int buildNumber = firstBuildNumber;
          buildNumber >= lastBuildNumber;
          buildNumber--) {
        Map<String, Timing> steps = timings[buildNumber] ?? const {};
        sb.write(padRight(' ${buildNumber}: ', 8));
        for (String stepName in stepNames) {
          Timing timing = steps[stepName];
          if (timing != null) {
            sb.write(' ${timing.time}');
          } else {
            sb.write(' --------------');
          }
        }
        sb.write('\n');
      }
      sb.write('\n');
    });
  }
  Set<TestConfiguration> errorIds = new Set<TestConfiguration>();
  for (BuildResult result in results) {
    errorIds.addAll(result.errors.map((TestFailure failure) => failure.id));
  }
  if (errorIds.isNotEmpty) {
    int firstBuildNumber = results.first.buildUri.buildNumber;
    int lastBuildNumber = results.last.buildUri.buildNumber;
    Map<TestConfiguration, Map<int, TestFailure>> map =
        <TestConfiguration, Map<int, TestFailure>>{};
    for (BuildResult result in results) {
      for (TestFailure failure in result.errors) {
        map.putIfAbsent(failure.id, () => <int, TestFailure>{})[
            failure.uri.buildNumber] = failure;
      }
    }
    sb.write('Errors for ${buildUri} :\n');
    // TODO(johnniwinther): Improve comparison of non-timeouts.
    map.forEach((TestConfiguration id, Map<int, TestFailure> failures) {
      if (!errorIds.contains(id)) return;
      sb.write('$id\n');
      for (int buildNumber = firstBuildNumber;
          buildNumber >= lastBuildNumber;
          buildNumber--) {
        TestFailure failure = failures[buildNumber];
        sb.write(padRight(' ${buildNumber}: ', 8));
        if (failure != null) {
          sb.write(padRight(failure.expected, 10));
          sb.write(' / ');
          sb.write(padRight(failure.actual, 10));
        } else {
          sb.write(' ' * 10);
          sb.write(' / ');
          sb.write(padRight('-- OK --', 10));
        }
        sb.write('\n');
      }
      sb.write('\n');
    });
  }
  return sb.toString();
}

/// The results of a build step.
class BuildResult {
  final BuildUri buildUri;
  final List<TestFailure> _failures;
  final List<Timing> _timings;

  BuildResult(this.buildUri, this._failures, this._timings);

  /// `true` of the build result has test failures.
  bool get hasFailures => _failures.isNotEmpty;

  /// Returns the top-20 timings found in the build log.
  Iterable<Timing> get timings => _timings;

  /// Returns the [TestFailure]s for tests that timed out.
  Iterable<TestFailure> get timeouts {
    return _failures
        .where((TestFailure failure) => failure.actual == 'Timeout');
  }

  /// Returns the [TestFailure]s for failing tests that did not time out.
  Iterable<TestFailure> get errors {
    return _failures
        .where((TestFailure failure) => failure.actual != 'Timeout');
  }

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('$buildUri\n');
    sb.write('Failures:\n${_failures.join('\n-----\n')}\n');
    sb.write('\nTimings:\n${_timings.join('\n')}');
    return sb.toString();
  }
}

/// The [Uri] of a build step stdio log split into its subparts.
class BuildUri {
  final String scheme;
  final String host;
  final String prefix;
  final String botName;
  final int buildNumber;
  final String stepName;
  final String suffix;

  factory BuildUri(Uri uri) {
    String scheme = uri.scheme;
    String host = uri.host;
    List<String> parts =
        split(uri.path, ['/builders/', '/builds/', '/steps/', '/logs/']);
    String prefix = parts[0];
    String botName = parts[1];
    int buildNumber = int.parse(parts[2]);
    String stepName = parts[3];
    String suffix = parts[4];
    return new BuildUri.internal(
        scheme, host, prefix, botName, buildNumber, stepName, suffix);
  }

  BuildUri.internal(this.scheme, this.host, this.prefix, this.botName,
      this.buildNumber, this.stepName, this.suffix);

  String get buildName =>
      '/builders/$botName/builds/$buildNumber/steps/$stepName';

  String get path => '$prefix$buildName/logs/$suffix';

  /// Creates the [Uri] for this build step stdio log.
  Uri toUri() {
    return new Uri(scheme: scheme, host: host, path: path);
  }

  /// Returns the [BuildUri] the previous build of this build step.
  BuildUri prev() {
    return new BuildUri.internal(
        scheme, host, prefix, botName, buildNumber - 1, stepName, suffix);
  }

  String toString() {
    return buildName;
  }
}

/// Id for a test on a specific configuration, for instance
/// `dart2js-chrome release_x64/co19/Language/Metadata/before_function_t07`.
class TestConfiguration {
  final String configName;
  final String testName;

  TestConfiguration(this.configName, this.testName);

  String toString() {
    return '$configName $testName';
  }

  int get hashCode => configName.hashCode * 17 + testName.hashCode * 19;

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! TestConfiguration) return false;
    return configName == other.configName && testName == other.testName;
  }
}

/// Test failure data derived from the test failure summary in the build step
/// stdio log.
class TestFailure {
  final BuildUri uri;
  final TestConfiguration id;
  final String expected;
  final String actual;
  final String text;

  factory TestFailure(BuildUri uri, List<String> lines) {
    List<String> parts = split(lines.first, ['FAILED: ', ' ', ' ']);
    String configName = parts[1];
    String archName = parts[2];
    String testName = parts[3];
    TestConfiguration id =
        new TestConfiguration(configName, '$archName/$testName');
    String expected = split(lines[1], ['Expected: '])[1];
    String actual = split(lines[2], ['Actual: '])[1];
    return new TestFailure.internal(
        uri, id, expected, actual, lines.skip(3).join('\n'));
  }

  TestFailure.internal(
      this.uri, this.id, this.expected, this.actual, this.text);

  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('FAILED: $id\n');
    sb.write('Expected: $expected\n');
    sb.write('Actual: $actual\n');
    sb.write(text);
    return sb.toString();
  }
}

/// Id for a single test step, for instance the compilation and run steps of
/// a test.
class TestStep {
  final String stepName;
  final TestConfiguration id;

  TestStep(this.stepName, this.id);

  String toString() {
    return '$stepName - $id';
  }

  int get hashCode => stepName.hashCode * 13 + id.hashCode * 17;

  bool operator ==(other) {
    if (identical(this, other)) return true;
    if (other is! TestStep) return false;
    return stepName == other.stepName && id == other.id;
  }
}

/// The timing result for a single test step.
class Timing {
  final BuildUri uri;
  final String time;
  final TestStep step;

  Timing(this.uri, this.time, this.step);

  String toString() {
    return '$time - $step';
  }
}

/// Create the [Timing]s for the [line] as found in the top-20 timings of a
/// build step stdio log.
List<Timing> parseTimings(BuildUri uri, String line) {
  List<String> parts = split(line, [' - ', ' - ', ' ']);
  String time = parts[0];
  String stepName = parts[1];
  String configName = parts[2];
  String testNames = parts[3];
  List<Timing> timings = <Timing>[];
  for (String testName in testNames.split(',')) {
    timings.add(new Timing(
        uri,
        time,
        new TestStep(
            stepName, new TestConfiguration(configName, testName.trim()))));
  }
  return timings;
}

/// Split [text] using [infixes] as infix markers.
List<String> split(String text, List<String> infixes) {
  List<String> result = <String>[];
  int start = 0;
  for (String infix in infixes) {
    int index = text.indexOf(infix, start);
    if (index == -1)
      throw "'$infix' not found in '$text' from offset ${start}.";
    result.add(text.substring(start, index));
    start = index + infix.length;
  }
  result.add(text.substring(start));
  return result;
}

/// Pad [text] with spaces to the right to fit [length].
String padRight(String text, int length) {
  if (text.length < length) return '${text}${' ' * (length - text.length)}';
  return text;
}

void log(String text) {
  print(text);
}
