import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:process_run/shell.dart';
import 'package:ink_flutter_runtime/ink_flutter_runtime.dart';
import 'package:ink_flutter_runtime/story.dart';
import 'package:process_run/process_run.dart';
import 'package:ink_flutter_runtime/error.dart';

enum TestMode { Normal, JsonRoundTrip }

class Tests {
  TestMode _mode;
  bool _testingErrors = false;
  List _errorMessages = [];
  List _warningMessages = [];
  List _authorMessages = [];

  var shell = Shell();

  Tests(this._mode);

  getFileData(String file) {
    return File(file).readAsStringSync();
  }

  Story CompileString(String str,
      [bool countAllVisits = false, bool testingErrors = false]) {
    _testingErrors = testingErrors;
    _errorMessages.clear();
    _warningMessages.clear();
    _authorMessages.clear();

    File('/home/potuo/my/works/gugu/c-ink/ink_flutter_runtimeink/cache/xx.ink')
        .writeAsStringSync(str);

    shell.run(
        r"echo $(mono /home/potuo/my/works/gugu/c-ink/ink_flutter_runtime/ink/inklecate -j /home/potuo/my/works/gugu/c-ink/ink_flutter_runtime/cache/xx.ink) > /home/potuo/my/works/gugu/c-ink/ink_flutter_runtime/cache/story.json");

    String storyjson = getFileData(
            "/home/potuo/my/works/gugu/c-ink/ink_flutter_runtime/cache/story.json")
        .toString();
    print("xxx\n\n");
    print(storyjson);
    print("\n\nxxx");
    Story story = Story(storyjson);

    if (!testingErrors) {
      assert(story != null);
    }

    story.onError.addListener(OnError);

    // Convert to json and back again
    if (_mode == TestMode.JsonRoundTrip) {
      var jsonStr = story.ToJson();
      story = new Story(jsonStr);
      story.onError.addListener(OnError);
    }

    return story;
  }

  void OnError(String message, ErrorType errorType) {
    if (_testingErrors) {
      if (errorType == ErrorType.Error)
        _errorMessages.add(message);
      else if (errorType == ErrorType.Warning)
        _warningMessages.add(message);
      else
        _authorMessages.add(message);
    } else
      throw Exception(message);
  }
}

void main() {
  Tests tests = new Tests(TestMode.Normal);
  test('adds one to input values', () {
    var shell = Shell();
    shell.run('''
touch /home/potuo/test
touch /home/potuo/test2
''');
    final calculator = Calculator();
    expect(calculator.addOne(2), 3);
    expect(calculator.addOne(-7), -6);
    expect(calculator.addOne(0), 1);
  });
  test('=====TEST_001_END=====', () {
    var storyStr = r"""
-> once ->
-> once ->

== once ==
{<- content|}
->->o

== content ==
Content
-> DONE
""";

    Story story = tests.CompileString(storyStr);

    expect("Content\n", story.Continue());
  });
}
