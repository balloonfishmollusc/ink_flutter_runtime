import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:process_run/shell.dart';
import 'package:ink_flutter_runtime/ink_flutter_runtime.dart';
import 'package:ink_flutter_runtime/story.dart';
import 'package:ink_flutter_runtime/error.dart';
import 'package:http/http.dart' as http;

enum TestMode { Normal, JsonRoundTrip }

class Tests {
  final TestMode _mode;
  bool _testingErrors = false;
  final List _errorMessages = [];
  final List _warningMessages = [];
  final List _authorMessages = [];

  var shell = Shell();

  Tests(this._mode);

  getFileData(String file) {
    return File(file).readAsStringSync();
  }

  Future<Story> CompileString(String str,
      [bool countAllVisits = false, bool testingErrors = false]) async {
    _testingErrors = testingErrors;
    _errorMessages.clear();
    _warningMessages.clear();
    _authorMessages.clear();

    var resp = await http.post(
        Uri.parse("https://inkycloud.bluel.fun/ink/compile"),
        body: jsonEncode({"main.ink": str}));
    assert(resp.statusCode == 200);

    var dict = jsonDecode(resp.body);
    String? inkJson = dict['ink_json'];
    dynamic result = dict['result'];

    if (result['compile-success'] != true) {
      print(result['issues']);
      throw Exception("编译失败");
    }

    Story story = Story(inkJson!);

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

    await tests.CompileString(storyStr).then((story) {
      expect(story.ContinueMaximally(), "36\n2\n3\n2\n2.3333333333333335\n8\n8");
    });
  });
}
