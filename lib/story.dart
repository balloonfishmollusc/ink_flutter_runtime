// reviewed

import 'dart:convert';
import 'dart:math';
import 'choice_point.dart';
import 'control_command.dart';
import 'addons/stack.dart';
import 'choice.dart';
import 'container.dart';
import 'debug_metadata.dart';
import 'divert.dart';
import 'error.dart';
import 'addons/extra.dart';
import 'i_named_content.dart';
import 'json_serialisation.dart';
import 'native_function_call.dart';
import 'pointer.dart';
import 'push_pop.dart';
import 'runtime_object.dart';
import 'search_result.dart';
import 'story_exception.dart';
import 'story_state.dart';
import 'tag.dart';
import 'value.dart';
import 'variable_assignment.dart';
import 'variable_reference.dart';
import 'variables_state.dart';
import 'path.dart';
import 'void.dart';

class Story extends RuntimeObject {
  static const int inkVersionCurrent = 20;
  static const int inkVersionMinimumCompatible = 18;

  List<Choice> get currentChoices {
    var choices = <Choice>[];
    for (var c in state.currentChoices) {
      if (!c.isInvisibleDefault) {
        c.index = choices.length;
        choices.add(c);
      }
    }
    return choices;
  }

  String get currentText => state.currentText!;
  List<String> get currentTags => state.currentTags;
  List<String> get currentErrors => state.currentErrors;
  List<String> get currentWarnings => state.currentWarnings;
  String get currentFlowName => state.currentFlowName;
  bool get currentFlowIsDefaultFlow => state.currentFlowIsDefaultFlow;
  List<String> get aliveFlowNames => state.aliveFlowNames;
  bool get hasError => state.hasError;
  bool get hasWarning => state.hasWarning;
  VariablesState? get variablesState => state.variablesState;
  StoryState get state => _state!;

  Event onError = Event(2);
  Event onDidContinue = Event(0);

  //event Action<Choice> onMakeChoice;
  Event onMakeChoice = Event(1);

  //event Action<String, dynamic[]> onEvaluateFunction;
  Event onEvaluateFunction = Event(2);

  //event Action<String, dynamic[], String, dynamic> onCompleteEvaluateFunction;
  Event onCompleteEvaluateFunction = Event(4);

  //event Action<String, dynamic[]> onChoosePathString;
  Event onChoosePathString = Event(2);

  Story.new1(this._mainContentContainer);

  Story(String jsonString) {
    Map<String, dynamic> rootObject = jsonDecode(jsonString);

    dynamic versionObj = rootObject["inkVersion"];
    if (versionObj == null) {
      throw Exception(
          "ink version number not found. Are you sure it's a valid .ink.json file?");
    }

    int formatFromFile = versionObj as int;
    if (formatFromFile > inkVersionCurrent) {
      throw Exception(
          "Version of ink used to build story was newer than the current version of the engine");
    } else if (formatFromFile < inkVersionMinimumCompatible) {
      throw Exception(
          "Version of ink used to build story is too old to be loaded by this version of the engine");
    } else if (formatFromFile != inkVersionCurrent) {
      print(
          "WARNING: Version of ink used to build story doesn't match current version of engine. Non-critical, but recommend synchronising.");
    }

    var rootToken = rootObject["root"];
    if (rootToken == null) {
      throw Exception(
          "Root node for ink not found. Are you sure it's a valid .ink.json file?");
    }

    _mainContentContainer = Json.JTokenToRuntimeObject(rootToken) as Container;

    ResetState();
  }

  String ToJson() {
    var dict = <String, dynamic>{};
    dict["cInkVersion"] = "1.0.0";
    dict["inkVersion"] = inkVersionCurrent;
    dict["root"] = Json.WriteRuntimeContainer(_mainContentContainer);
    dict["listDefs"] = {};
    return jsonEncode(dict);
  }

  void ResetState() {
    _state = StoryState(this);
    ResetGlobals();
  }

  void ResetErrors() {
    state.ResetErrors();
  }

  void ResetCallstack() {
    state.ForceEnd();
  }

  void ResetGlobals() {
    if (_mainContentContainer.namedContent.containsKey("global decl")) {
      var originalPointer = state.currentPointer;

      ChoosePath(Path.new3("global decl"), false);

      ContinueInternal();

      state.currentPointer = originalPointer;
    }

    state.variablesState!.SnapshotDefaultGlobals();
  }

  void SwitchFlow(String flowName) {
    if (_asyncSaving) {
      throw Exception(
          "Story is already in background saving mode, can't switch flow to " +
              flowName);
    }

    state.SwitchFlow_Internal(flowName);
  }

  void RemoveFlow(String flowName) {
    state.RemoveFlow_Internal(flowName);
  }

  void SwitchToDefaultFlow() {
    state.SwitchToDefaultFlow_Internal();
  }

  String Continue() {
    ContinueInternal();
    return currentText;
  }

  bool get canContinue {
    return state.canContinue;
  }

