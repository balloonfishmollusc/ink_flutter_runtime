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

  bool HadError([String? matchStr = null]) {
    return HadErrorOrWarning(matchStr, _errorMessages);
  }

  bool HadErrorOrWarning(String? matchStr, List list) {
    if (matchStr == null) return list.length > 0;

    for (var str in list) {
      if (str.contains(matchStr)) return true;
    }
    return false;
  }

  bool HadWarning([String? matchStr = null]) {
    return HadErrorOrWarning(matchStr, _warningMessages);
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
    expect(story.ContinueMaximally(), r'''Once: one two
Stopping: one two two two
Default: one two two two
Cycle: one two one two
Shuffle: two one one two
Shuffle stopping: two one final final
Shuffle once: one two
''');
  });

  test("TestCallStackEvaluation", () async {
    var storyStr = r'''
                   { six() + two() }
                    -> END

                === function six
                    ~ return four() + two()

                === function four
                    ~ return two() + two()

                === function two
                    ~ return 2
''';

    Story story = await tests.CompileString(storyStr);
    expect(story.Continue(), r'''8
''');
  });

  test("TestChoiceCount", () async {
    Story story = await tests.CompileString(r'''
<- choices
{ CHOICE_COUNT() }

= end
-> END

= choices
* one -> end
* two -> end
''');
    expect(story.ContinueMaximally(), r'''2
''');
  });

  test("TestChoiceDivertsToDone", () async {
    var story = await tests.CompileString(r'* choice -> DONE');
    story.Continue();

    expect(story.currentChoices.length, 1);
    story.ChooseChoiceIndex(0);

    expect(story.Continue(), 'choice');
  });

  test("TestChoiceWithBracketsOnly", () async {
    var storyStr = '*   [Option]\n    Text';

    Story story = await tests.CompileString(storyStr);
    story.Continue();

    expect(story.currentChoices.length, 1);
    expect(story.currentChoices[0].text, 'Option');

    story.ChooseChoiceIndex(0);

    expect(story.Continue(), r'''Text
''');
  });

  test("TestCompareDivertTargets", () async {
    var storyStr = r'''
VAR to_one = -> one
VAR to_two = -> two

{to_one == to_two:same knot|different knot}
{to_one == to_one:same knot|different knot}
{to_two == to_two:same knot|different knot}
{ -> one == -> two:same knot|different knot}
{ -> one == to_one:same knot|different knot}
{ to_one == -> one:same knot|different knot}

== one
    One
    -> DONE

=== two
    Two
    -> DONE''';

    Story story = await tests.CompileString(storyStr);

    expect(story.ContinueMaximally(),
        'different knot\nsame knot\nsame knot\ndifferent knot\nsame knot\nsame knot\n');
  });

  test("TestComplexTunnels", () async {
    Story story = await tests.CompileString(r'''
-> one (1) -> two (2) ->
three (3)

== one(num) ==
one ({num})
-> oneAndAHalf (1.5) ->
->->

== oneAndAHalf(num) ==
one and a half ({num})
->->

== two (num) ==
two ({num})
->->
''');

    expect(story.ContinueMaximally(),
        'one (1)\none and a half (1.5)\ntwo (2)\nthree (3)\n');
  });

  test("TestConditionalChoiceInWeave", () async {
    var storyStr = r'''
- start
 {
    - true: * [go to a stitch] -> a_stitch
 }
- gather should be seen
-> DONE

= a_stitch
    result
    -> END
                ''';

    Story story = await tests.CompileString(storyStr);

    expect(story.ContinueMaximally(), 'start\ngather should be seen\n');
    expect(story.currentChoices.length, 1);

    story.ChooseChoiceIndex(0);

    expect(story.Continue(), "result\n");
  });

  test("TestConditionalChoiceInWeave2", () async {
    var storyStr = r'''
- first gather
    * [option 1]
    * [option 2]
- the main gather
{false:
    * unreachable option -> END
}
- bottom gather''';

    Story story = await tests.CompileString(storyStr);

    expect("first gather\n", story.Continue());

    expect(2, story.currentChoices.length);

    story.ChooseChoiceIndex(0);

    expect("the main gather\nbottom gather\n", story.ContinueMaximally());
    expect(0, story.currentChoices.length);
  });

  test("TestConditionalChoices", () async {
    var storyStr = r'''
* { true } { false } not displayed
* { true } { true }
  { true and true }  one
* { false } not displayed
* (name) { true } two
* { true }
  { true }
  three
* { true }
  four
                ''';

    Story story = await tests.CompileString(storyStr);
    story.ContinueMaximally();

    expect(4, story.currentChoices.length);
    expect("one", story.currentChoices[0].text);
    expect("two", story.currentChoices[1].text);
    expect("three", story.currentChoices[2].text);
    expect("four", story.currentChoices[3].text);
  });

  test("TestConditionals", () async {
    var storyStr = r'''
{false:not true|true}
{
   - 4 > 5: not true
   - 5 > 4: true
}
{ 2*2 > 3:
   - true
   - not true
}
{
   - 1 > 3: not true
   - { 2+2 == 4:
        - true
        - not true
   }
}
{ 2*3:
   - 1+7: not true
   - 9: not true
   - 1+1+1+3: true
   - 9-3: also true but not printed
}
{ true:
    great
    right?
}
                ''';

    Story story = await tests.CompileString(storyStr);

    expect("true\ntrue\ntrue\ntrue\ntrue\ngreat\nright?\n",
        story.ContinueMaximally());
  });

  test("TestConst", () async {
    var story = await tests.CompileString(r'''
VAR x = c

CONST c = 5

{x}
''');
    expect("5\n", story.Continue());
  });

  test("TestDefaultChoices", () async {
    Story story = await tests.CompileString(r'''
 - (start)
 * [Choice 1]
 * [Choice 2]
 * {false} Impossible choice
 * -> default
 - After choice
 -> start

== default ==
This is default.
-> DONE
''');

    expect("", story.Continue());
    expect(2, story.currentChoices.length);

    story.ChooseChoiceIndex(0);
    expect("After choice\n", story.Continue());

    expect(1, story.currentChoices.length);

    story.ChooseChoiceIndex(0);
    expect("After choice\nThis is default.\n", story.ContinueMaximally());
  });

  test("TestDefaultSimpleGather", () async {
    var story = await tests.CompileString(r'''
* ->
- x
-> DONE''');

    expect("x\n", story.Continue());
  });

  test("TestDivertInConditional", () async {
    var storyStr = r'''
=== intro
= top
    { main: -> done }
    -> END
= main
    -> top
= done
    -> END
                ''';

    Story story = await tests.CompileString(storyStr);
    expect("", story.ContinueMaximally());
  });

  test("TestDivertToWeavePoints", () async {
    var storyStr = r'''
-> knot.stitch.gather

== knot ==
= stitch
- hello
    * (choice) test
        choice content
- (gather)
  gather

  {stopping:
    - -> knot.stitch.choice
    - second time round
  }

-> END
                ''';

    Story story = await tests.CompileString(storyStr);

    expect("gather\ntest\nchoice content\ngather\nsecond time round\n",
        story.ContinueMaximally());
  });

  test("TestElseBranches", () async {
    var storyStr = r'''
VAR x = 3

{
    - x == 1: one
    - x == 2: two
    - else: other
}

{
    - x == 1: one
    - x == 2: two
    - other
}

{ x == 4:
  - The main clause
  - else: other
}

{ x == 4:
  The main clause
- else:
  other
}
''';

    Story story = await tests.CompileString(storyStr);

    expect("other\nother\nother\nother\n", story.ContinueMaximally());
  });

  test("TestEmpty", () async {
    Story story = await tests.CompileString(r"");

    expect('', story.currentText);
  });
  test("TestEmptyMultilineConditionalBranch", () async {
    var story = await tests.CompileString(r'''
{ 3:
    - 3:
    - 4:
        txt
}
''');

    expect("", story.Continue());
  });
  test("TestAllSwitchBranchesFailIsClean", () async {
    var story = await tests.CompileString(r'''
{ 1:
    - 2: x
    - 3: y
}
        ''');

    story.Continue();

    expect(story.state.evaluationStack.length, 0);
  });
  test("TestTrivialCondition", () async {
    var story = await tests.CompileString(r'''
{
- false:
   beep
}
                ''');

    story.Continue();
  });
  test("TestEmptySequenceContent", () async {
    var story = await tests.CompileString(r'''
-> thing ->
-> thing ->
-> thing ->
-> thing ->
-> thing ->
Done.

== thing ==
{once:
  - Wait for it....
  -
  -
  -  Surprise!
}
->->
''');
    expect("Wait for it....\nSurprise!\nDone.\n", story.ContinueMaximally());
  });
  test("TestEnd", () async {
    Story story = await tests.CompileString(r'''
hello
-> END
world
-> END
''');

    expect("hello\n", story.ContinueMaximally());
  });
  test("TestEnd2", () async {
    Story story = await tests.CompileString(r'''
-> test

== test ==
hello
-> END
world
-> END
''');

    expect("hello\n", story.ContinueMaximally());
  });

  test("name", () async {});
}
