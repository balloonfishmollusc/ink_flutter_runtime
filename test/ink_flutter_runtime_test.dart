import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_flutter_runtime/addons/extra.dart';
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

  Story CompileString(String str,
      {bool testingErrors = false, bool copyIncludes = false}) {
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

    var processResult = Process.runSync(Platform.isWindows ? 'dotnet' : 'mono',
        ["./inklecate.dll", "-j", "cache/main.ink"],
        workingDirectory: 'test');

    String shellOutput = processResult.stdout;
    if (!shellOutput.contains('{"compile-success": true}')) {
      throw Exception("编译失败！\n" + shellOutput);
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

  bool HadError([String? matchStr]) {
    return HadErrorOrWarning(matchStr, _errorMessages);
  }

  bool HadErrorOrWarning(String? matchStr, List list) {
    if (matchStr == null) return list.length > 0;

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

  test("TestNonTextInChoiceInnerConten", () {
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
* \ {"test1"} ["test2 {"test3"}""] {"test4"}
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
//     var storyStr = r'''
// == TestKnot ==
// this is a test
// + [Next] -> TestKnot2

// == TestKnot2 ==
// this is the end
// -> END
// ''';

//     Story story = tests.CompileString(storyStr);

//     expect(story.state.VisitCountAtPathString("TestKnot"), 0);
//     expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

//     story.ChoosePathString("TestKnot");

//     expect(story.state.VisitCountAtPathString("TestKnot"), 1);
//     expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

//     story.Continue();

//     expect(story.state.VisitCountAtPathString("TestKnot"), 1);
//     expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

//     story.ChooseChoiceIndex(0);

//     expect(story.state.VisitCountAtPathString("TestKnot"), 1);

//     // At this point, we have made the choice, but the divert *within* the choice
//     // won't yet have been evaluated.
//     expect(story.state.VisitCountAtPathString("TestKnot2"), 0);

//     story.Continue();

//     expect(story.state.VisitCountAtPathString("TestKnot"), 1);
//     expect(story.state.VisitCountAtPathString("TestKnot2"), 1);
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

  test("test1", () {
    expect(1,0)
  });

  test("test2", () {
    print(123);
  });

  test("", () {});
}