  void ContinueInternal() {
    //if( _profiler != null )
    //    _profiler.PreContinue();

    _recursiveContinueCount++;

    if (!canContinue) {
      throw Exception(
          "Can't continue - should check canContinue before calling Continue");
    }

    state.didSafeExit = false;
    state.ResetOutput();

    if (_recursiveContinueCount == 1) {
      state.variablesState!.batchObservingVariableChanges = true;
    }

    bool outputStreamEndsInNewline = false;
    _sawLookaheadUnsafeFunctionAfterNewline = false;

    do {
      try {
        outputStreamEndsInNewline = ContinueSingleStep();
      } on StoryException catch (e) {
        AddError(e.message, useEndLineNumber: e.useEndLineNumber);
        break;
      }

      if (outputStreamEndsInNewline) {
        break;
      }
    } while (canContinue);

    // 4 outcomes:
    //  - got newline (so finished this line of text)
    //  - can't continue (e.g. choices or ending)
    //  - ran out of time during evaluation
    //  - error
    if (outputStreamEndsInNewline || !canContinue) {
      if (_stateSnapshotAtLastNewline != null) {
        RestoreStateSnapshot();
      }

      if (!canContinue) {
        if (state.callStack.canPopThread) {
          AddError(
              "Thread available to pop, threads should always be flat by the end of evaluation?");
        }

        if (state.generatedChoices.isEmpty &&
            !state.didSafeExit &&
            _temporaryEvaluationContainer == null) {
          if (state.callStack.CanPop(PushPopType.Tunnel)) {
            AddError(
                "unexpectedly reached end of content. Do you need a '->->' to return from a tunnel?");
          } else if (state.callStack.CanPop(PushPopType.Function)) {
            AddError(
                "unexpectedly reached end of content. Do you need a '~ return'?");
          } else if (!state.callStack.canPop) {
            AddError(
                "ran out of content. Do you need a '-> DONE' or '-> END'?");
          } else {
            AddError(
                "unexpectedly reached end of content for unknown reason. Please debug compiler!");
          }
        }
      }

      state.didSafeExit = false;
      _sawLookaheadUnsafeFunctionAfterNewline = false;

      if (_recursiveContinueCount == 1) {
        _state!.variablesState!.batchObservingVariableChanges = false;
      }

      onDidContinue.fire();
    }

    _recursiveContinueCount--;

    //if( _profiler != null )
    //    _profiler.PostContinue();

    if (state.hasError || state.hasWarning) {
      if (onError.isNotEmpty) {
        if (state.hasError) {
          for (var err in state.currentErrors) {
            onError.fire([err, ErrorType.Error]);
          }
        }
        if (state.hasWarning) {
          for (var err in state.currentWarnings) {
            onError.fire([err, ErrorType.Warning]);
          }
        }
        ResetErrors();
      } else {
        var sb = StringBuilder();
        sb.add("Ink had ");
        if (state.hasError) {
          sb.add(state.currentErrors.length.toString());
          sb.add(state.currentErrors.length == 1 ? " error" : " errors");
          if (state.hasWarning) sb.add(" and ");
        }
        if (state.hasWarning) {
          sb.add(state.currentWarnings.length.toString());
          sb.add(state.currentWarnings.length == 1 ? " warning" : " warnings");
        }
        sb.add(
            ". It is strongly suggested that you assign an error handler to story.onError. The first issue was: ");
        sb.add(
            state.hasError ? state.currentErrors[0] : state.currentWarnings[0]);
        throw StoryException(sb.toString());
      }
    }
  }

  bool ContinueSingleStep() {
    //if (_profiler != null)
    //    _profiler.PreStep ();

    Step();

    //if (_profiler != null)
    //    _profiler.PostStep ();

    if (!canContinue && !state.callStack.elementIsEvaluateFromGame) {
      TryFollowDefaultInvisibleChoice();
    }

    //if (_profiler != null)
    //    _profiler.PreSnapshot ();

    if (!state.inStringEvaluation) {
      if (_stateSnapshotAtLastNewline != null) {
        var change = CalculateNewlineOutputStateChange(
            _stateSnapshotAtLastNewline!.currentText!,
            state.currentText!,
            _stateSnapshotAtLastNewline!.currentTags.length,
            state.currentTags.length);

        //print("change: $change");

        if (change == OutputStateChange.ExtendedBeyondNewline ||
            _sawLookaheadUnsafeFunctionAfterNewline) {
          RestoreStateSnapshot();
          return true;
        } else if (change == OutputStateChange.NewlineRemoved) {
          DiscardSnapshot();
        }
      }

      if (state.outputStreamEndsInNewline) {
        if (canContinue) {
          if (_stateSnapshotAtLastNewline == null) {
            StateSnapshot();
          }
        } else {
          DiscardSnapshot();
        }
      }
    }

    //if (_profiler != null)
    //    _profiler.PostSnapshot ();
    return false;
  }

  OutputStateChange CalculateNewlineOutputStateChange(
      String prevText, String currText, int prevTagCount, int currTagCount) {
    //print("prev: $prevText");
    // print("curr: $currText");
    //print("=========");

    var newlineStillExists = currText.length >= prevText.length &&
        currText[prevText.length - 1] == '\n';
    if (prevTagCount == currTagCount &&
        prevText.length == currText.length &&
        newlineStillExists) return OutputStateChange.NoChange;

    if (!newlineStillExists) {
      return OutputStateChange.NewlineRemoved;
    }

    if (currTagCount > prevTagCount) {
      return OutputStateChange.ExtendedBeyondNewline;
    }

    for (int i = prevText.length; i < currText.length; i++) {
      var c = currText[i];
      if (c != ' ' && c != '\t') {
        return OutputStateChange.ExtendedBeyondNewline;
      }
    }

    return OutputStateChange.NoChange;
  }

