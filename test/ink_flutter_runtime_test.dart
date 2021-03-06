import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_flutter_runtime/addons/extra.dart';
import 'package:ink_flutter_runtime/story.dart';
import 'package:ink_flutter_runtime/error.dart';
import 'package:ink_flutter_runtime/story_exception.dart';

enum TestMode { Normal, JsonRoundTrip }

void assertError<E extends Exception>(Function fn, [String? msg]) {
  try {
    fn();
    assert(false);
  } on E catch (e) {
    if (msg != null) {
      expect(e.toString().contains(msg), true);
    }
  }
}

class Tests {
  final TestMode _mode;
  bool _testingErrors = false;
  final List _errorMessages = [];
  final List _warningMessages = [];
  final List _authorMessages = [];

  Tests(this._mode);

  Story CompileString(String str,
      {bool countAllVisits = false,
      bool testingErrors = false,
      bool copyIncludes = false,
      bool printInkJson = false}) {
    _testingErrors = testingErrors;
    _errorMessages.clear();
    _warningMessages.clear();
    _authorMessages.clear();

    var cacheDir = Directory("test/cache");
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    cacheDir.createSync();

    if (copyIncludes) {
      if (Platform.isWindows) {
        Process.runSync("robocopy", ["./", "./cache", "*.ink"],
            workingDirectory: "test");
      } else {
        Process.runSync("sh", ["-c", "cp test*.ink cache/"],
            workingDirectory: "test");
      }
    }

    File("${cacheDir.path}/main.ink").writeAsStringSync(str);

    List<String> compileParams = ["./inklecate.dll", "-j", "cache/main.ink"];
    if (countAllVisits) compileParams.insert(1, "-c");

    var processResult = Process.runSync(
        Platform.isWindows ? 'dotnet' : 'mono', compileParams,
        workingDirectory: 'test');

    String shellOutput = processResult.stdout;
    if (!shellOutput.contains('{"compile-success": true}')) {
      throw Exception("编译失败！\n" + shellOutput);
    }

    String inkJson = File("${cacheDir.path}/main.ink.json").readAsStringSync();

    // ignore: avoid_print
    if (printInkJson) print(inkJson);

    Story story = Story(inkJson);

    story.onError.addListener(OnError);

    //print(inkJson);

    // Convert to json and back again
    if (_mode == TestMode.JsonRoundTrip) {
      var jsonStr = story.ToJson();
      //print(jsonStr);
      story = Story(jsonStr);
      story.onError.addListener(OnError);
    }

    return story;
  }

  bool HadError([String? matchStr]) {
    return HadErrorOrWarning(matchStr, _errorMessages);
  }

  bool HadErrorOrWarning(String? matchStr, List list) {
    if (matchStr == null) return list.isNotEmpty;
    for (var str in list) {
      if (str.contains(matchStr)) return true;
    }
    return false;
  }

