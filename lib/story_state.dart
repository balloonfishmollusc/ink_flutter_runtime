// reviewed

import 'dart:convert';
import 'dart:math';
import 'addons/extra.dart';
import 'call_stack.dart';
import 'choice.dart';
import 'container.dart';
import 'control_command.dart';
import 'flow.dart';
import 'glue.dart';
import 'json_serialisation.dart';
import 'path.dart';
import 'pointer.dart';
import 'push_pop.dart';
import 'runtime_object.dart';
import 'state_patch.dart';
import 'story.dart';
import 'tag.dart';
import 'value.dart';
import 'variables_state.dart';
import 'void.dart';

class StoryState {
  static const int kInkSaveStateVersion = 9;
  static const int kMinCompatibleLoadVersion = 8;

  Event onDidLoadState = Event(0);

  String ToJson() {
    return jsonEncode(WriteJson() as Map<String, dynamic>);
  }

  void LoadJson(String json) {
    var jObject = jsonDecode(json);
    LoadJsonObj(jObject);
    onDidLoadState.fire();
  }

  int VisitCountAtPathString(String pathString) {
    int? visitCountOut;

    if (_patch != null) {
      var container = story.ContentAtPath(Path.new3(pathString)).container;
      if (container == null) {
        throw Exception("Content at path not found: " + pathString);
      }

      visitCountOut = _patch?.visitCounts[container];
      if (visitCountOut != null) return visitCountOut;
    }

    visitCountOut = _visitCounts[pathString];
    if (visitCountOut != null) return visitCountOut;

    return 0;
  }

  int VisitCountForContainer(Container container) {
    if (!container.visitsShouldBeCounted) {
      story.Error(
          "Read count for target (${container.name} - on ${container.debugMetadata}) unknown.");
      return 0;
    }

    int? count = _patch?.visitCounts[container];
    if (_patch != null && count != null) {
      return count;
    }

    var containerPathStr = container.path.toString();
    count = _visitCounts[containerPathStr];
    return count ?? 0;
  }

  void IncrementVisitCountForContainer(Container container) {
    if (_patch != null) {
      var currCount = VisitCountForContainer(container);
      currCount++;
      _patch!.visitCounts[container] = currCount;
      return;
    }

    int count = 0;
    var containerPathStr = container.path.toString();
    count = _visitCounts[containerPathStr] ?? 0;
    count++;
    _visitCounts[containerPathStr] = count;
  }

  void RecordTurnIndexVisitToContainer(Container container) {
    if (_patch != null) {
      _patch!.turnIndices[container] = currentTurnIndex;
      return;
    }

    var containerPathStr = container.path.toString();
    _turnIndices[containerPathStr] = currentTurnIndex;
  }

  int TurnsSinceForContainer(Container container) {
    if (!container.turnIndexShouldBeCounted) {
      story.Error(
          "TURNS_SINCE() for target (${container.name} - on ${container.debugMetadata}) unknown.");
    }

    int? index;

    index = _patch?.turnIndices[container];
    if (_patch != null && index != null) {
      return currentTurnIndex - index;
    }

    var containerPathStr = container.path.toString();
    index = _turnIndices[containerPathStr];
    if (index != null) {
      return currentTurnIndex - index;
    } else {
      return -1;
    }
  }

  int get callstackDepth => callStack.depth;

  // REMEMBER! REMEMBER! REMEMBER!
  // When adding state, update the Copy method, and serialisation.
  // REMEMBER! REMEMBER! REMEMBER!

  List<RuntimeObject> get outputStream => _currentFlow.outputStream;

  List<Choice> get currentChoices {
    if (canContinue) return [];
    return _currentFlow.currentChoices;
  }

  List<Choice> get generatedChoices => _currentFlow.currentChoices;

  final List<String> currentErrors = [];
  final List<String> currentWarnings = [];
  VariablesState? variablesState;
  CallStack get callStack => _currentFlow.callStack;

  List<RuntimeObject> evaluationStack = [];
  Pointer divertedPointer = Pointer.Null;

  int currentTurnIndex = 0;
  int storySeed = 0;
  int previousRandom = 0;
  bool didSafeExit = false;

