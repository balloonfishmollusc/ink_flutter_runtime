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

    var resp = await http
        .post(Uri.parse("https://inkycloud.bluel.fun/ink/compile"),
            body: jsonEncode({"main.ink": str}))
        .timeout(const Duration(seconds: 3));
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
  test("Story Load", () {
    String json =
        r'''{"inkVersion":20,"root":[["ev",2,3,"*",5,6,"*","+","out","/ev","\n","ev",8,3,"%","out","/ev","\n","ev",13,5,"%","out","/ev","\n","ev",7,3,"/","out","/ev","\n","ev",7,3.0,"/","out","/ev","\n","ev",10,2,"-","out","/ev","\n","ev",2,5,1,"-","*","out","/ev","\n",["done",{"#n":"g-0"}],null],"done",null],"listDefs":{}}''';
    var story = Story(json);
    expect(story.ContinueMaximally(), "36\n2\n3\n2\n2.3333333\n8\n8\n");
  });

  Tests tests = Tests(TestMode.JsonRoundTrip);
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
      print("Story loaded!");
      expect(story.ContinueMaximally(), "36\n2\n3\n2\n2.3333333\n8\n8\n");
    });
  });

  test("TestMemoryLeak", () async {
    var storyStr = r'''
Once upon a time...

 * There were two choices.
 * There were four lines of content.

- They lived happily ever after.
    -> END
''';

    await tests.CompileString(storyStr).then((story) {
      expect(story.Continue(), "Once upon a time...");
    });
  });
}