  String ContinueMaximally() {
    var sb = StringBuilder();

    while (canContinue) {
      sb.add(Continue());
    }

    return sb.toString();
  }

  SearchResult ContentAtPath(Path path) {
    return mainContentContainer.ContentAtPath(path);
  }

  Container? KnotContainerWithName(String name) {
    INamedContent? namedContainer = mainContentContainer.namedContent[name];
    if (namedContainer != null) {
      return namedContainer as Container;
    } else {
      return null;
    }
  }

  Pointer PointerAtPath(Path path) {
    if (path.length == 0) {
      return Pointer.Null;
    }

    Pointer? p;

    int pathLengthToUse = path.length;

    SearchResult result;
    if (path.lastComponent!.isIndex) {
      pathLengthToUse = path.length - 1;
      result = mainContentContainer.ContentAtPath(path,
          partialPathLength: pathLengthToUse);
      p = Pointer(
          container: result.container, index: path.lastComponent!.index);
    } else {
      result = mainContentContainer.ContentAtPath(path);
      p = Pointer(container: result.container, index: -1);
    }

    if (result.obj == null ||
        result.obj == mainContentContainer && pathLengthToUse > 0) {
      Error(
          "Failed to find content at path '$path', and no approximation of it was possible.");
    } else if (result.approximate) {
      Warning(
          "Failed to find content at path '$path', so it was approximated to: '${result.obj!.path}'.");
    }

    return p;
  }

  void StateSnapshot() {
    _stateSnapshotAtLastNewline = _state;
    _state = state.CopyAndStartPatching();
  }

  void RestoreStateSnapshot() {
    _stateSnapshotAtLastNewline!.RestoreAfterPatch();

    _state = _stateSnapshotAtLastNewline;
    _stateSnapshotAtLastNewline = null;

    if (!_asyncSaving) {
      state.ApplyAnyPatch();
    }
  }

  void DiscardSnapshot() {
    if (!_asyncSaving) {
      state.ApplyAnyPatch();
    }

    _stateSnapshotAtLastNewline = null;
  }

  StoryState CopyStateForBackgroundThreadSave() {
    if (_asyncSaving) {
      throw Exception(
          "Story is already in background saving mode, can't call CopyStateForBackgroundThreadSave again!");
    }
    var stateToSave = state;
    _state = state.CopyAndStartPatching();
    _asyncSaving = true;
    return stateToSave;
  }

  void BackgroundSaveComplete() {
    if (_stateSnapshotAtLastNewline == null) {
      state.ApplyAnyPatch();
    }

    _asyncSaving = false;
  }

  void Step() {
    //print(state.currentPointer.toString());

    bool shouldAddToStream = true;

    var pointer = state.currentPointer;
    if (pointer.isNull) return;

    Container? containerToEnter = pointer.Resolve()?.csAs<Container>();
    while (containerToEnter != null) {
      VisitContainer(containerToEnter, true);

      if (containerToEnter.content.isEmpty) break;

      pointer = Pointer.StartOf(containerToEnter);
      containerToEnter = pointer.Resolve()?.csAs<Container>();
    }
    state.currentPointer = pointer;

    //if( _profiler != null ) {
    //	_profiler.Step(state.callStack);
    //}

    var currentContentObj = pointer.Resolve();
    bool isLogicOrFlowControl = PerformLogicAndFlowControl(currentContentObj);

    if (state.currentPointer.isNull) return;

    if (isLogicOrFlowControl) shouldAddToStream = false;

    var choicePoint = currentContentObj?.csAs<ChoicePoint>();
    if (choicePoint != null) {
      var choice = ProcessChoice(choicePoint);
      if (choice != null) {
        state.generatedChoices.add(choice);
      }

      currentContentObj = null;
      shouldAddToStream = false;
    }

    if (currentContentObj is Container) {
      shouldAddToStream = false;
    }

    if (shouldAddToStream) {
      var varPointer = currentContentObj?.csAs<VariablePointerValue>();
      if (varPointer != null && varPointer.contextIndex == -1) {
        var contextIdx =
            state.callStack.ContextForVariableNamed(varPointer.variableName);
        currentContentObj =
            VariablePointerValue(varPointer.variableName, contextIdx);
      }

      if (state.inExpressionEvaluation) {
        state.PushEvaluationStack(currentContentObj!);
      } else {
        state.PushToOutputStream(currentContentObj!);
      }
    }

    NextContent();

    var controlCmd = currentContentObj?.csAs<ControlCommand>();
    if (controlCmd != null &&
        controlCmd.commandType == CommandType.StartThread) {
      state.callStack.PushThread();
    }
  }

  void VisitContainer(Container container, bool atStart) {
    if (!container.countingAtStartOnly || atStart) {
      if (container.visitsShouldBeCounted) {
        state.IncrementVisitCountForContainer(container);
      }

      if (container.turnIndexShouldBeCounted) {
        state.RecordTurnIndexVisitToContainer(container);
      }
    }
  }