  final Story story;

  /// <summary>
  /// String representation of the location where the story currently is.
  /// </summary>
  String? get currentPathString {
    var pointer = currentPointer;
    if (pointer.isNull) {
      return null;
    } else {
      return pointer.path.toString();
    }
  }

  Pointer get currentPointer => callStack.currentElement.currentPointer;

  set currentPointer(Pointer value) {
    callStack.currentElement.currentPointer = value;
  }

  Pointer get previousPointer => callStack.currentThread.previousPointer;

  set previousPointer(Pointer value) {
    callStack.currentThread.previousPointer = value;
  }

  bool get canContinue => !currentPointer.isNull && !hasError;

  bool get hasError => currentErrors.isNotEmpty;

  bool get hasWarning => currentWarnings.isNotEmpty;

  String? get currentText {
    if (_outputStreamTextDirty) {
      var sb = StringBuilder();

      for (var outputObj in outputStream) {
        var textContent = outputObj.csAs<StringValue>();
        if (textContent != null) {
          sb.add(textContent.value);
        }
      }

      _currentText = CleanOutputWhitespace(sb.toString());

      _outputStreamTextDirty = false;
    }

    return _currentText;
  }

  String CleanOutputWhitespace(String str) {
    var sb = StringBuilder();

    int currentWhitespaceStart = -1;
    int startOfLine = 0;

    for (int i = 0; i < str.length; i++) {
      var c = str[i];

      bool isInlineWhitespace = c == ' ' || c == '\t';

      if (isInlineWhitespace && currentWhitespaceStart == -1) {
        currentWhitespaceStart = i;
      }

      if (!isInlineWhitespace) {
        if (c != '\n' &&
            currentWhitespaceStart > 0 &&
            currentWhitespaceStart != startOfLine) {
          sb.add(' ');
        }
        currentWhitespaceStart = -1;
      }

      if (c == '\n') startOfLine = i + 1;

      if (!isInlineWhitespace) sb.add(c);
    }

    return sb.toString();
  }

  String? _currentText;

  List<String> get currentTags {
    if (_outputStreamTagsDirty) {
      _currentTags = <String>[];

      for (var outputObj in outputStream) {
        var tag = outputObj.csAs<Tag>();
        if (tag != null) {
          _currentTags.add(tag.text);
        }
      }

      _outputStreamTagsDirty = false;
    }

    return _currentTags;
  }

  List<String> _currentTags = [];

  String get currentFlowName => _currentFlow.name;

  bool get currentFlowIsDefaultFlow => _currentFlow.name == kDefaultFlowName;

  List<String> get aliveFlowNames {
    if (_aliveFlowNamesDirty) {
      _aliveFlowNames = <String>[];

      if (_namedFlows != null) {
        for (String flowName in _namedFlows!.keys) {
          if (flowName != kDefaultFlowName) {
            _aliveFlowNames.add(flowName);
          }
        }
      }

      _aliveFlowNamesDirty = false;
    }

    return _aliveFlowNames;
  }

  List<String> _aliveFlowNames = [];

  bool get inExpressionEvaluation =>
      callStack.currentElement.inExpressionEvaluation;

  set inExpressionEvaluation(bool value) {
    callStack.currentElement.inExpressionEvaluation = value;
  }

  StoryState(this.story) {
    _currentFlow = Flow(kDefaultFlowName, story);

    OutputStreamDirty();
    _aliveFlowNamesDirty = true;

    variablesState = VariablesState(callStack);

    currentTurnIndex = -1;

    // Seed the shuffle random numbers
    int timeSeed = DateTime.now().millisecond;
    storySeed = (Random(timeSeed)).nextInt(1 << 32) % 100;
    previousRandom = 0;

    GoToStart();
  }

  void GoToStart() {
    callStack.currentElement.currentPointer =
        Pointer.StartOf(story.mainContentContainer);
  }