  bool HadWarning([String? matchStr]) {
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

  test('TestArithmetic', () {
    var storyStr = r"""
{ 2 * 3 + 5 * 6 }
{8 mod 3}
{13 % 5}
{ 7 / 3 }
{ 7 / 3.0 }
{ 10 - 2 }
{ 2 * (5-1) }
""";
    var story = tests.CompileString(storyStr);
    expect(story.ContinueMaximally(), "36\n2\n3\n2\n2.3333333\n8\n8\n");
  });

  test("TestBasicStringLiterals", () {
    var story = tests.CompileString(r'''
VAR x = "Hello world 1"
{x}
Hello {"world"} 2.
''');
    expect(story.ContinueMaximally(), "Hello world 1\nHello world 2.\n");
  });

  test("TestBasicTunnel", () {
    Story story = tests.CompileString(r'''
-> f ->
<> world

== f ==
Hello
->->
''');

    expect(story.Continue(), "Hello world\n");
  });

  test("TestBlanksInInlineSequences", () {
    var story = tests.CompileString(r'''
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

  test("TestAllSequenceTypes", () {
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

    Story story = tests.CompileString(storyStr);
    expect(story.ContinueMaximally(), r'''Once: one two
Stopping: one two two two
Default: one two two two
Cycle: one two one two
Shuffle: two one one two
Shuffle stopping: two one final final
Shuffle once: one two
''');
  });

  test("TestCallStackEvaluation", () {
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

    Story story = tests.CompileString(storyStr);
    expect(story.Continue(), r'''8
''');
  });

  test("TestChoiceCount", () {
    Story story = tests.CompileString(r'''
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

  test("TestChoiceDivertsToDone", () {
    var story = tests.CompileString(r'* choice -> DONE');
    story.Continue();

    expect(story.currentChoices.length, 1);
    story.ChooseChoiceIndex(0);

    expect(story.Continue(), 'choice');
  });

  test("TestChoiceWithBracketsOnly", () {
    var storyStr = '*   [Option]\n    Text';

    Story story = tests.CompileString(storyStr);
    story.Continue();

    expect(story.currentChoices.length, 1);
    expect(story.currentChoices[0].text, 'Option');

    story.ChooseChoiceIndex(0);

    expect(story.Continue(), r'''Text
''');
  });

  test("TestCompareDivertTargets", () {
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

    Story story = tests.CompileString(storyStr);

    expect(story.ContinueMaximally(),
        'different knot\nsame knot\nsame knot\ndifferent knot\nsame knot\nsame knot\n');
  });

  test("TestComplexTunnels", () {
    Story story = tests.CompileString(r'''
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

  test("TestConditionalChoiceInWeave", () {
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

    Story story = tests.CompileString(storyStr);

    expect(story.ContinueMaximally(), 'start\ngather should be seen\n');
    expect(story.currentChoices.length, 1);

    story.ChooseChoiceIndex(0);

    expect(story.Continue(), "result\n");
  });

  test("TestConditionalChoiceInWeave2", () {
    var storyStr = r'''
- first gather
    * [option 1]
    * [option 2]
- the main gather
{false:
    * unreachable option -> END
}
- bottom gather''';

    Story story = tests.CompileString(storyStr);

    expect("first gather\n", story.Continue());

    expect(2, story.currentChoices.length);

    story.ChooseChoiceIndex(0);

    expect("the main gather\nbottom gather\n", story.ContinueMaximally());
    expect(0, story.currentChoices.length);
  });

  test("TestConditionalChoices", () {
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

    Story story = tests.CompileString(storyStr);
    story.ContinueMaximally();

    expect(4, story.currentChoices.length);
    expect("one", story.currentChoices[0].text);
    expect("two", story.currentChoices[1].text);
    expect("three", story.currentChoices[2].text);
    expect("four", story.currentChoices[3].text);
  });

  test("TestConditionals", () {
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

    Story story = tests.CompileString(storyStr);

    expect("true\ntrue\ntrue\ntrue\ntrue\ngreat\nright?\n",
        story.ContinueMaximally());
  });

  test("TestConst", () {
    var story = tests.CompileString(r'''
VAR x = c

CONST c = 5

{x}
''');
    expect("5\n", story.Continue());
  });

  test("TestDefaultChoices", () {
    Story story = tests.CompileString(r'''
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

  test("TestDefaultSimpleGather", () {
    var story = tests.CompileString(r'''
* ->
- x
-> DONE''');

    expect("x\n", story.Continue());
  });

  test("TestDivertInConditional", () {
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

    Story story = tests.CompileString(storyStr);
    expect("", story.ContinueMaximally());
  });

  test("TestDivertToWeavePoints", () {
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

    Story story = tests.CompileString(storyStr);

    expect("gather\ntest\nchoice content\ngather\nsecond time round\n",
        story.ContinueMaximally());
  });

  test("TestElseBranches", () {
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

    Story story = tests.CompileString(storyStr);

    expect("other\nother\nother\nother\n", story.ContinueMaximally());
  });

  test("TestEmpty", () {
    Story story = tests.CompileString(r"");

    expect('', story.currentText);
  });
  test("TestEmptyMultilineConditionalBranch", () {
    var story = tests.CompileString(r'''
{ 3:
    - 3:
    - 4:
        txt
}
''');

    expect("", story.Continue());
  });
  test("TestAllSwitchBranchesFailIsClean", () {
    var story = tests.CompileString(r'''
{ 1:
    - 2: x
    - 3: y
}
        ''');

    story.Continue();

    expect(story.state.evaluationStack.length, 0);
  });
  test("TestTrivialCondition", () {
    var story = tests.CompileString(r'''
{
- false:
   beep
}
                ''');

    story.Continue();
  });
  test("TestEmptySequenceContent", () {
    var story = tests.CompileString(r'''
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
  test("TestEnd", () {
    Story story = tests.CompileString(r'''
hello
-> END
world
-> END
''');

    expect("hello\n", story.ContinueMaximally());
  });
  test("TestEnd2", () {
    Story story = tests.CompileString(r'''
-> test

== test ==
hello
-> END
world
-> END
''');

    expect("hello\n", story.ContinueMaximally());
  });

  test("TestEscapeCharacter", () {
    var storyStr = r"{true:this is a '\|' character|this isn't}";

    Story story = tests.CompileString(storyStr);

    expect("this is a '|' character\n", story.ContinueMaximally());
  });

  test("TestObjectMethodCall", () {
    var story = tests.CompileString(r"""
VAR a = 4
{a.add(5)}
{add(3, a.add(8))}
{a.add(1).add(2).add(3)}
== function add(x, y)
~ return x + y
""");
    expect("9", story.Continue().trim());
    expect("15", story.Continue().trim());
    expect("10", story.Continue().trim());
  });

  String generalExternalFunction(List args) {
    return args.join(",");
  }

  test("TestExternalBindingWithVariableArguments", () {
    var story = tests.CompileString(r"""
EXTERNAL array()
{array(1,2,3,4,5,6)}
""");

    story.BindExternalFunctionGeneral("array", generalExternalFunction);

    expect("1,2,3,4,5,6", story.Continue().trim());
  });
  test("TestExternalBinding", () {
    var story = tests.CompileString(r"""
EXTERNAL message(x)
EXTERNAL multiply(x,y)
EXTERNAL times(i,str)
~ message("hello world")
{multiply(5.0, 3)}
{times(3, "knock ")}
""");
    String? message;

    story.BindExternalFunctionGeneral("message", (List arg) {
      message = "MESSAGE: " + arg[0];
    });

    story.BindExternalFunctionGeneral("multiply", (List arg) {
      double arg1 = arg[0];
      int arg2 = arg[1];
      return arg1 * arg2;
    });

    story.BindExternalFunctionGeneral("times", (List arg) {
      int numberOfTimes = arg[0];
      String str = arg[1];
      String result = "";
      for (int i = 0; i < numberOfTimes; i++) {
        result += str;
      }
      return result;
    });

    expect("15\n", story.Continue());

    expect("knock knock knock\n", story.Continue());

    expect("MESSAGE: hello world", message);
  });
  test("TestLookupSafeOrNot", () {
    var story = tests.CompileString(r"""
EXTERNAL myAction()

One
~ myAction()
Two
""");

    // Lookahead SAFE - should get multiple calls to the ext function,
    // one for lookahead on first line, one "for real" on second line.
    int callCount = 0;
    story.BindExternalFunctionGeneral(
        "myAction", (List args) => callCount++, true);

    story.ContinueMaximally();
    expect(2, callCount);

    // Lookahead UNSAFE - when it sees the function, it should break out early
    // and stop lookahead, making sure that the action is only called for the second line.
    callCount = 0;
    story.ResetState();
    story.UnbindExternalFunction("myAction");
    story.BindExternalFunctionGeneral(
        "myAction", (List args) => callCount++, false);

    story.ContinueMaximally();
    expect(1, callCount);

    // Lookahead SAFE but breaks glue intentionally
    var storyWithPostGlue = tests.CompileString(r"""
EXTERNAL myAction()

One 
~ myAction()
<> Two
""");

    storyWithPostGlue.BindExternalFunctionGeneral(
        "myAction", (List args) => null);
    var result = storyWithPostGlue.ContinueMaximally();
    expect("One\nTwo\n", result);
  });
  test("TestFactorialByReference", () {
    var storyStr = r"""
VAR result = 0
~ factorialByRef(result, 5)
{ result }

== function factorialByRef(ref r, n) ==
{ r == 0:
    ~ r = 1
}
{ n > 1:
    ~ r = r * n
    ~ factorialByRef(r, n-1)
}
~ return
""";

    Story story = tests.CompileString(storyStr);

    expect("120\n", story.ContinueMaximally());
  });
  test("TestFactorialRecursive", () {
    var storyStr = r"""
{ factorial(5) }

== function factorial(n) ==
 { n == 1:
    ~ return 1
 - else:
    ~ return (n * factorial(n-1))
 }
""";

    Story story = tests.CompileString(storyStr);

    expect("120\n", story.ContinueMaximally());
  });
  test("TestGatherChoiceSameLine", () {
    var storyStr = "- * hello\n- * world";

    Story story = tests.CompileString(storyStr);
    story.Continue();

    expect("hello", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    story.Continue();

    expect("world", story.currentChoices[0].text);
  });
  test("TestGatherReadCountWithInitialSequence", () {
    var story = tests.CompileString(r"""
- (opts)
{test:seen test}
- (test)
{ -> opts |}
""");

    expect("seen test\n", story.Continue());
  });
  test("TestHasReadOnChoice", () {
    var storyStr = r"""
* { not test } visible choice
* { test } visible choice

== test ==
-> END
                """;

    Story story = tests.CompileString(storyStr);
    story.ContinueMaximally();

    expect(1, story.currentChoices.length);
    expect("visible choice", story.currentChoices[0].text);
  });
  test("TestHelloWorld", () {
    Story story = tests.CompileString("Hello world");
    expect("Hello world\n", story.Continue());
  });
  test("TestIdentifersCanStartWithNumbers", () {
    var story = tests.CompileString(r"""
-> 2tests
== 2tests ==
~ temp 512x2 = 512 * 2
~ temp 512x2p2 = 512x2 + 2
512x2 = {512x2}
512x2p2 = {512x2p2}
-> DONE
""");

    expect("512x2 = 1024\n512x2p2 = 1026\n", story.ContinueMaximally());
  });
  test("TestImplicitInlineGlue", () {
    var story = tests.CompileString(r"""
I have {five()} eggs.

== function five ==
{false:
    Don't print this
}
five
""");

    expect("I have five eggs.\n", story.Continue());
  });
  test("TestImplicitInlineGlueB", () {
    var story = tests.CompileString(r"""
A {f():B} 
X

=== function f() ===
{true: 
    ~ return false
}
""");

    expect("A\nX\n", story.ContinueMaximally());
  });
  test("TestImplicitInlineGlueC", () {
    var story = tests.CompileString(r"""
A
{f():X}
C

=== function f()
{ true: 
    ~ return false
}
""");

    expect("A\nC\n", story.ContinueMaximally());
  });
  test("TestInclude", () {
    var storyStr = r"""
INCLUDE test_included_file.ink
  INCLUDE test_included_file2.ink

This is the main file.
                """;
    Story story = tests.CompileString(storyStr, copyIncludes: true);
    expect("This is include 1.\nThis is include 2.\nThis is the main file.\n",
        story.ContinueMaximally());
  });
  test("TestIncrement", () {
    Story story = tests.CompileString(r"""
VAR x = 5
~ x++
{x}

~ x--
{x}
""");

    expect("6\n5\n", story.ContinueMaximally());
  });

  test("TestKnotDotGather", () {
    var story = tests.CompileString(r"""
-> knot
=== knot
-> knot.gather
- (gather) g
-> DONE""");

    expect("g\n", story.Continue());
  });
  test("TestKnotThreadInteraction", () {
    Story story = tests.CompileString(r"""
-> knot
=== knot
    <- threadB
    -> tunnel ->
    THE END
    -> END

=== tunnel
    - blah blah
    * wigwag
    - ->->

=== threadB
    *   option
    -   something
        -> DONE
""");

    expect("blah blah\n", story.ContinueMaximally());

    expect(2, story.currentChoices.length);
    expect(story.currentChoices[0].text?.contains("option"), true);
    expect(story.currentChoices[1].text?.contains("wigwag"), true);

    story.ChooseChoiceIndex(1);
    expect("wigwag\n", story.Continue());
    expect("THE END\n", story.Continue());
  });
  test("TestKnotThreadInteraction2", () {
    Story story = tests.CompileString(r"""
-> knot
=== knot
    <- threadA
    When should this get printed?
    -> DONE

=== threadA
    -> tunnel ->
    Finishing thread.
    -> DONE

=== tunnel
    -   I’m in a tunnel
    *   I’m an option
    -   ->->

""");

    expect("I’m in a tunnel\nWhen should this get printed?\n",
        story.ContinueMaximally());
    expect(1, story.currentChoices.length);
    expect(story.currentChoices[0].text, "I’m an option");

    story.ChooseChoiceIndex(0);
    expect("I’m an option\nFinishing thread.\n", story.ContinueMaximally());
  });

  test("TestLeadingNewlineMultilineSequence", () {
    var story = tests.CompileString(r"""
{stopping:

- a line after an empty line
- blah
}
""");

    expect("a line after an empty line\n", story.Continue());
  });

  test("TestLiteralUnary", () {
    var story = tests.CompileString(r"""
VAR negativeLiteral = -1
VAR negativeLiteral2 = not not false
VAR negativeLiteral3 = !(0)

{negativeLiteral}
{negativeLiteral2}
{negativeLiteral3}
""");
    expect("-1\nfalse\ntrue\n", story.ContinueMaximally());
  });

  test("TestLogicInChoices", () {
    var story = tests.CompileString(r"""
* 'Hello {name()}[, your name is {name()}.'],' I said, knowing full well that his name was {name()}.
-> DONE

== function name ==
Joe
""");

    story.ContinueMaximally();

    expect("'Hello Joe, your name is Joe.'", story.currentChoices[0].text);
    story.ChooseChoiceIndex(0);

    expect("'Hello Joe,' I said, knowing full well that his name was Joe.\n",
        story.ContinueMaximally());
  });

  test("TestMultipleConstantReferences", () {
    var story = tests.CompileString(r"""
CONST CONST_STR = "ConstantString"
VAR varStr = CONST_STR
{varStr == CONST_STR:success}
""");

    expect("success\n", story.Continue());
  });

  test("TestMultiThread", () {
    Story story = tests.CompileString(r"""
-> start
== start ==
-> tunnel ->
The end
-> END

== tunnel ==
<- place1
<- place2
-> DONE

== place1 ==
This is place 1.
* choice in place 1
- ->->

== place2 ==
This is place 2.
* choice in place 2
- ->->
""");
    expect("This is place 1.\nThis is place 2.\n", story.ContinueMaximally());

    story.ChooseChoiceIndex(0);
    expect("choice in place 1\nThe end\n", story.ContinueMaximally());
  });

  test("TestNestedInclude", () {
    var storyStr = r"""
INCLUDE test_included_file3.ink

This is the main file

-> knot_in_2
                """;

    Story story = tests.CompileString(storyStr, copyIncludes: true);
    expect(
        "The value of a variable in test file 2 is 5.\nThis is the main file\nThe value when accessed from knot_in_2 is 5.\n",
        story.ContinueMaximally());
  });

  test("TestNestedPassByReference", () {
    var storyStr = r"""
VAR globalVal = 5

{globalVal}

~ squaresquare(globalVal)

{globalVal}

== function squaresquare(ref x) ==
 {square(x)} {square(x)}
 ~ return

== function square(ref x) ==
 ~ x = x * x
 ~ return
""";

    Story story = tests.CompileString(storyStr);

    // Bloody whitespace
    expect("5\n625\n", story.ContinueMaximally());
  });

  test("TestNonTextInChoiceInnerContent", () {
    var storyStr = r"""
-> knot
== knot
   *   option text[]. {true: Conditional bit.} -> next
   -> DONE

== next
    Next.
    -> DONE
                """;

    Story story = tests.CompileString(storyStr);
    story.Continue();

    story.ChooseChoiceIndex(0);
    expect("option text. Conditional bit. Next.\n", story.Continue());
  });

  test("TestOnceOnlyChoicesCanLinkBackToSelf", () {
    var story = tests.CompileString(r"""
-> opts
= opts
*   (firstOpt) [First choice]   ->  opts
*   {firstOpt} [Second choice]  ->  opts
* -> end

- (end)
    -> END
""");

    story.ContinueMaximally();

    expect(1, story.currentChoices.length);
    expect("First choice", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    expect(1, story.currentChoices.length);
    expect("Second choice", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    expect([], story.currentErrors);
  });

  test("TestOnceOnlyChoicesWithOwnContent", () {
    Story story = tests.CompileString(r"""
VAR times = 3
-> home

== home ==
~ times = times - 1
{times >= 0:-> eat}
I've finished eating now.
-> END

== eat ==
This is the {first|second|third} time.
 * Eat ice-cream[]
 * Drink coke[]
 * Munch cookies[]
-
-> home
""");

    story.ContinueMaximally();

    expect(3, story.currentChoices.length);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    expect(2, story.currentChoices.length);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    expect(1, story.currentChoices.length);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    expect(0, story.currentChoices.length);
  });

  test("TestPathToSelf", () {
    var story = tests.CompileString(r"""
- (dododo)
-> tunnel ->
-> dododo

== tunnel
+ A
->->
""");
    // We're only checking that the story copes
    // okay without crashing
    // (internally the "-> dododo" ends up generating
    //  a very short path: ".^", and after walking into
    // the parent, it didn't cope with the "." before
    // I fixed it!)
    story.Continue();
    story.ChooseChoiceIndex(0);
    story.Continue();
    story.ChooseChoiceIndex(0);
  });

  test("TestPrintNum", () {
    var story = tests.CompileString(r"""
. {print_num(4)} .
. {print_num(15)} .
. {print_num(37)} .
. {print_num(101)} .
. {print_num(222)} .
. {print_num(1234)} .

=== function print_num(x) ===
{
    - x >= 1000:
        {print_num(x / 1000)} thousand { x mod 1000 > 0:{print_num(x mod 1000)}}
    - x >= 100:
        {print_num(x / 100)} hundred { x mod 100 > 0:and {print_num(x mod 100)}}
    - x == 0:
        zero
    - else:
        { x >= 20:
            { x / 10:
                - 2: twenty
                - 3: thirty
                - 4: forty
                - 5: fifty
                - 6: sixty
                - 7: seventy
                - 8: eighty
                - 9: ninety
            }
            { x mod 10 > 0:<>-<>}
        }
        { x < 10 || x > 20:
            { x mod 10:
                - 1: one
                - 2: two
                - 3: three
                - 4: four
                - 5: five
                - 6: six
                - 7: seven
                - 8: eight
                - 9: nine
            }
        - else:
            { x:
                - 10: ten
                - 11: eleven
                - 12: twelve
                - 13: thirteen
                - 14: fourteen
                - 15: fifteen
                - 16: sixteen
                - 17: seventeen
                - 18: eighteen
                - 19: nineteen
            }
        }
}
""");

    expect(r""". four .
. fifteen .
. thirty-seven .
. one hundred and one .
. two hundred and twenty-two .
. one thousand two hundred and thirty-four .
""", story.ContinueMaximally());
  });

  test("TestQuoteCharacterSignificance", () {
    // Confusing escaping + ink! Actual ink string is:
    // My name is "{"J{"o"}e"}"
    //  - First and last quotes are insignificant - they're part of the content
    //  - Inner quotes are significant - they're part of the syntax for string expressions
    // So output is: My name is "Joe"
    var story = tests.CompileString(r'My name is "{"J{"o"}e"}"');
    expect("My name is \"Joe\"\n", story.ContinueMaximally());
  });

  test("TestReadCountAcrossCallstack", () {
    var story = tests.CompileString(r"""
-> first

== first ==
1) Seen first {first} times.
-> second ->
2) Seen first {first} times.
-> DONE

== second ==
In second.
->->
""");
    expect("1) Seen first 1 times.\nIn second.\n2) Seen first 1 times.\n",
        story.ContinueMaximally());
  });

  test("TestReadCountAcrossThreads", () {
    var story = tests.CompileString(r"""
    -> top

= top
    {top}
    <- aside
    {top}
    -> DONE

= aside
    * {false} DONE
	- -> DONE
""");
    expect("1\n1\n", story.ContinueMaximally());
  });

  test("TestReadCountDotSeparatedPath", () {
    Story story = tests.CompileString(r'''
-> hi ->
-> hi ->
-> hi ->

{ hi.stitch_to_count }

== hi ==
= stitch_to_count
hi
->->
''');

    expect("hi\nhi\nhi\n3\n", story.ContinueMaximally());
  });

  test("TestSameLineDivertIsInline", () {
    var story = tests.CompileString(r"""
-> hurry_home
=== hurry_home ===
We hurried home to Savile Row -> as_fast_as_we_could

=== as_fast_as_we_could ===
as fast as we could.
-> DONE
""");

    expect("We hurried home to Savile Row as fast as we could.\n",
        story.Continue());
  });

  test("TestShouldntGatherDueToChoice", () {
    Story story = tests.CompileString(r"""
* opt
    - - text
    * * {false} impossible
    * * -> END
- gather""");

    story.ContinueMaximally();
    story.ChooseChoiceIndex(0);

    // Shouldn't go to "gather"
    expect("opt\ntext\n", story.ContinueMaximally());
  });

  test("TestShuffleStackMuddying", () {
    var story = tests.CompileString(r"""
* {condFunc()} [choice 1]
* {condFunc()} [choice 2]
* {condFunc()} [choice 3]
* {condFunc()} [choice 4]


=== function condFunc() ===
{shuffle:
    - ~ return false
    - ~ return true
    - ~ return true
    - ~ return false
}
""");

    story.Continue();

    expect(2, story.currentChoices.length);
  });

  test("TestSimpleGlue", () {
    var storyStr = "Some <> \ncontent<> with glue.\n";

    Story story = tests.CompileString(storyStr);

    expect("Some content with glue.\n", story.Continue());
  });

  test("TestStickyChoicesStaySticky", () {
    var story = tests.CompileString(r"""
-> test
== test ==
First line.
Second line.
+ Choice 1
+ Choice 2
- -> test
""");

    story.ContinueMaximally();
    expect(2, story.currentChoices.length);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();
    expect(2, story.currentChoices.length);
  });

  test("TestStringConstants", () {
    var story = tests.CompileString(r'''
{x}
VAR x = kX
CONST kX = "hi"
''');

    expect("hi\n", story.Continue());
  });

  test("TestStringsInChoices", () {
    var story = tests.CompileString(r'''
* \ {"test1"} ["test2 {"test3"}"] {"test4"}
-> DONE
''');
    story.ContinueMaximally();

    expect(1, story.currentChoices.length);
    expect(r'test1 "test2 test3"', story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    expect("test1 test4\n", story.Continue());
  });

  test("TestStringTypeCoersion", () {
    var story = tests.CompileString(r'''
{"5" == 5:same|different}
{"blah" == 5:same|different}
''');

    // Not sure that "5" should be equal to 5, but hmm.
    expect("same\ndifferent\n", story.ContinueMaximally());
  });

  test("TestTemporariesAtGlobalScope", () {
    var story = tests.CompileString(r'''
VAR x = 5
~ temp y = 4
{x}{y}
''');
    expect("54\n", story.Continue());
  });

  test("TestThreadDone", () {
    Story story = tests.CompileString(r'''
This is a thread example
<- example_thread
The example is now complete.

== example_thread ==
Hello.
-> DONE
World.
-> DONE
''');

    expect("This is a thread example\nHello.\nThe example is now complete.\n",
        story.ContinueMaximally());
  });

  test("TestTunnelOnwardsAfterTunnel", () {
    var story = tests.CompileString(r'''
-> tunnel1 ->
The End.
-> END

== tunnel1 ==
Hello...
-> tunnel2 ->->

== tunnel2 ==
...world.
->->
''');

    expect("Hello...\n...world.\nThe End.\n", story.ContinueMaximally());
  });

  test("TestTunnelVsThreadBehaviour", () {
    Story story = tests.CompileString(r'''
-> knot_with_options ->
Finished tunnel.

Starting thread.
<- thread_with_options
* E
-
Done.

== knot_with_options ==
* A
* B
-
->->

== thread_with_options ==
* C
* D
- -> DONE
''');

    expect(false, story.ContinueMaximally().contains("Finished tunnel"));

    // Choices should be A, B
    expect(2, story.currentChoices.length);

    story.ChooseChoiceIndex(0);

    // Choices should be C, D, E
    expect(true, story.ContinueMaximally().contains("Finished tunnel"));
    expect(3, story.currentChoices.length);

    story.ChooseChoiceIndex(2);

    expect(true, story.ContinueMaximally().contains("Done."));
  });

  test("TestTurnsSince", () {
    Story story = tests.CompileString(r'''
{ TURNS_SINCE(-> test) }
~ test()
{ TURNS_SINCE(-> test) }
* [choice 1]
- { TURNS_SINCE(-> test) }
* [choice 2]
- { TURNS_SINCE(-> test) }

== function test ==
~ return
''');
    expect("-1\n0\n", story.ContinueMaximally());

    story.ChooseChoiceIndex(0);
    expect("1\n", story.ContinueMaximally());

    story.ChooseChoiceIndex(0);
    expect("2\n", story.ContinueMaximally());
  });

  test("TestTurnsSinceNested", () {
    var story = tests.CompileString(r'''
-> empty_world
=== empty_world ===
    {TURNS_SINCE(-> then)} = -1
    * (then) stuff
        {TURNS_SINCE(-> then)} = 0
        * * (next) more stuff
            {TURNS_SINCE(-> then)} = 1
        -> DONE
''');
    expect("-1 = -1\n", story.ContinueMaximally());

    expect(1, story.currentChoices.length);
    story.ChooseChoiceIndex(0);

    expect("stuff\n0 = 0\n", story.ContinueMaximally());

    expect(1, story.currentChoices.length);
    story.ChooseChoiceIndex(0);

    expect("more stuff\n1 = 1\n", story.ContinueMaximally());
  });

  test("TestTurnsSinceWithVariableTarget", () {
    // Count all visits must be switched on for variable count targets
    var story = tests.CompileString(r'''
-> start

=== start ===
    {beats(-> start)}
    {beats(-> start)}
    *   [Choice]  -> next
= next
    {beats(-> start)}
    -> END

=== function beats(x) ===
    ~ return TURNS_SINCE(x)
''');

    expect("0\n0\n", story.ContinueMaximally());

    story.ChooseChoiceIndex(0);
    expect("1\n", story.ContinueMaximally());
  });

  test("TestUnbalancedWeaveIndentation", () {
    var story = tests.CompileString(r'''
* * * First
* * * * Very indented
- - End
-> END
''');
    story.ContinueMaximally();

    expect(1, story.currentChoices.length);
    expect("First", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    expect("First\n", story.ContinueMaximally());
    expect(1, story.currentChoices.length);
    expect("Very indented", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    expect("Very indented\nEnd\n", story.ContinueMaximally());
    expect(0, story.currentChoices.length);
  });

  test("TestVariableDeclarationInConditional", () {
    var storyStr = r'''
VAR x = 0
{true:
    - ~ x = 5
}
{x}
                ''';

    Story story = tests.CompileString(storyStr);

    // Extra newline is because there's a choice object sandwiched there,
    // so it can't be absorbed :-/
    expect("5\n", story.Continue());
  });

  test("TestVariableDivertTarget", () {
    var story = tests.CompileString(r'''
VAR x = -> here

-> there

== there ==
-> x

== here ==
Here.
-> DONE
''');
    expect("Here.\n", story.Continue());
  });

  test("TestVariableGetSetAPI", () {
    var story = tests.CompileString(r'''
VAR x = 5

{x}

* [choice]
-
{x}

* [choice]
-

{x}

* [choice]
-

{x}

-> DONE
''');

    // Initial state
    expect("5\n", story.ContinueMaximally());
    expect(5, story.variablesState!["x"]);

    story.variablesState!["x"] = 10;
    story.ChooseChoiceIndex(0);
    expect("10\n", story.ContinueMaximally());
    expect(10, story.variablesState!["x"]);

    story.variablesState?["x"] = 8.5;
    story.ChooseChoiceIndex(0);
    expect("8.5\n", story.ContinueMaximally());
    expect(8.5, story.variablesState!["x"]);

    story.variablesState!["x"] = "a string";
    story.ChooseChoiceIndex(0);
    expect("a string\n", story.ContinueMaximally());
    expect("a string", story.variablesState?["x"]);

    expect(null, story.variablesState!["z"]);

    try {
      story.variablesState!["x"] = StringBuilder();
      throw Exception("Assert failed.");
    } catch (e) {
      if (!e.toString().startsWith("Exception: Invalid value passed")) rethrow;
    }
  });

  test("TestVariablePointerRefFromKnot", () {
    var story = tests.CompileString(r'''
VAR val = 5

-> knot ->

-> END

== knot ==
~ inc(val)
{val}
->->

== function inc(ref x) ==
    ~ x = x + 1
''');

    expect("6\n", story.Continue());
  });

  test("TestVariableSwapRecurse", () {
    var storyStr = r'''
~ f(1, 1)

== function f(x, y) ==
{ x == 1 and y == 1:
  ~ x = 2
  ~ f(y, x)
- else:
  {x} {y}
}
~ return
''';

    Story story = tests.CompileString(storyStr);

    expect("1 2\n", story.ContinueMaximally());
  });

  test("TestVariableTunnel", () {
    var story = tests.CompileString(r'''
-> one_then_tother(-> tunnel)

=== one_then_tother(-> x) ===
    -> x -> end

=== tunnel ===
    STUFF
    ->->

=== end ===
    -> END
''');

    expect("STUFF\n", story.ContinueMaximally());
  });

  test("TestWeaveGathers", () {
    var storyStr = r'''
-
 * one
    * * two
   - - three
 *  four
   - - five
- six
                ''';

    Story story = tests.CompileString(storyStr);

    story.ContinueMaximally();

    expect(2, story.currentChoices.length);
    expect("one", story.currentChoices[0].text);
    expect("four", story.currentChoices[1].text);

    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    expect(1, story.currentChoices.length);
    expect("two", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    expect("two\nthree\nsix\n", story.ContinueMaximally());
  });

  test("TestWeaveOptions", () {
    var storyStr = r'''
                    -> test
                    === test
                        * Hello[.], world.
                        -> END
                ''';

    Story story = tests.CompileString(storyStr);
    story.Continue();

    expect("Hello.", story.currentChoices[0].text);

    story.ChooseChoiceIndex(0);
    expect("Hello, world.\n", story.Continue());
  });

  test("TestWhitespace", () {
    var storyStr = r'''
-> firstKnot
=== firstKnot
    Hello!
    -> anotherKnot

=== anotherKnot
    World.
    -> END
''';

    Story story = tests.CompileString(storyStr);
    expect("Hello!\nWorld.\n", story.ContinueMaximally());
  });

  test("TestVisitCountsWhenChoosing", () {
    var storyStr = r'''
== TestKnot ==
this is a test
+ [Next] -> TestKnot2

== TestKnot2 ==
this is the end
-> END
''';

    Story story = tests.CompileString(storyStr, countAllVisits: true);

    expect(story.state.VisitCountAtPathString("TestKnot"), 0);
    expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

    story.ChoosePathString("TestKnot");

    expect(story.state.VisitCountAtPathString("TestKnot"), 1);
    expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

    story.Continue();

    expect(story.state.VisitCountAtPathString("TestKnot"), 1);
    expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

    story.ChooseChoiceIndex(0);

    expect(story.state.VisitCountAtPathString("TestKnot"), 1);

    // At this point, we have made the choice, but the divert *within* the choice
    // won't yet have been evaluated.
    expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

    story.Continue();

    expect(story.state.VisitCountAtPathString("TestKnot"), 1);
    expect(story.state.VisitCountAtPathString("TestKnot2"), 1);
  });

  test("TestVisitCountBugDueToNestedContainers", () {
    var storyStr = r'''
                - (gather) {gather}
                * choice
                - {gather}
            ''';

    Story story = tests.CompileString(storyStr);

    expect("1\n", story.Continue());

    story.ChooseChoiceIndex(0);
    expect("choice\n1\n", story.ContinueMaximally());
  });

  test("TestTempGlobalConflict", () {
    // Test bug where temp was being treated as a global
    var storyStr = r'''
-> outer
=== outer
~ temp x = 0
~ f(x)
{x}
-> DONE

=== function f(ref x)
~temp local = 0
~x=x
{setTo3(local)}

=== function setTo3(ref x)
~x = 3
''';

    Story story = tests.CompileString(storyStr);

    expect("0\n", story.Continue());
  });

  test("TestThreadInLogic", () {
    var storyStr = r'''
-> once ->
-> once ->

== once ==
{<- content|}
->->

== content ==
Content
-> DONE
''';

    Story story = tests.CompileString(storyStr);

    expect("Content\n", story.Continue());
  });

  test("TestTempUsageInOptions", () {
    var storyStr = r'''
~ temp one = 1
* \ {one}
- End of choice 
    -> another
* (another) this [is] another
 -> DONE
''';

    Story story = tests.CompileString(storyStr);
    story.Continue();

    expect(story.currentChoices.length, 1);
    expect(story.currentChoices[0].text, "1");
    story.ChooseChoiceIndex(0);

    expect(story.ContinueMaximally(), "1\nEnd of choice\nthis another\n");

    expect(story.currentChoices.length, 0);
  });

  test("TestEvaluatingInkFunctionsFromGame", () {
    var storyStr = r'''
Top level content
* choice

== somewhere ==
= here
-> DONE

== function test ==
~ return -> somewhere.here
''';

    Story story = tests.CompileString(storyStr);
    story.Continue();

    var returnedDivertTarget = story.EvaluateFunction("test");

    // Divert target should get returned as a string
    expect("somewhere.here", returnedDivertTarget);
  });

  test("TestEvaluatingInkFunctionsFromGame2", () {
    var storyStr = r'''
One
Two
Three

== function func1 ==
This is a function
~ return 5

== function func2 ==
This is a function without a return value
~ return

== function add(x,y) ==
x = {x}, y = {y}
~ return x + y
''';

    Story story = tests.CompileString(storyStr);
    String? textOutput;

    textOutput = story.EvaluateFunctionWithTextOutput("func1")['text_output'];
    var funcResult = story.EvaluateFunction("func1");

    expect("This is a function\n", textOutput);
    expect(5, funcResult);

    expect("One\n", story.Continue());

    textOutput = story.EvaluateFunctionWithTextOutput("func2")['text_output'];
    funcResult = story.EvaluateFunction("func2");

    expect("This is a function without a return value\n", textOutput);
    expect(null, funcResult);

    expect("Two\n", story.Continue());

    textOutput =
        story.EvaluateFunctionWithTextOutput("add", [1, 2])['text_output'];
    funcResult = story.EvaluateFunction("add", [1, 2]);

    expect("x = 1, y = 2\n", textOutput);
    expect(3, funcResult);

    expect("Three\n", story.Continue());
  });

  test("TestEvaluatingFunctionVariableStateBug", () {
    var storyStr = r'''
Start
-> tunnel ->
End
-> END

== tunnel ==
In tunnel.
->->

=== function function_to_evaluate() ===
    { zero_equals_(1):
        ~ return "WRONG"
    - else:
        ~ return "RIGHT"
    }

=== function zero_equals_(k) ===
    ~ do_nothing(0)
    ~ return  (0 == k)

=== function do_nothing(k)
    ~ return 0
''';

    Story story = tests.CompileString(storyStr);

    expect("Start\n", story.Continue());
    expect("In tunnel.\n", story.Continue());

    var funcResult = story.EvaluateFunction("function_to_evaluate");
    expect("RIGHT", funcResult);

    expect("End\n", story.Continue());
  });

  test("TestDoneStopsThread", () {
    var storyStr = r'''
-> DONE
This content is inaccessible.
''';

    Story story = tests.CompileString(storyStr);

    expect('', story.ContinueMaximally());
  });

  test("TestLeftRightGlueMatching", () {
    var storyStr = r'''
A line.
{ f():
    Another line.
}

== function f ==
{false:nothing}
~ return true

''';
    var story = tests.CompileString(storyStr);

    expect("A line.\nAnother line.\n", story.ContinueMaximally());
  });

  test("TestSetNonExistantVariable", () {
    var storyStr = r'''
VAR x = "world"
Hello {x}.
''';
    var story = tests.CompileString(storyStr);

    expect("Hello world.\n", story.Continue());

    assertError<StoryException>(() {
      story.variablesState?["y"] = "earth";
    });
  });

  test("TestTags", () {
    var storyStr = r'''
VAR x = 2 
# author: Joe
# title: My Great Story
This is the content

== knot ==
# knot tag
Knot content
# end of knot tag
-> END

= stitch
# stitch tag
Stitch content
# this tag is below some content so isn't included in the static tags for the stitch
-> END
''';
    var story = tests.CompileString(storyStr);

    List<String> globalTags = [];
    globalTags.add("author: Joe");
    globalTags.add("title: My Great Story");

    List<String> knotTags = [];
    knotTags.add("knot tag");

    List<String> knotTagWhenContinuedTwice = [];
    knotTagWhenContinuedTwice.add("end of knot tag");

    List<String> stitchTags = [];
    stitchTags.add("stitch tag");

    expect(globalTags, story.globalTags);
    expect("This is the content\n", story.Continue());
    expect(globalTags, story.currentTags);

    expect(knotTags, story.TagsForContentAtPath("knot"));
    expect(stitchTags, story.TagsForContentAtPath("knot.stitch"));

    story.ChoosePathString("knot");
    expect("Knot content\n", story.Continue());
    expect(knotTags, story.currentTags);
    expect("", story.Continue());
    expect(knotTagWhenContinuedTwice, story.currentTags);
  });

  test("TestTunnelOnwardsDivertOverride", () {
    var storyStr = r'''
-> A ->
We will never return to here!

== A ==
This is A
->-> B

== B ==
Now in B.
-> END
''';
    var story = tests.CompileString(storyStr);

    expect("This is A\nNow in B.\n", story.ContinueMaximally());
  });

  test("TestAuthorWarningsInsideContentListBug", () {
    var storyStr = r'''
{ once:
- a
TODO: b
}
''';
    tests.CompileString(storyStr, testingErrors: true);
    expect(tests.HadError(), false);
  });

  test("TestWeaveWithinSequence", () {
    var storyStr = r'''
{ shuffle:
-   * choice
    nextline
    -> END
}
''';
    var story = tests.CompileString(storyStr);

    story.Continue();

    expect(story.currentChoices.length == 1, true);

    story.ChooseChoiceIndex(0);

    expect("choice\nnextline\n", story.ContinueMaximally());
  });

  test("TestNestedChoiceError", () {
    var storyStr = r'''
{ true:
    * choice
}
''';

    assertError(() => tests.CompileString(storyStr, testingErrors: true),
        "need to explicitly divert");
  });

  test("TestStitchNamingCollision", () {
    var storyStr = r'''
VAR stitch = 0

== knot ==
= stitch
->DONE
''';

    assertError(
        () => tests.CompileString(storyStr,
            countAllVisits: false, testingErrors: true),
        "already been used for a var");
  });

  test("TestWeavePointNamingCollision", () {
    var storyStr = r'''
-(opts)
opts1
-(opts)
opts1
-> END
''';

    assertError(
        () => tests.CompileString(storyStr,
            countAllVisits: false, testingErrors: true),
        "with the same label");
  });

  test("TestVariableNamingCollisionWithArg", () {
    var storyStr = r'''=== function knot (a)
                    ~temp a = 1''';

    assertError(
        () => tests.CompileString(storyStr,
            countAllVisits: false, testingErrors: true),
        "has already been used");
  });

  test("TestTunnelOnwardsDivertAfterWithArg", () {
    var storyStr = r'''
-> a ->  

=== a === 
->-> b (5 + 3)

=== b (x) ===
{x} 
-> END
''';

    var story = tests.CompileString(storyStr);

    expect("8\n", story.ContinueMaximally());
  });

  test("TestVariousDefaultChoices", () {
    var storyStr = r'''
* -> hello
Unreachable
- (hello) 1
* ->
   - - 2
- 3
-> END
''';

    var story = tests.CompileString(storyStr);
    expect("1\n2\n3\n", story.ContinueMaximally());
  });

  test("TestVariousBlankChoiceWarning", () {
    var storyStr = r'''
* [] blank
        ''';

    // skip!
    //assertError(() => tests.CompileString(storyStr, testingErrors: true),
    //    "Blank choice");
  });

  test("TestTunnelOnwardsWithParamDefaultChoice", () {
    var storyStr = r'''
-> tunnel ->

== tunnel ==
* ->-> elsewhere (8)

== elsewhere (x) ==
{x}
-> END
''';

    var story = tests.CompileString(storyStr);
    expect("8\n", story.ContinueMaximally());
  });

  test("TestTunnelOnwardsToVariableDivertTarget", () {
    var storyStr = r'''
-> outer ->

== outer
This is outer
-> cut_to(-> the_esc)

=== cut_to(-> escape) 
    ->-> escape
    
== the_esc
This is the_esc
-> END
''';

    var story = tests.CompileString(storyStr);
    expect("This is outer\nThis is the_esc\n", story.ContinueMaximally());
  });

  test("TestReadCountVariableTarget", () {
    var storyStr = r'''
VAR x = ->knot

Count start: {READ_COUNT (x)} {READ_COUNT (-> knot)} {knot}

-> x (1) ->
-> x (2) ->
-> x (3) ->

Count end: {READ_COUNT (x)} {READ_COUNT (-> knot)} {knot}
-> END


== knot (a) ==
{a}
->->
''';

    var story = tests.CompileString(storyStr, countAllVisits: true);
    expect("Count start: 0 0 0\n1\n2\n3\nCount end: 3 3 3\n",
        story.ContinueMaximally());
  });

  test("TestDivertTargetsWithParameters", () {
    var storyStr = r'''
VAR x = ->place

->x (5)

== place (a) ==
{a}
-> DONE
''';

    var story = tests.CompileString(storyStr);

    expect("5\n", story.ContinueMaximally());
  });

  test("TestTagOnChoice", () {
    var storyStr = r'''
* [Hi] Hello -> END #hey
''';

    var story = tests.CompileString(storyStr);

    story.Continue();

    story.ChooseChoiceIndex(0);

    var txt = story.Continue();
    var tags = story.currentTags;

    expect("Hello", txt);
    expect(1, tags.length);
    expect("hey", tags[0]);
  });

  test("TestStringContains", () {
    var storyStr = r'''
{"hello world" ? "o wo"}
{"hello world" ? "something else"}
{"hello" ? ""}
{"" ? ""}
''';

    var story = tests.CompileString(storyStr);

    var result = story.ContinueMaximally();

    expect("true\nfalse\ntrue\ntrue\n", result);
  });

  test("TestEvaluationStackLeaks", () {
    var storyStr = r'''
{false:
    
- else: 
    else
}

{6:
- 5: five
- else: else
}

-> onceTest ->
-> onceTest ->

== onceTest ==
{once:
- hi
}
->->
''';

    var story = tests.CompileString(storyStr);

    var result = story.ContinueMaximally();

    expect("else\nelse\nhi\n", result);
    expect(story.state.evaluationStack.isEmpty, true);
  });

  test("TestGameInkBackAndForth", () {
    var storyStr = r'''
EXTERNAL gameInc(x)

== function topExternal(x)
In top external
~ return gameInc(x)

== function inkInc(x)
~ return x + 1

            ''';

    var story = tests.CompileString(storyStr);

    // Crazy game/ink callstack:
    // - Game calls "topExternal(5)" (Game -> ink)
    // - topExternal calls gameInc(5) (ink -> Game)
    // - gameInk increments to 6
    // - gameInk calls inkInc(6) (Game -> ink)
    // - inkInc just increments to 7 (ink)
    // And the whole thing unwinds again back to game.

    story.BindExternalFunctionGeneral("gameInc", (List args) {
      int x = args[0];
      x++;
      x = story.EvaluateFunction("inkInc", [x]);
      return x;
    });

    String strResult =
        story.EvaluateFunctionWithTextOutput("topExternal", [5])["text_output"];
    var finalResult = story.EvaluateFunction("topExternal", [5]);

    expect(7, finalResult);
    expect("In top external\n", strResult);
  });

  test("TestNewlinesWithStringEval", () {
    var storyStr = r'''
A
~temp someTemp = string()
B

A 
{string()}
B

=== function string()    
    ~ return "{3}"
}
''';

    var story = tests.CompileString(storyStr);

    expect("A\nB\nA\n3\nB\n", story.ContinueMaximally());
  });

  test("TestNewlinesTrimmingWithFuncExternalFallback", () {
    var storyStr = r'''
EXTERNAL TRUE ()

Phrase 1 
{ TRUE ():

	Phrase 2
}
-> END 

=== function TRUE ()
	~ return true
''';

    var story = tests.CompileString(storyStr);
    story.allowExternalFunctionFallbacks = true;

    expect("Phrase 1\nPhrase 2\n", story.ContinueMaximally());
  });

  test("TestMultilineLogicWithGlue", () {
    var storyStr = r'''
{true:
    a 
} <> b


{true:
    a 
} <> { true: 
    b 
}
''';
    var story = tests.CompileString(storyStr);

    expect("a b\na b\n", story.ContinueMaximally());
  });

  test("TestNewlineAtStartOfMultilineConditional", () {
    var storyStr = r'''
{isTrue():
    x
}

=== function isTrue()
    X
	~ return true
        ''';
    var story = tests.CompileString(storyStr);

    expect("X\nx\n", story.ContinueMaximally());
  });

  test("TestTempNotFound", () {
    var storyStr = r'''
{x}
~temp x = 5
hello
                ''';
    var story = tests.CompileString(storyStr, testingErrors: true);

    expect("0\nhello\n", story.ContinueMaximally());

    expect(tests.HadWarning(), true);
  });

  test("TestTopFlowTerminatorShouldntKillThreadChoices", () {
    var storyStr = r'''
<- move
Limes 

=== move
	* boop
        -> END
                    ''';

    var story = tests.CompileString(storyStr);

    expect("Limes\n", story.Continue());
    expect(story.currentChoices.length == 1, true);
  });

  test("TestNewlineConsistency", () {
    var storyStr = r'''
hello -> world
== world
world 
-> END''';

    var story = tests.CompileString(storyStr);
    expect("hello world\n", story.ContinueMaximally());

    storyStr = r'''
* hello -> world
== world
world 
-> END''';
    story = tests.CompileString(storyStr);

    story.Continue();
    story.ChooseChoiceIndex(0);
    expect("hello world\n", story.ContinueMaximally());

    storyStr = r'''
* hello 
	-> world
== world
world 
-> END''';
    story = tests.CompileString(storyStr);

    story.Continue();
    story.ChooseChoiceIndex(0);
    expect("hello\nworld\n", story.ContinueMaximally());
  });

  test("TestTurns", () {
    var storyStr = r'''
-> c
- (top)
+ (c) [choice]
    {TURNS ()}
    -> top
                    ''';

    var story = tests.CompileString(storyStr);

    for (int i = 0; i < 10; i++) {
      expect("$i\n", story.Continue());
      story.ChooseChoiceIndex(0);
    }
  });

  test("TestLogicLinesWithNewlines", () {
    // Both "~" lines should be followed by newlines
    // since func() has a text output side effect.
    var storyStr = r'''
~ func ()
text 2

~temp tempVar = func ()
text 2

== function func ()
	text1
	~ return true
''';

    var story = tests.CompileString(storyStr);

    expect("text1\ntext 2\ntext1\ntext 2\n", story.ContinueMaximally());
  });

  test("TestFloorCeilingAndCasts", () {
    var storyStr = r'''
{FLOOR(1.2)}
{INT(1.2)}
{CEILING(1.2)}
{CEILING(1.2) / 3}
{INT(CEILING(1.2)) / 3}
{FLOOR(1)}
''';

    var story = tests.CompileString(storyStr);

    expect("1\n1\n2\n0.6666667\n0\n1\n", story.ContinueMaximally());
  });

  test("TestKnotStitchGatherCounts", () {
    var storyStr = r'''
VAR knotCount = 0
VAR stitchCount = 0

-> gather_count_test ->

~ knotCount = 0
-> knot_count_test ->

~ knotCount = 0
-> knot_count_test ->

-> stitch_count_test ->

== gather_count_test ==
VAR gatherCount = 0
- (loop)
~ gatherCount++
{gatherCount} {loop}
{gatherCount<3:->loop}
->->

== knot_count_test ==
~ knotCount++
{knotCount} {knot_count_test}
{knotCount<3:->knot_count_test}
->->


== stitch_count_test ==
~ stitchCount = 0
-> stitch ->
~ stitchCount = 0
-> stitch ->
->->

= stitch
~ stitchCount++
{stitchCount} {stitch}
{stitchCount<3:->stitch}
->->
''';

    // Ensure it just compiles
    var story = tests.CompileString(storyStr);

    expect(r'''1 1
2 2
3 3
1 1
2 1
3 1
1 2
2 2
3 2
1 1
2 1
3 1
1 2
2 2
3 2
''', story.ContinueMaximally());
  });

  test("TestChoiceThreadForking", () {
    var storyStr = r'''
-> generate_choice(1) ->

== generate_choice(x) ==
{true:
    + A choice
        Vaue of local var is: {x}
        -> END
}
->->
''';

    // Generate the choice with the forked thread
    var story = tests.CompileString(storyStr);
    story.Continue();

    // Save/reload
    var savedState = story.state.ToJson();
    story = tests.CompileString(storyStr);
    story.state.LoadJson(savedState);

    // Load the choice, it should have its own thread still
    // that still has the captured temp x
    story.ChooseChoiceIndex(0);
    story.ContinueMaximally();

    // Don't want this warning:
    // RUNTIME WARNING: '' line 7: Variable not found: 'x'
    expect(story.hasWarning, false);
  });

  test("TestFallbackChoiceOnThread", () {
    var storyStr = r'''
<- knot

== knot
   ~ temp x = 1
   *   ->
       Should be 1 not 0: {x}.
       -> DONE
''';

    var story = tests.CompileString(storyStr);
    expect("Should be 1 not 0: 1.\n", story.Continue());
  });

  test("TestCleanCallstackResetOnPathChoice", () {
    var storyStr = r'''
{RunAThing()}

== function RunAThing ==
The first line.
The second line.

== SomewhereElse ==
{"somewhere else"}
->END
''';

    var story = tests.CompileString(storyStr);

    expect("The first line.\n", story.Continue());

    story.ChoosePathString("SomewhereElse");

    expect("somewhere else\n", story.ContinueMaximally());
  });

  test("TestStateRollbackOverDefaultChoice", () {
    var storyStr = r'''
<- make_default_choice
Text.

=== make_default_choice
    *   -> 
        {5}
        -> END 
''';

    var story = tests.CompileString(storyStr);

    expect("Text.\n", story.Continue());
    expect("5\n", story.Continue());
  });

  test("TestBools", () {
    expect("true\n", tests.CompileString("{true}").Continue());
    expect("2\n", tests.CompileString("{true + 1}").Continue());
    expect("3\n", tests.CompileString("{2 + true}").Continue());
    expect("0\n", tests.CompileString("{false + false}").Continue());
    expect("2\n", tests.CompileString("{true + true}").Continue());
    expect("true\n", tests.CompileString("{true == 1}").Continue());
    expect("false\n", tests.CompileString("{not 1}").Continue());
    expect("false\n", tests.CompileString("{not true}").Continue());
    expect("true\n", tests.CompileString("{3 > 1}").Continue());
  });

  test("TestMultiFlowBasics", () {
    var storyStr = r'''
=== knot1
knot 1 line 1
knot 1 line 2
-> END 

=== knot2
knot 2 line 1
knot 2 line 2
-> END 
''';

    var story = tests.CompileString(storyStr);

    story.SwitchFlow("First");
    story.ChoosePathString("knot1");
    expect("knot 1 line 1\n", story.Continue());

    story.SwitchFlow("Second");
    story.ChoosePathString("knot2");
    expect("knot 2 line 1\n", story.Continue());

    story.SwitchFlow("First");
    expect("knot 1 line 2\n", story.Continue());

    story.SwitchFlow("Second");
    expect("knot 2 line 2\n", story.Continue());
  });

  test("TestMultiFlowSaveLoadThreads", () {
    var storyStr = r'''
Default line 1
Default line 2

== red ==
Hello I'm red
<- thread1("red")
<- thread2("red")
-> DONE

== blue ==
Hello I'm blue
<- thread1("blue")
<- thread2("blue")
-> DONE

== thread1(name) ==
+ Thread 1 {name} choice
    -> thread1Choice(name)

== thread2(name) ==
+ Thread 2 {name} choice
    -> thread2Choice(name)

== thread1Choice(name) ==
After thread 1 choice ({name})
-> END

== thread2Choice(name) ==
After thread 2 choice ({name})
-> END
''';

    var story = tests.CompileString(storyStr);

    // Default flow
    expect("Default line 1\n", story.Continue());

    story.SwitchFlow("Blue Flow");
    story.ChoosePathString("blue");
    expect("Hello I'm blue\n", story.Continue());

    story.SwitchFlow("Red Flow");
    story.ChoosePathString("red");
    expect("Hello I'm red\n", story.Continue());

    // Test existing state remains after switch (blue)
    story.SwitchFlow("Blue Flow");
    expect("Hello I'm blue\n", story.currentText);
    expect("Thread 1 blue choice", story.currentChoices[0].text);

    // Test existing state remains after switch (red)
    story.SwitchFlow("Red Flow");
    expect("Hello I'm red\n", story.currentText);
    expect("Thread 1 red choice", story.currentChoices[0].text);

    // Save/load test
    var saved = story.state.ToJson();

    // Test choice before reloading state before resetting
    story.ChooseChoiceIndex(0);
    expect("Thread 1 red choice\nAfter thread 1 choice (red)\n",
        story.ContinueMaximally());
    story.ResetState();

    // Load to pre-choice: still red, choose second choice
    story.state.LoadJson(saved);

    story.ChooseChoiceIndex(1);
    expect("Thread 2 red choice\nAfter thread 2 choice (red)\n",
        story.ContinueMaximally());

    // Load: switch to blue, choose 1
    story.state.LoadJson(saved);
    story.SwitchFlow("Blue Flow");
    story.ChooseChoiceIndex(0);
    expect("Thread 1 blue choice\nAfter thread 1 choice (blue)\n",
        story.ContinueMaximally());

    // Load: switch to blue, choose 2
    story.state.LoadJson(saved);
    story.SwitchFlow("Blue Flow");
    story.ChooseChoiceIndex(1);
    expect("Thread 2 blue choice\nAfter thread 2 choice (blue)\n",
        story.ContinueMaximally());

    // Remove active blue flow, should revert back to global flow
    story.RemoveFlow("Blue Flow");
    expect("Default line 2\n", story.Continue());
  });
}