  final List<Container> _prevContainers = [];
  void VisitChangedContainersDueToDivert() {
    var previousPointer = state.previousPointer;
    var pointer = state.currentPointer;

    if (pointer.isNull || pointer.index == -1) {
      return;
    }

    _prevContainers.clear();
    if (!previousPointer.isNull) {
      Container? prevAncestor = previousPointer.Resolve()?.csAs<Container>() ??
          previousPointer.container?.csAs<Container>();
      while (prevAncestor != null) {
        _prevContainers.add(prevAncestor);
        prevAncestor = prevAncestor.parent?.csAs<Container>();
      }
    }

    RuntimeObject? currentChildOfContainer = pointer.Resolve();

    if (currentChildOfContainer == null) return;

    Container? currentContainerAncestor =
        currentChildOfContainer.parent?.csAs<Container>();

    bool allChildrenEnteredAtStart = true;
    while (currentContainerAncestor != null &&
        (!_prevContainers.contains(currentContainerAncestor) ||
            currentContainerAncestor.countingAtStartOnly)) {
      bool enteringAtStart = currentContainerAncestor.content.isNotEmpty &&
          currentChildOfContainer == currentContainerAncestor.content[0] &&
          allChildrenEnteredAtStart;

      if (!enteringAtStart) {
        allChildrenEnteredAtStart = false;
      }

      VisitContainer(currentContainerAncestor, enteringAtStart);

      currentChildOfContainer = currentContainerAncestor;
      currentContainerAncestor =
          currentContainerAncestor.parent?.csAs<Container>();
    }
  }

  Choice? ProcessChoice(ChoicePoint choicePoint) {
    bool showChoice = true;

    if (choicePoint.hasCondition) {
      var conditionValue = state.PopEvaluationStack();
      if (!IsTruthy(conditionValue)) {
        showChoice = false;
      }
    }

    String startText = "";
    String choiceOnlyText = "";

    if (choicePoint.hasChoiceOnlyContent) {
      var choiceOnlyStrVal = state.PopEvaluationStack() as StringValue;
      choiceOnlyText = choiceOnlyStrVal.value;
    }

    if (choicePoint.hasStartContent) {
      var startStrVal = state.PopEvaluationStack() as StringValue;
      startText = startStrVal.value;
    }

    if (choicePoint.onceOnly) {
      var visitCount = state.VisitCountForContainer(choicePoint.choiceTarget!);
      if (visitCount > 0) {
        showChoice = false;
      }
    }

    if (!showChoice) {
      return null;
    }

    var choice = Choice();
    choice.targetPath = choicePoint.pathOnChoice;
    choice.sourcePath = choicePoint.path.toString();
    choice.isInvisibleDefault = choicePoint.isInvisibleDefault;

    choice.threadAtGeneration = state.callStack.ForkThread();

    choice.text = (startText + choiceOnlyText).trimWhitespaces();

    return choice;
  }

  bool IsTruthy(RuntimeObject obj) {
    bool truthy = false;
    if (obj is Value) {
      var val = obj;

      if (val is DivertTargetValue) {
        var divTarget = val;
        Error(
            "Shouldn't use a divert target (to ${divTarget.targetPath}) as a conditional value. Did you intend a function call 'likeThis()' or a read count check 'likeThis'? (no arrows)");
        return false;
      }

      return val.isTruthy;
    }
    return truthy;
  }