  void SwitchFlow_Internal(String flowName) {
    if (_namedFlows == null) {
      _namedFlows = <String, Flow>{};
      _namedFlows![kDefaultFlowName] = _currentFlow;
    }

    if (flowName == _currentFlow.name) {
      return;
    }

    Flow? flow;
    flow = _namedFlows![flowName];
    if (flow == null) {
      flow = Flow(flowName, story);
      _namedFlows![flowName] = flow;
      _aliveFlowNamesDirty = true;
    }

    _currentFlow = flow;
    variablesState!.callStack = _currentFlow.callStack;

    OutputStreamDirty();
  }

  void SwitchToDefaultFlow_Internal() {
    if (_namedFlows == null) return;
    SwitchFlow_Internal(kDefaultFlowName);
  }

  void RemoveFlow_Internal(String flowName) {
    if (flowName == kDefaultFlowName) {
      throw Exception("Cannot destroy default flow");
    }

    if (_currentFlow.name == flowName) {
      SwitchToDefaultFlow_Internal();
    }

    _namedFlows!.remove(flowName);
    _aliveFlowNamesDirty = true;
  }

  StoryState CopyAndStartPatching() {
    var copy = StoryState(story);

    copy._patch = StatePatch(_patch);

    copy._currentFlow.name = _currentFlow.name;
    copy._currentFlow.callStack = CallStack.new2(_currentFlow.callStack);
    copy._currentFlow.currentChoices.addAll(_currentFlow.currentChoices);
    copy._currentFlow.outputStream.addAll(_currentFlow.outputStream);
    copy.OutputStreamDirty();

    if (_namedFlows != null) {
      copy._namedFlows = <String, Flow>{};
      for (var namedFlow in _namedFlows!.entries) {
        copy._namedFlows![namedFlow.key] = namedFlow.value;
      }
      copy._namedFlows![_currentFlow.name] = copy._currentFlow;
      copy._aliveFlowNamesDirty = true;
    }

    if (hasError) {
      copy.currentErrors.clear();
      copy.currentErrors.addAll(currentErrors);
    }
    if (hasWarning) {
      copy.currentWarnings.clear();
      copy.currentWarnings.addAll(currentWarnings);
    }

    copy.variablesState = variablesState;
    copy.variablesState!.callStack = copy.callStack;
    copy.variablesState!.patch = copy._patch;

    copy.evaluationStack.addAll(evaluationStack);

    if (!divertedPointer.isNull) {
      copy.divertedPointer = divertedPointer;
    }

    copy.previousPointer = previousPointer;

    copy._visitCounts = _visitCounts;
    copy._turnIndices = _turnIndices;

    copy.currentTurnIndex = currentTurnIndex;
    copy.storySeed = storySeed;
    copy.previousRandom = previousRandom;

    copy.didSafeExit = didSafeExit;

    return copy;
  }

  void RestoreAfterPatch() {
    variablesState!.callStack = callStack;
    variablesState!.patch = _patch; // usually null
  }

  void ApplyAnyPatch() {
    if (_patch == null) return;

    variablesState!.ApplyPatch();

    for (var pathToCount in _patch!.visitCounts.entries) {
      ApplyCountChanges(pathToCount.key, pathToCount.value, true);
    }

    for (var pathToIndex in _patch!.turnIndices.entries) {
      ApplyCountChanges(pathToIndex.key, pathToIndex.value, false);
    }

    _patch = null;
  }

  void ApplyCountChanges(Container container, int newCount, bool isVisit) {
    var counts = isVisit ? _visitCounts : _turnIndices;
    counts[container.path.toString()] = newCount;
  }

  dynamic WriteJson() {
    var dict = <String, dynamic>{};

    // Flows
    dict["flows"] = <String, dynamic>{};

    // Multi-flow
    if (_namedFlows != null) {
      for (var namedFlow in _namedFlows!.entries) {
        dict["flows"][namedFlow.key] = namedFlow.value.WriteJson();
      }
    }

    // Single flow
    else {
      dict["flows"][_currentFlow.name] = _currentFlow.WriteJson();
    }

    dict["currentFlowName"] = _currentFlow.name;
    dict["variablesState"] = variablesState!.WriteJson();

    dict["evalStack"] = Json.WriteListRuntimeObjs(evaluationStack);

    if (!divertedPointer.isNull) {
      dict["currentDivertTarget"] = divertedPointer.path!.componentsString;
    }

    dict["visitCounts"] = Json.WriteIntDictionary(_visitCounts);
    dict["turnIndices"] = Json.WriteIntDictionary(_turnIndices);

    dict["turnIdx"] = currentTurnIndex;
    dict["storySeed"] = storySeed;
    dict["previousRandom"] = previousRandom;

    dict["inkSaveVersion"] = kInkSaveStateVersion;

    // Not using this right now, but could do in future.
    dict["inkFormatVersion"] = Story.inkVersionCurrent;

    return dict;
  }

