import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:process_run/shell.dart';
import 'package:ink_flutter_runtime/story.dart';
import 'package:ink_flutter_runtime/error.dart';

enum TestMode { Normal, JsonRoundTrip }

class Tests {
  final TestMode _mode;
  bool _testingErrors = false;
  final List _errorMessages = [];
  final List _warningMessages = [];
  final List _authorMessages = [];

  Tests(this._mode);

  Future<Story> CompileString(String str,
      [bool countAllVisits = false, bool testingErrors = false]) async {
    _testingErrors = testingErrors;
    _errorMessages.clear();
    _warningMessages.clear();
    _authorMessages.clear();

    var cacheDir = Directory("test/cache");
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    cacheDir.createSync();

    File("${cacheDir.path}/main.ink").writeAsStringSync(str);

    var shell = Shell(workingDirectory: "test");
    var processResults = await shell.run(
        "${Platform.isWindows ? 'dotnet' : 'mono'} ./inklecate.dll -j cache/main.ink");

    String shellOutput = processResults.first.outText;
    if (!shellOutput.contains('{"compile-success": true}')) {
      print(shellOutput);
      throw Exception("编译失败");
    }

    String inkJson = File("${cacheDir.path}/main.ink.json").readAsStringSync();
    Story story = Story(inkJson);

    story.onError.addListener(OnError);

    // Convert to json and back again
    if (_mode == TestMode.JsonRoundTrip) {
      var jsonStr = story.ToJson();
      story = Story(jsonStr);
      story.onError.addListener(OnError);
    }

    return story;
  }

  void OnError(String message, ErrorType errorType) {
    if (_testingErrors) {
      if (errorType == ErrorType.Error) {
        _errorMessages.add(message);
      } else if (errorType == ErrorType.Warning) {
        _warningMessages.add(message);
      } else {
        _authorMessages.add(message);
      }
    } else {
      throw Exception(message);
    }
  }
}

void main() {
  Tests tests = Tests(TestMode.Normal);

  test('TestArithmetic', () async {
    var storyStr = r"""
{ 2 * 3 + 5 * 6 }
{8 mod 3}
{13 % 5}
{ 7 / 3 }
{ 7 / 3.0 }
{ 10 - 2 }
{ 2 * (5-1) }
""";
    var story = await tests.CompileString(storyStr);
    expect(story.ContinueMaximally(), "36\n2\n3\n2\n2.3333333\n8\n8\n");
  });
}