  bool PerformLogicAndFlowControl(RuntimeObject? contentObj) {
    if (contentObj == null) {
      return false;
    }

    if (contentObj is Divert) {
      Divert currentDivert = contentObj;

      if (currentDivert.isConditional) {
        var conditionValue = state.PopEvaluationStack();

        if (!IsTruthy(conditionValue)) {
          return true;
        }
      }

      if (currentDivert.hasVariableTarget) {
        var varName = currentDivert.variableDivertName;

        var varContents = state.variablesState!.GetVariableWithName(varName!);

        if (varContents == null) {
          Error(
              "Tried to divert using a target from a variable that could not be found (" +
                  varName +
                  ")");
        } else if (varContents is! DivertTargetValue) {
          var intContent = varContents.csAs<IntValue>();

          String errorMessage =
              "Tried to divert to a target from a variable, but the variable ($varName) didn't contain a divert target, it ";
          if (intContent != null && intContent.value == 0) {
            errorMessage += "was empty/null (the value 0).";
          } else {
            errorMessage += "contained '$varContents'.";
          }

          Error(errorMessage);
        }

        var target = varContents as DivertTargetValue;
        state.divertedPointer = PointerAtPath(target.targetPath!);
      } else if (currentDivert.isExternal) {
        CallExternalFunction(
            currentDivert.targetPathString!, currentDivert.externalArgs);
        return true;
      } else {
        state.divertedPointer = currentDivert.targetPointer;
      }

      if (currentDivert.pushesToStack) {
        state.callStack.Push(currentDivert.stackPushType,
            outputStreamLengthWithPushed: state.outputStream.length);
      }

      if (state.divertedPointer.isNull && !currentDivert.isExternal) {
        if (currentDivert.debugMetadata?.sourceName != null) {
          Error("Divert target doesn't exist: " +
              currentDivert.debugMetadata!.sourceName!);
        } else {
          Error("Divert resolution failed: " + currentDivert.toString());
        }
      }

      return true;
    } else if (contentObj is ControlCommand) {
      var evalCommand = contentObj;

      switch (evalCommand.commandType) {
        case CommandType.EvalStart:
          Assert(state.inExpressionEvaluation == false,
              "Already in expression evaluation?");
          state.inExpressionEvaluation = true;
          break;

        case CommandType.EvalEnd:
          Assert(state.inExpressionEvaluation == true,
              "Not in expression evaluation mode");
          state.inExpressionEvaluation = false;
          break;

        case CommandType.EvalOutput:
          if (state.evaluationStack.isNotEmpty) {
            var output = state.PopEvaluationStack();

            if (output is! Void) {
              var text = StringValue(output.toString());

              state.PushToOutputStream(text);
            }
          }
          break;

        case CommandType.NoOp:
          break;

        case CommandType.Duplicate:
          state.PushEvaluationStack(state.PeekEvaluationStack());
          break;

        case CommandType.PopEvaluatedValue:
          state.PopEvaluationStack();
          break;

        case CommandType.PopFunction:
        case CommandType.PopTunnel:
          var popType = evalCommand.commandType == CommandType.PopFunction
              ? PushPopType.Function
              : PushPopType.Tunnel;

          DivertTargetValue? overrideTunnelReturnTarget;
          if (popType == PushPopType.Tunnel) {
            var popped = state.PopEvaluationStack();
            overrideTunnelReturnTarget = popped.csAs<DivertTargetValue>();
            if (overrideTunnelReturnTarget == null) {
              Assert(popped is Void,
                  "Expected void if ->-> doesn't override target");
            }
          }

          if (state.TryExitFunctionEvaluationFromGame()) {
            break;
          } else if (state.callStack.currentElement.type != popType ||
              !state.callStack.canPop) {
            var names = <PushPopType, String>{};
            names[PushPopType.Function] =
                "function return statement (~ return)";
            names[PushPopType.Tunnel] = "tunnel onwards statement (->->)";

            String? expected = names[state.callStack.currentElement.type];
            if (!state.callStack.canPop) {
              expected = "end of flow (-> END or choice)";
            }

            var errorMsg = "Found ${names[popType]}, when expected $expected";

            Error(errorMsg);
          } else {
            state.PopCallstack();

            if (overrideTunnelReturnTarget != null) {
              state.divertedPointer =
                  PointerAtPath(overrideTunnelReturnTarget.targetPath!);
            }
          }

          break;

        case CommandType.BeginString:
          state.PushToOutputStream(evalCommand);

          Assert(state.inExpressionEvaluation == true,
              "Expected to be in an expression when evaluating a String");
          state.inExpressionEvaluation = false;
          break;

        case CommandType.EndString:
          var contentStackForString = Stack<RuntimeObject>();

          int outputCountConsumed = 0;
          for (int i = state.outputStream.length - 1; i >= 0; --i) {
            var obj = state.outputStream[i];

            outputCountConsumed++;

            var command = obj.csAs<ControlCommand>();
            if (command != null &&
                command.commandType == CommandType.BeginString) {
              break;
            }

            if (obj is StringValue) {
              contentStackForString.push(obj);
            }
          }

          state.PopFromOutputStream(outputCountConsumed);

          var sb = StringBuilder();

          for (var c in contentStackForString) {
            sb.add(c.toString());
          }

          state.inExpressionEvaluation = true;
          state.PushEvaluationStack(StringValue(sb.toString()));
          break;

        case CommandType.ChoiceCount:
          var choiceCount = state.generatedChoices.length;
          state.PushEvaluationStack(IntValue(choiceCount));
          break;

        case CommandType.Turns:
          state.PushEvaluationStack(IntValue(state.currentTurnIndex + 1));
          break;

        case CommandType.TurnsSince:
        case CommandType.ReadCount:
          var target = state.PopEvaluationStack();
          if (target is! DivertTargetValue) {
            String extraNote = "";
            if (target is IntValue) {
              extraNote =
                  ". Did you accidentally pass a read count ('knot_name') instead of a target ('-> knot_name')?";
            }
            Error(
                "TURNS_SINCE expected a divert target (knot, stitch, label name), but saw " +
                    target.toString() +
                    extraNote);
            break;
          }

          var divertTarget = target.csAs<DivertTargetValue>();
          var container = ContentAtPath(divertTarget!.targetPath!)
              .correctObj
              ?.csAs<Container>();

          int eitherCount;
          if (container != null) {
            if (evalCommand.commandType == CommandType.TurnsSince) {
              eitherCount = state.TurnsSinceForContainer(container);
            } else {
              eitherCount = state.VisitCountForContainer(container);
            }
          } else {
            if (evalCommand.commandType == CommandType.TurnsSince) {
              eitherCount = -1;
            } else {
              eitherCount = 0;
            }

            Warning("Failed to find container for $evalCommand lookup at " +
                divertTarget.targetPath.toString());
          }

          state.PushEvaluationStack(IntValue(eitherCount));
          break;

        case CommandType.Random:
          {
            var maxInt = state.PopEvaluationStack().csAs<IntValue>();
            var minInt = state.PopEvaluationStack().csAs<IntValue>();

            if (minInt == null) {
              Error("Invalid value for minimum parameter of RANDOM(min, max)");
            }

            if (maxInt == null) {
              Error("Invalid value for maximum parameter of RANDOM(min, max)");
            }

            int randomRange = maxInt!.value - minInt!.value + 1;

            if (randomRange <= 0) {
              Error(
                  "RANDOM was called with minimum as ${minInt.value} and maximum as ${maxInt.value}. The maximum must be larger");
            }

            var resultSeed = state.storySeed + state.previousRandom;
            var random = Random(resultSeed);

            var nextRandom = random.nextInt(1 << 32);
            var chosenValue = (nextRandom % randomRange) + minInt.value;
            state.PushEvaluationStack(IntValue(chosenValue));

            state.previousRandom = nextRandom;
            break;
          }

        case CommandType.SeedRandom:
          var seed = state.PopEvaluationStack().csAs<IntValue>();
          if (seed == null) {
            Error("Invalid value passed to SEED_RANDOM");
          }

          state.storySeed = seed!.value;
          state.previousRandom = 0;

          state.PushEvaluationStack(Void());
          break;

        case CommandType.VisitIndex:
          var count =
              state.VisitCountForContainer(state.currentPointer.container!) - 1;
          state.PushEvaluationStack(IntValue(count));
          break;

        case CommandType.SequenceShuffleIndex:
          var shuffleIndex = NextSequenceShuffleIndex();
          state.PushEvaluationStack(IntValue(shuffleIndex));
          break;

        case CommandType.StartThread:
          break;

        case CommandType.Done:
          if (state.callStack.canPopThread) {
            state.callStack.PopThread();
          } else {
            state.didSafeExit = true;

            state.currentPointer = Pointer.Null;
          }

          break;

        case CommandType.End:
          state.ForceEnd();
          break;
        default:
          Error("unhandled ControlCommand: $evalCommand");
          break;
      }

      return true;
    } else if (contentObj is VariableAssignment) {
      var varAss = contentObj;
      var assignedVal = state.PopEvaluationStack();

      state.variablesState!.Assign(varAss, assignedVal);

      return true;
    } else if (contentObj is VariableReference) {
      var varRef = contentObj;
      RuntimeObject? foundValue;

      if (varRef.pathForCount != null) {
        var container = varRef.containerForCount;
        int count = state.VisitCountForContainer(container!);
        foundValue = IntValue(count);
      } else {
        foundValue = state.variablesState!.GetVariableWithName(varRef.name!);

        if (foundValue == null) {
          Warning(
              "Variable not found: '${varRef.name}'. Using default value of 0 (false). This can happen with temporary variables if the declaration hasn't yet been hit. Globals are always given a default value on load if a value doesn't exist in the save state.");
          foundValue = IntValue(0);
        }
      }

      state.PushEvaluationStack(foundValue);

      return true;
    } else if (contentObj is NativeFunctionCall) {
      var func = contentObj;
      var funcParams = state.PopEvaluationStackMulti(func.numberOfParameters);
      var result = func.Call(funcParams);
      state.PushEvaluationStack(result);
      return true;
    }

    return false;
  }