  void LoadJsonObj(Map<String, dynamic> jObject) {
    dynamic jSaveVersion = jObject["inkSaveVersion"];
    if (jSaveVersion == null) {
      throw Exception("ink save format incorrect, can't load.");
    } else if (jSaveVersion as int < kMinCompatibleLoadVersion) {
      throw Exception(
          "Ink save format isn't compatible with the current version (saw '$jSaveVersion', but minimum is $kMinCompatibleLoadVersion), so can't load.");
    }

    dynamic flowsObj;
    flowsObj = jObject["flows"];
    if (flowsObj != null) {
      Map<String, dynamic> flowsObjDict = flowsObj;

      if (flowsObjDict.length == 1) {
        _namedFlows = null;
      } else if (_namedFlows == null) {
        _namedFlows = <String, Flow>{};
      } else {
        _namedFlows!.clear();
      }

      for (var namedFlowObj in flowsObjDict.entries) {
        var name = namedFlowObj.key;
        Map<String, dynamic> flowObj = namedFlowObj.value;

        var flow = Flow(name, story, flowObj);

        if (flowsObjDict.length == 1) {
          _currentFlow = Flow(name, story, flowObj);
        } else {
          _namedFlows![name] = flow;
        }
      }

      if (_namedFlows != null && _namedFlows!.length > 1) {
        String currFlowName = jObject["currentFlowName"];
        _currentFlow = _namedFlows![currFlowName]!;
      }
    }

    // Old format: individually load up callstack, output stream, choices in current/default flow
    else {
      throw Exception("Old format is not supported.");
    }

    OutputStreamDirty();
    _aliveFlowNamesDirty = true;

    variablesState!
        .SetJsonToken(jObject["variablesState"] as Map<String, dynamic>);
    variablesState!.callStack = _currentFlow.callStack;

    evaluationStack = Json.JArrayToRuntimeObjList<RuntimeObject>(
        jObject["evalStack"] as List);

    dynamic currentDivertTargetPath = jObject["currentDivertTarget"];
    if (currentDivertTargetPath != null) {
      var divertPath = Path.new3(currentDivertTargetPath.toString());
      divertedPointer = story.PointerAtPath(divertPath);
    }

    _visitCounts = jObject["visitCounts"].cast();
    _turnIndices = jObject["turnIndices"].cast();

    currentTurnIndex = jObject["turnIdx"];
    storySeed = jObject["storySeed"];

    // Not optional, but bug in inkjs means it's actually missing in inkjs saves
    int? previousRandomObj = jObject["previousRandom"];
    if (previousRandomObj != null) {
      previousRandom = previousRandomObj;
    } else {
      previousRandom = 0;
    }
  }

  void ResetErrors() {
    currentErrors.clear();
    currentWarnings.clear();
  }

  void ResetOutput([List<RuntimeObject>? objs]) {
    outputStream.clear();
    if (objs != null) outputStream.addAll(objs);
    OutputStreamDirty();
  }

  void PushToOutputStream(RuntimeObject obj) {
    var text = obj.csAs<StringValue>();
    if (text != null) {
      var listText = TrySplittingHeadTailWhitespace(text);
      if (listText != null) {
        for (var textObj in listText) {
          PushToOutputStreamIndividual(textObj);
        }
        OutputStreamDirty();
        return;
      }
    }

    PushToOutputStreamIndividual(obj);

    OutputStreamDirty();
  }

  void PopFromOutputStream(int count) {
    outputStream.removeRange(outputStream.length - count, outputStream.length);
    OutputStreamDirty();
  }

