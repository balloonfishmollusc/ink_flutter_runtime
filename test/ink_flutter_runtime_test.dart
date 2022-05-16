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

  Future<Story> CompileString(String str, {bool testingErrors = false}) async {
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

  test("TestBasicStringLiterals", () async {
    var story = await tests.CompileString(r'''
VAR x = "Hello world 1"
{x}
Hello {"world"} 2.
''');
    expect(story.ContinueMaximally(), "Hello world 1\nHello world 2.\n");
  });

  test("TestBasicTunnel", () async {
    Story story = await tests.CompileString(r'''
-> f ->
<> world

== f ==
Hello
->->
''');

    expect(story.Continue(), "Hello world\n");
  });

  test("TestBlanksInInlineSequences", () async {
    var story = await tests.CompileString(r'''
1. -> seq1 ->
2. -> seq1 ->
3. -> seq1 ->
4. -> seq1 ->
\---
1. -> seq2 ->
2. -> seq2 ->
3. -> seq2 ->
\---
1. -> seq3 ->
2. -> seq3 ->
3. -> seq3 ->
\---
1. -> seq4 ->
2. -> seq4 ->
3. -> seq4 ->

== seq1 ==
{a||b}
->->

== seq2 ==
{|a}
->->

== seq3 ==
{a|}
->->

== seq4 ==
{|}
->->''');

    expect(story.ContinueMaximally(), r'''
1. a
2.
3. b
4. b
---
1.
2. a
3. a
---
1. a
2.
3.
---
1.
2.
3.
''');
  });

  test("TestAllSequenceTypes", () async {
    var storyStr = r'''
~ SEED_RANDOM(1)

Once: {f_once()} {f_once()} {f_once()} {f_once()}
Stopping: {f_stopping()} {f_stopping()} {f_stopping()} {f_stopping()}
Default: {f_default()} {f_default()} {f_default()} {f_default()}
Cycle: {f_cycle()} {f_cycle()} {f_cycle()} {f_cycle()}
Shuffle: {f_shuffle()} {f_shuffle()} {f_shuffle()} {f_shuffle()}
Shuffle stopping: {f_shuffle_stopping()} {f_shuffle_stopping()} {f_shuffle_stopping()} {f_shuffle_stopping()}
Shuffle once: {f_shuffle_once()} {f_shuffle_once()} {f_shuffle_once()} {f_shuffle_once()}

== function f_once ==
{once:
    - one
    - two
}

== function f_stopping ==
{stopping:
    - one
    - two
}

== function f_default ==
{one|two}

== function f_cycle ==
{cycle:
    - one
    - two
}

== function f_shuffle ==
{shuffle:
    - one
    - two
}

== function f_shuffle_stopping ==
{stopping shuffle:
    - one
    - two
    - final
}

== function f_shuffle_once ==
{shuffle once:
    - one
    - two
}
                ''';

    Story story = await tests.CompileString(storyStr);
    expect(story.ContinueMaximally(),
        r'''Once: one two
Stopping: one two two two
Default: one two two two
Cycle: one two one two
Shuffle: two one one two
Shuffle stopping: two one final final
Shuffle once: one two
''');
  });
}