  void ChoosePathString(String path,
      [bool resetCallstack = true, List? arguments]) {
    onChoosePathString.fire([path, arguments]);
    if (resetCallstack) {
      ResetCallstack();
    } else {
      if (state.callStack.currentElement.type == PushPopType.Function) {
        String funcDetail = "";
        var container = state.callStack.currentElement.currentPointer.container;
        if (container != null) {
          funcDetail = "(" + container.path.toString() + ") ";
        }
        throw Exception("Story was running a function " +
            funcDetail +
            "when you called ChoosePathString(" +
            path +
            ") - this is almost certainly not not what you want! Full stack trace: \n" +
            state.callStack.callStackTrace);
      }
    }

    state.PassArgumentsToEvaluationStack(arguments);
    ChoosePath(Path.new3(path));
  }

  void ChoosePath(Path p, [bool incrementingTurnIndex = true]) {
    state.SetChosenPath(p, incrementingTurnIndex);

    VisitChangedContainersDueToDivert();
  }

  void ChooseChoiceIndex(int choiceIdx) {
    var choices = currentChoices;
    Assert(choiceIdx >= 0 && choiceIdx < choices.length, "choice out of range");

    var choiceToChoose = choices[choiceIdx];
    onMakeChoice.fire([choiceToChoose]);
    state.callStack.currentThread = choiceToChoose.threadAtGeneration!;

    ChoosePath(choiceToChoose.targetPath!);
  }

  bool HasFunction(String functionName) {
    try {
      return KnotContainerWithName(functionName) != null;
    } catch (_) {
      return false;
    }
  }

  dynamic EvaluateFunction(String functionName, [List? arguments]) {
    var dict = EvaluateFunction(functionName, arguments);
    return dict['return_value'];
  }

  Map<String, dynamic> EvaluateFunctionWithTextOutput(String functionName,
      [List? arguments]) {
    onEvaluateFunction.fire([functionName, arguments]);

    if (functionName.trim().isEmpty) {
      throw Exception("Function is empty or white space.");
    }

    var funcContainer = KnotContainerWithName(functionName);
    if (funcContainer == null) {
      throw Exception("Function doesn't exist: '" + functionName + "'");
    }

    var outputStreamBefore = List<RuntimeObject>.of(state.outputStream);
    state.ResetOutput();

    state.StartFunctionEvaluationFromGame(funcContainer, arguments);

    var stringOutput = StringBuilder();
    while (canContinue) {
      stringOutput.add(Continue());
    }

    var ret = <String, dynamic>{};
    ret['text_output'] = stringOutput.toString();

    state.ResetOutput(outputStreamBefore);

    var result = state.CompleteFunctionEvaluationFromGame();
    onCompleteEvaluateFunction
        .fire([functionName, arguments, ret['text_output'], result]);
    ret['return_value'] = result;
    return ret;
  }