  // At both the start and the end of the String, split out the lines like so:
  //
  //  "   \n  \n     \n  the String \n is awesome \n     \n     "
  //      ^-----------^                           ^-------^
  //
  // Excess newlines are converted into single newlines, and spaces discarded.
  // Outside spaces are significant and retained. "Interior" newlines within
  // the main String are ignored, since this is for the purpose of gluing only.
  //
  //  - If no splitting is necessary, null is returned.
  //  - A newline on its own is returned in a list for consistency.
  List<StringValue>? TrySplittingHeadTailWhitespace(StringValue single) {
    String str = single.value;

    int headFirstNewlineIdx = -1;
    int headLastNewlineIdx = -1;
    for (int i = 0; i < str.length; i++) {
      var c = str[i];
      if (c == '\n') {
        if (headFirstNewlineIdx == -1) {
          headFirstNewlineIdx = i;
        }
        headLastNewlineIdx = i;
      } else if (c == ' ' || c == '\t') {
        continue;
      } else {
        break;
      }
    }

    int tailLastNewlineIdx = -1;
    int tailFirstNewlineIdx = -1;
    for (int i = str.length - 1; i >= 0; i--) {
      var c = str[i];
      if (c == '\n') {
        if (tailLastNewlineIdx == -1) {
          tailLastNewlineIdx = i;
        }
        tailFirstNewlineIdx = i;
      } else if (c == ' ' || c == '\t') {
        continue;
      } else {
        break;
      }
    }

    // No splitting to be done?
    if (headFirstNewlineIdx == -1 && tailLastNewlineIdx == -1) {
      return null;
    }

    var listTexts = <StringValue>[];
    int innerStrStart = 0;
    int innerStrEnd = str.length;

    if (headFirstNewlineIdx != -1) {
      if (headFirstNewlineIdx > 0) {
        var leadingSpaces = StringValue(str.substring(0, headFirstNewlineIdx));
        listTexts.add(leadingSpaces);
      }
      listTexts.add(StringValue("\n"));
      innerStrStart = headLastNewlineIdx + 1;
    }

    if (tailLastNewlineIdx != -1) {
      innerStrEnd = tailFirstNewlineIdx;
    }

    if (innerStrEnd > innerStrStart) {
      var innerStrText = str.substring(innerStrStart, innerStrEnd);
      listTexts.add(StringValue(innerStrText));
    }

    if (tailLastNewlineIdx != -1 && tailFirstNewlineIdx > headLastNewlineIdx) {
      listTexts.add(StringValue("\n"));
      if (tailLastNewlineIdx < str.length - 1) {
        int numSpaces = (str.length - tailLastNewlineIdx) - 1;
        var trailingSpaces = StringValue(str.substring(
            tailLastNewlineIdx + 1, tailLastNewlineIdx + 1 + numSpaces));
        listTexts.add(trailingSpaces);
      }
    }

    return listTexts;
  }

  void PushToOutputStreamIndividual(RuntimeObject obj) {
    var glue = obj.csAs<Glue>();
    var text = obj.csAs<StringValue>();

    bool includeInOutput = true;

    if (glue != null) {
      TrimNewlinesFromOutputStream();
      includeInOutput = true;
    } else if (text != null) {
      var functionTrimIndex = -1;
      var currEl = callStack.currentElement;
      if (currEl.type == PushPopType.Function) {
        functionTrimIndex = currEl.functionStartInOuputStream;
      }

      int glueTrimIndex = -1;
      for (int i = outputStream.length - 1; i >= 0; i--) {
        var o = outputStream[i];
        var c = o.csAs<ControlCommand>();
        var g = o.csAs<Glue>();

        if (g != null) {
          glueTrimIndex = i;
          break;
        }

        // Don't function-trim past the start of a String evaluation section
        else if (c != null && c.commandType == CommandType.BeginString) {
          if (i >= functionTrimIndex) {
            functionTrimIndex = -1;
          }
          break;
        }
      }

      var trimIndex = -1;
      if (glueTrimIndex != -1 && functionTrimIndex != -1) {
        trimIndex = min(functionTrimIndex, glueTrimIndex);
      } else if (glueTrimIndex != -1) {
        trimIndex = glueTrimIndex;
      } else {
        trimIndex = functionTrimIndex;
      }

      if (trimIndex != -1) {
        if (text.isNewline) {
          includeInOutput = false;
        } else if (text.isNonWhitespace) {
          if (glueTrimIndex > -1) {
            RemoveExistingGlue();
          }

          if (functionTrimIndex > -1) {
            var callstackElements = callStack.elements;
            for (int i = callstackElements.length - 1; i >= 0; i--) {
              var el = callstackElements[i];
              if (el.type == PushPopType.Function) {
                el.functionStartInOuputStream = -1;
              } else {
                break;
              }
            }
          }
        }
      }

      // De-duplicate newlines, and don't ever lead with a newline
      else if (text.isNewline) {
        if (outputStreamEndsInNewline || !outputStreamContainsContent) {
          includeInOutput = false;
        }
      }
    }

    if (includeInOutput) {
      outputStream.add(obj);
      OutputStreamDirty();
    }
  }