  RuntimeObject? EvaluateExpression(Container exprContainer) {
    int startCallStackHeight = state.callStack.elements.length;

    state.callStack.Push(PushPopType.Tunnel);

    _temporaryEvaluationContainer = exprContainer;

    state.GoToStart();

    int evalStackHeight = state.evaluationStack.length;

    Continue();

    _temporaryEvaluationContainer = null;

    if (state.callStack.elements.length > startCallStackHeight) {
      state.PopCallstack();
    }

    int endStackHeight = state.evaluationStack.length;
    if (endStackHeight > evalStackHeight) {
      return state.PopEvaluationStack();
    } else {
      return null;
    }
  }

  bool allowExternalFunctionFallbacks = false;

  void CallExternalFunction(String funcName, int numberOfArguments) {
    ExternalFunctionDef? funcDef = _externals[funcName];
    Container? fallbackFunctionContainer;

    var foundExternal = funcDef != null;

    if (foundExternal &&
        !funcDef.lookaheadSafe &&
        _stateSnapshotAtLastNewline != null) {
      _sawLookaheadUnsafeFunctionAfterNewline = true;
      return;
    }

    if (!foundExternal) {
      if (allowExternalFunctionFallbacks) {
        fallbackFunctionContainer = KnotContainerWithName(funcName);
        Assert(
            fallbackFunctionContainer != null,
            "Trying to call EXTERNAL function '" +
                funcName +
                "' which has not been bound, and fallback ink function could not be found.");

        // Divert direct into fallback function and we're done
        state.callStack.Push(PushPopType.Function,
            outputStreamLengthWithPushed: state.outputStream.length);
        state.divertedPointer = Pointer.StartOf(fallbackFunctionContainer!);
        return;
      } else {
        Assert(
            false,
            "Trying to call EXTERNAL function '" +
                funcName +
                "' which has not been bound (and ink fallbacks disabled).");
      }
    }

    var arguments = [];
    for (int i = 0; i < numberOfArguments; ++i) {
      var poppedObj = state.PopEvaluationStack() as Value;
      var valueObj = poppedObj.valueObject;
      arguments.add(valueObj);
    }

    arguments = arguments.reversed.toList();

    dynamic funcResult = funcDef!.function(arguments);

    RuntimeObject? returnObj;
    if (funcResult != null) {
      returnObj = Value.Create(funcResult);
    } else {
      returnObj = Void();
    }

    state.PushEvaluationStack(returnObj);
  }

  void BindExternalFunctionGeneral(String funcName, ExternalFunction func,
      [bool lookaheadSafe = false]) {
    Assert(!_externals.containsKey(funcName),
        "Function '" + funcName + "' has already been bound.");
    _externals[funcName] =
        ExternalFunctionDef(function: func, lookaheadSafe: lookaheadSafe);
  }

  void UnbindExternalFunction(String funcName) {
    Assert(_externals.containsKey(funcName),
        "Function '" + funcName + "' has not been bound.");
    _externals.remove(funcName);
  }

  List<String> get globalTags => TagsAtStartOfFlowContainerWithPathString("");

  List<String> TagsForContentAtPath(String path) {
    return TagsAtStartOfFlowContainerWithPathString(path);
  }

  List<String> TagsAtStartOfFlowContainerWithPathString(String pathString) {
    var path = Path.new3(pathString);

    var flowContainer = ContentAtPath(path).container;
    while (true) {
      var firstContent = flowContainer?.content[0];
      if (firstContent is Container) {
        flowContainer = firstContent;
      } else {
        break;
      }
    }

    List<String> tags = [];
    for (var c in flowContainer!.content) {
      var tag = c.csAs<Tag>();
      if (tag != null) {
        tags.add(tag.text);
      } else {
        break;
      }
    }

    return tags;
  }

  void NextContent() {
    state.previousPointer = state.currentPointer;

    if (!state.divertedPointer.isNull) {
      state.currentPointer = state.divertedPointer;
      state.divertedPointer = Pointer.Null;

      VisitChangedContainersDueToDivert();

      if (!state.currentPointer.isNull) {
        return;
      }
    }

    bool successfulPointerIncrement = IncrementContentPointer();

    if (!successfulPointerIncrement) {
      bool didPop = false;

      if (state.callStack.CanPop(PushPopType.Function)) {
        state.PopCallstack(PushPopType.Function);

        if (state.inExpressionEvaluation) {
          state.PushEvaluationStack(Void());
        }

        didPop = true;
      } else if (state.callStack.canPopThread) {
        state.callStack.PopThread();

        didPop = true;
      } else {
        state.TryExitFunctionEvaluationFromGame();
      }

      // Step past the point where we last called out
      if (didPop && !state.currentPointer.isNull) {
        NextContent();
      }
    }
  }

  bool IncrementContentPointer() {
    bool successfulIncrement = true;

    var pointer = state.callStack.currentElement.currentPointer;
    pointer = pointer.withIndex(pointer.index + 1);

    while (pointer.index >= pointer.container!.content.length) {
      successfulIncrement = false;

      Container? nextAncestor = pointer.container!.parent?.csAs<Container>();
      if (nextAncestor == null) {
        break;
      }

      var indexInAncestor = nextAncestor.content.indexOf(pointer.container!);
      if (indexInAncestor == -1) {
        break;
      }

      pointer = Pointer(container: nextAncestor, index: indexInAncestor + 1);
      successfulIncrement = true;
    }

    if (!successfulIncrement) pointer = Pointer.Null;

    state.callStack.currentElement.currentPointer = pointer;

    return successfulIncrement;
  }