  void TrimNewlinesFromOutputStream() {
    int removeWhitespaceFrom = -1;
    int i = outputStream.length - 1;
    while (i >= 0) {
      var obj = outputStream[i];
      var cmd = obj.csAs<ControlCommand>();
      var txt = obj.csAs<StringValue>();

      if (cmd != null || (txt != null && txt.isNonWhitespace)) {
        break;
      } else if (txt != null && txt.isNewline) {
        removeWhitespaceFrom = i;
      }
      i--;
    }

    if (removeWhitespaceFrom >= 0) {
      i = removeWhitespaceFrom;
      while (i < outputStream.length) {
        var text = outputStream[i].csAs<StringValue>();
        if (text != null) {
          outputStream.removeAt(i);
        } else {
          i++;
        }
      }
    }

    OutputStreamDirty();
  }

  // Only called when non-whitespace is appended
  void RemoveExistingGlue() {
    for (int i = outputStream.length - 1; i >= 0; i--) {
      var c = outputStream[i];
      if (c is Glue) {
        outputStream.removeAt(i);
      } else if (c is ControlCommand) {
        break;
      }
    }

    OutputStreamDirty();
  }

  bool get outputStreamEndsInNewline {
    if (outputStream.isNotEmpty) {
      for (int i = outputStream.length - 1; i >= 0; i--) {
        var obj = outputStream[i];
        if (obj is ControlCommand) {
          break;
        }
        var text = outputStream[i].csAs<StringValue>();
        if (text != null) {
          if (text.isNewline) {
            return true;
          } else if (text.isNonWhitespace) {
            break;
          }
        }
      }
    }

    return false;
  }

  bool get outputStreamContainsContent {
    for (var content in outputStream) {
      if (content is StringValue) {
        return true;
      }
    }
    return false;
  }

  bool get inStringEvaluation {
    for (int i = outputStream.length - 1; i >= 0; i--) {
      var cmd = outputStream[i].csAs<ControlCommand>();
      if (cmd != null && cmd.commandType == CommandType.BeginString) {
        return true;
      }
    }

    return false;
  }

  void PushEvaluationStack(RuntimeObject obj) {
    evaluationStack.add(obj);
  }

  RuntimeObject PopEvaluationStack() {
    return evaluationStack.removeLast();
  }

  RuntimeObject PeekEvaluationStack() {
    return evaluationStack.last;
  }

  List<RuntimeObject> PopEvaluationStackMulti(int numberOfObjects) {
    if (numberOfObjects > evaluationStack.length) {
      throw Exception("trying to pop too many dynamics");
    }

    var popped =
        evaluationStack.sublist(evaluationStack.length - numberOfObjects);
    evaluationStack.removeRange(
        evaluationStack.length - numberOfObjects, evaluationStack.length);
    return popped;
  }

  void ForceEnd() {
    callStack.Reset();

    _currentFlow.currentChoices.clear();

    currentPointer = Pointer.Null;
    previousPointer = Pointer.Null;

    didSafeExit = true;
  }