  bool TryFollowDefaultInvisibleChoice() {
    var allChoices = state.currentChoices;

    var invisibleChoices =
        allChoices.where((c) => c.isInvisibleDefault).toList();
    if (invisibleChoices.isEmpty ||
        allChoices.length > invisibleChoices.length) {
      return false;
    }

    var choice = invisibleChoices[0];

    state.callStack.currentThread = choice.threadAtGeneration!;

    if (_stateSnapshotAtLastNewline != null) {
      state.callStack.currentThread = state.callStack.ForkThread();
    }

    ChoosePath(choice.targetPath!, false);

    return true;
  }

  int NextSequenceShuffleIndex() {
    var numElementsIntVal = state.PopEvaluationStack().csAs<IntValue>();
    if (numElementsIntVal == null) {
      Error("expected number of elements in sequence for shuffle index");
      return 0;
    }

    var seqContainer = state.currentPointer.container;

    int numElements = numElementsIntVal.value;

    var seqCountVal = state.PopEvaluationStack().csAs<IntValue>();
    var seqCount = seqCountVal!.value;
    var loopIndex = seqCount / numElements;
    var iterationIndex = seqCount % numElements;

    var seqPathStr = seqContainer!.path.toString();
    int sequenceHash = 0;
    for (int c in seqPathStr.codeUnits) {
      sequenceHash += c;
    }
    var randomSeed = sequenceHash + loopIndex + state.storySeed;
    var random = Random(randomSeed.toInt());

    var unpickedIndices = <int>[];
    for (int i = 0; i < numElements; ++i) {
      unpickedIndices.add(i);
    }

    for (int i = 0; i <= iterationIndex; ++i) {
      var chosen = random.nextInt(1 << 32) % unpickedIndices.length;
      var chosenIndex = unpickedIndices[chosen];
      unpickedIndices.removeAt(chosen);

      if (i == iterationIndex) {
        return chosenIndex;
      }
    }

    throw Exception("Should never reach here");
  }

  void Error(String message, [bool useEndLineNumber = false]) {
    var e = StoryException(message);
    e.useEndLineNumber = useEndLineNumber;
    throw e;
  }

  void Warning(String message) {
    AddError(message, isWarning: true);
  }

  void AddError(String message,
      {bool isWarning = false, bool useEndLineNumber = false}) {
    var dm = currentDebugMetadata;

    var errorTypeStr = isWarning ? "WARNING" : "ERROR";

    if (dm != null) {
      int lineNum = useEndLineNumber ? dm.endLineNumber : dm.startLineNumber;
      message =
          "RUNTIME $errorTypeStr: '${dm.fileName}' line $lineNum: $message";
    } else if (!state.currentPointer.isNull) {
      message =
          "RUNTIME $errorTypeStr: (${state.currentPointer.path}): $message";
    } else {
      message = "RUNTIME " + errorTypeStr + ": " + message;
    }

    state.AddError(message, isWarning);

    if (!isWarning) {
      state.ForceEnd();
    }
  }

  void Assert(bool condition, [String? message]) {
    if (condition == false) {
      message ??= "Story assert";
      throw Exception(message + " " + currentDebugMetadata.toString());
    }
  }

  DebugMetadata? get currentDebugMetadata {
    DebugMetadata? dm;

    var pointer = state.currentPointer;
    if (!pointer.isNull) {
      dm = pointer.Resolve()!.debugMetadata;
      if (dm != null) {
        return dm;
      }
    }

    for (int i = state.callStack.elements.length - 1; i >= 0; --i) {
      pointer = state.callStack.elements[i].currentPointer;
      if (!pointer.isNull && pointer.Resolve() != null) {
        dm = pointer.Resolve()!.debugMetadata;
        if (dm != null) {
          return dm;
        }
      }
    }

    for (int i = state.outputStream.length - 1; i >= 0; --i) {
      var outputObj = state.outputStream[i];
      dm = outputObj.debugMetadata;
      if (dm != null) {
        return dm;
      }
    }

    return null;
  }

  int get currentLineNumber {
    var dm = currentDebugMetadata;
    if (dm != null) {
      return dm.startLineNumber;
    }
    return 0;
  }

  Container get mainContentContainer {
    if (_temporaryEvaluationContainer != null) {
      return _temporaryEvaluationContainer!;
    } else {
      return _mainContentContainer;
    }
  }

  late final Container _mainContentContainer;

  final Map<String, ExternalFunctionDef> _externals = {};

  Container? _temporaryEvaluationContainer;

  StoryState? _state;

  StoryState? _stateSnapshotAtLastNewline;
  bool _sawLookaheadUnsafeFunctionAfterNewline = false;

  int _recursiveContinueCount = 0;

  bool _asyncSaving = false;

  //Profiler _profiler;
}

enum OutputStateChange { NoChange, ExtendedBeyondNewline, NewlineRemoved }

class ExternalFunctionDef {
  final ExternalFunction function;
  final bool lookaheadSafe;
  ExternalFunctionDef({required this.function, this.lookaheadSafe = false});
}

typedef ExternalFunction = dynamic Function(List args);
//typedef VariableObserver = void Function(String variableName, dynamic newValue);