  void TrimWhitespaceFromFunctionEnd() {
    assert(callStack.currentElement.type == PushPopType.Function);

    var functionStartPoint =
        callStack.currentElement.functionStartInOuputStream;

    if (functionStartPoint == -1) {
      functionStartPoint = 0;
    }

    // Trim whitespace from END of function call
    for (int i = outputStream.length - 1; i >= functionStartPoint; i--) {
      var obj = outputStream[i];
      var txt = obj.csAs<StringValue>();
      var cmd = obj.csAs<ControlCommand>();
      if (txt == null) continue;
      if (cmd != null) break;

      if (txt.isNewline || txt.isInlineWhitespace) {
        outputStream.removeAt(i);
        OutputStreamDirty();
      } else {
        break;
      }
    }
  }

  void PopCallstack([PushPopType? popType]) {
    if (callStack.currentElement.type == PushPopType.Function) {
      TrimWhitespaceFromFunctionEnd();
    }

    callStack.Pop(popType);
  }

  void SetChosenPath(Path path, bool incrementingTurnIndex) {
    _currentFlow.currentChoices.clear();

    var newPointer = story.PointerAtPath(path);
    if (!newPointer.isNull && newPointer.index == -1) {
      newPointer.index = 0;
    }

    currentPointer = newPointer;

    if (incrementingTurnIndex) {
      currentTurnIndex++;
    }
  }

  void StartFunctionEvaluationFromGame(
      Container funcContainer, List? arguments) {
    callStack.Push(PushPopType.FunctionEvaluationFromGame,
        externalEvaluationStackHeight: evaluationStack.length);
    callStack.currentElement.currentPointer = Pointer.StartOf(funcContainer);

    PassArgumentsToEvaluationStack(arguments);
  }

  void PassArgumentsToEvaluationStack(List? arguments) {
    if (arguments != null) {
      for (int i = 0; i < arguments.length; i++) {
        if (!(arguments[i] is int ||
            arguments[i] is double ||
            arguments[i] is String ||
            arguments[i] is bool)) {
          throw Exception(
              "ink arguments when calling EvaluateFunction / ChoosePathStringWithParameters must be int, float, String, bool or InkList. Argument was " +
                  (arguments[i] == null
                      ? "null"
                      : arguments[i].runtimeType.toString()));
        }

        PushEvaluationStack(Value.Create(arguments[i]));
      }
    }
  }

  bool TryExitFunctionEvaluationFromGame() {
    if (callStack.currentElement.type ==
        PushPopType.FunctionEvaluationFromGame) {
      currentPointer = Pointer.Null;
      didSafeExit = true;
      return true;
    }

    return false;
  }

  dynamic CompleteFunctionEvaluationFromGame() {
    if (callStack.currentElement.type !=
        PushPopType.FunctionEvaluationFromGame) {
      throw Exception(
          "Expected external function evaluation to be complete. Stack trace: " +
              callStack.callStackTrace);
    }

    int originalEvaluationStackHeight =
        callStack.currentElement.evaluationStackHeightWhenPushed;

    RuntimeObject? returnedObj;
    while (evaluationStack.length > originalEvaluationStackHeight) {
      var poppedObj = PopEvaluationStack();
      returnedObj ??= poppedObj;
    }

    PopCallstack(PushPopType.FunctionEvaluationFromGame);

    if (returnedObj != null) {
      if (returnedObj is Void) {
        return null;
      }

      var returnVal = returnedObj as Value;
      if (returnVal.valueType == ValueType.DivertTarget) {
        return returnVal.valueObject.toString();
      }

      return returnVal.valueObject;
    }

    return null;
  }

  void AddError(String message, bool isWarning) {
    if (!isWarning) {
      currentErrors.add(message);
    } else {
      currentWarnings.add(message);
    }
  }

  void OutputStreamDirty() {
    _outputStreamTextDirty = true;
    _outputStreamTagsDirty = true;
  }

  Map<String, int> _visitCounts = {};
  Map<String, int> _turnIndices = {};
  bool _outputStreamTextDirty = true;
  bool _outputStreamTagsDirty = true;

  StatePatch? _patch;

  late Flow _currentFlow;
  Map<String, Flow>? _namedFlows;
  static const String kDefaultFlowName = "DEFAULT_FLOW";
  bool _aliveFlowNamesDirty = true;
}
