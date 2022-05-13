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
  /// <summary>
  /// The current version of the state save file JSON-based format.
  /// </summary>
  static const int kInkSaveStateVersion =
      9; // new: multi-flows, but backward compatible
  static const int kMinCompatibleLoadVersion = 8;

  /// <summary>
  /// Callback for when a state is loaded
  /// </summary>
  Event onDidLoadState = Event(0);

  /// <summary>
  /// Exports the current state to json format, in order to save the game.
  /// </summary>
  /// <returns>The save state in json format.</returns>
  String ToJson() {
    return jsonEncode(WriteJson() as Map<String, dynamic>);
  }

  /// <summary>
  /// Loads a previously saved state in JSON format.
  /// </summary>
  /// <param name="json">The JSON String to load.</param>
  void LoadJson(String json) {
    var jObject = jsonDecode(json);
    LoadJsonObj(jObject);
    onDidLoadState.fire();
  }

  /// <summary>
  /// Gets the visit/read count of a particular Container at the given path.
  /// For a knot or stitch, that path String will be in the form:
  ///
  ///     knot
  ///     knot.stitch
  ///
  /// </summary>
  /// <returns>The number of times the specific knot or stitch has
  /// been enountered by the ink engine.</returns>
  /// <param name="pathString">The dot-separated path String of
  /// the specific knot or stitch.</param>
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
          "Read count for target (${container.name} - on $container.debugMetadata) unknown.");
      return 0;
    }

    int? count = _patch?.visitCounts[container];
    if (_patch != null && count != null) {
      return count;
    }

    var containerPathStr = container.path.toString();
    count = _visitCounts[containerPathStr];
    return count!;
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
    count = _visitCounts[containerPathStr]!;
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

    int? index = 0;

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
    // If we can continue generating text content rather than choices,
    // then we reflect the choice list as being empty, since choices
    // should always come at the end.
    if (canContinue) return [];
    return _currentFlow.currentChoices;
  }

  List<Choice> get generatedChoices => _currentFlow.currentChoices;

  // TODO: Consider removing currentErrors / currentWarnings altogether
  // and relying on client error handler code immediately handling StoryExceptions etc
  // Or is there a specific reason we need to collect potentially multiple
  // errors before throwing/exiting?
  final List<String> currentErrors = [];
  final List<String> currentWarnings = [];
  VariablesState? variablesState;
  CallStack get callStack => _currentFlow.callStack;

  List<RuntimeObject> evaluationStack = [];
  Pointer? divertedPointer;

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
    if (pointer.isNull != false) {
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

  bool get canContinue => currentPointer.isNull && !hasError;

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

  String? _currentText;

  // Cleans inline whitespace in the following way:
  //  - Removes all whitespace from the start and end of line (including just before a \n)
  //  - Turns all consecutive space and tab runs into single spaces (HTML style)
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

    evaluationStack = <RuntimeObject>[];

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

  void SwitchFlow_Internal(String? flowName) {
    if (flowName == null) {
      throw Exception("Must pass a non-null String to Story.SwitchFlow");
    }

    if (_namedFlows == null) {
      _namedFlows = <String, Flow>{};
      _namedFlows![kDefaultFlowName] = _currentFlow;
    }

    if (flowName == _currentFlow.name) {
      return;
    }

    Flow? flow;
    flow = _namedFlows![flowName];
    if (!(flow != null)) {
      flow = Flow(flowName, story);
      _namedFlows![flowName] = flow;
      _aliveFlowNamesDirty = true;
    }

    _currentFlow = flow;
    variablesState!.callStack = _currentFlow.callStack;

    // Cause text to be regenerated from output stream if necessary
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

    // If we're currently in the flow that's being removed, switch back to default
    if (_currentFlow.name == flowName) {
      SwitchToDefaultFlow_Internal();
    }

    _namedFlows!.remove(flowName);
    _aliveFlowNamesDirty = true;
  }

  // Warning: Any RuntimeObject content referenced within the StoryState will
  // be re-referenced rather than cloned. This is generally okay though since
  // RuntimeObjects are treated as immutable after they've been set up.
  // (e.g. we don't edit a Runtime.StringValue after it's been created an added.)
  // I wonder if there's a sensible way to enforce that..??
  StoryState CopyAndStartPatching() {
    var copy = StoryState(story);

    copy._patch = StatePatch(_patch);

    // Hijack the default flow to become a copy of our current one
    // If the patch is applied, then this flow will replace the old one in _namedFlows
    copy._currentFlow.name = _currentFlow.name;
    copy._currentFlow.callStack = CallStack.new2(_currentFlow.callStack);
    copy._currentFlow.currentChoices.addAll(_currentFlow.currentChoices);
    copy._currentFlow.outputStream.addAll(_currentFlow.outputStream);
    copy.OutputStreamDirty();

    // The copy of the state has its own copy of the named flows dictionary,
    // except with the current flow replaced with the copy above
    // (Assuming we're in multi-flow mode at all. If we're not then
    // the above copy is simply the default flow copy and we're done)
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

    // ref copy - exactly the same variables state!
    // we're expecting not to read it only while in patch mode
    // (though the callstack will be modified)
    copy.variablesState = variablesState;
    copy.variablesState!.callStack = copy.callStack;
    copy.variablesState!.patch = copy._patch;

    copy.evaluationStack.addAll(evaluationStack);

    if (!divertedPointer!.isNull) {
      copy.divertedPointer = divertedPointer;
    }

    copy.previousPointer = previousPointer;

    // visit counts and turn indicies will be read only, not modified
    // while in patch mode
    copy._visitCounts = _visitCounts;
    copy._turnIndices = _turnIndices;

    copy.currentTurnIndex = currentTurnIndex;
    copy.storySeed = storySeed;
    copy.previousRandom = previousRandom;

    copy.didSafeExit = didSafeExit;

    return copy;
  }

  void RestoreAfterPatch() {
    // VariablesState was being borrowed by the patched
    // state, so restore it with our own callstack.
    // _patch will be null normally, but if you're in the
    // middle of a save, it may contain a _patch for save purpsoes.
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

    if (!divertedPointer!.isNull) {
      dict["currentDivertTarget"] = divertedPointer!.path!.componentsString;
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
    if (!(jSaveVersion != null)) {
      throw Exception("ink save format incorrect, can't load.");
    } else if (jSaveVersion as int < kMinCompatibleLoadVersion) {
      throw Exception(
          "Ink save format isn't compatible with the current version (saw '$jSaveVersion', but minimum is $kMinCompatibleLoadVersion), so can't load.");
    }

    // Flows: Always exists in latest format (even if there's just one default)
    // but this dictionary doesn't exist in prev format
    dynamic flowsObj;
    flowsObj = jObject["flows"];
    if (flowsObj != null) {
      Map<String, dynamic> flowsObjDict = flowsObj;

      // Single default flow
      if (flowsObjDict.length == 1) {
        _namedFlows = null;
      } else if (_namedFlows == null) {
        _namedFlows = <String, Flow>{};
      } else {
        _namedFlows!.clear();
      }

      // Load up each flow (there may only be one)
      for (var namedFlowObj in flowsObjDict.entries) {
        var name = namedFlowObj.key;
        Map<String, dynamic> flowObj = namedFlowObj.value;

        // Load up this flow using JSON data
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
      _namedFlows = null;
      _currentFlow.name = kDefaultFlowName;
      _currentFlow.callStack.SetJsonToken(
          jObject["callstackThreads"] as Map<String, dynamic>, story);
      _currentFlow.outputStream = Json.JArrayToRuntimeObjList<RuntimeObject>(
          jObject["outputStream"] as List<dynamic>);
      _currentFlow.currentChoices = Json.JArrayToRuntimeObjList<Choice>(
          jObject["currentChoices"] as List<dynamic>);

      dynamic jChoiceThreadsObj = jObject["choiceThreads"];
      _currentFlow.LoadFlowChoiceThreads(
          jChoiceThreadsObj as Map<String, dynamic>, story);
    }

    OutputStreamDirty();
    _aliveFlowNamesDirty = true;

    variablesState!
        .SetJsonToken(jObject["variablesState"] as Map<String, dynamic>);
    variablesState!.callStack = _currentFlow.callStack;

    evaluationStack = Json.JArrayToRuntimeObjList<RuntimeObject>(
        jObject["evalStack"] as List<dynamic>);

    dynamic currentDivertTargetPath = jObject["currentDivertTarget"];
    if (currentDivertTargetPath != null) {
      var divertPath = Path.new3(currentDivertTargetPath.toString());
      divertedPointer = story.PointerAtPath(divertPath);
    }

    _visitCounts = jObject["visitCounts"].Cast();
    _turnIndices = jObject["turnIndices"].Cast();

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

  // Push to output stream, but split out newlines in text for consistency
  // in dealing with them later.
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
      var innerStrText =
          str.substring(innerStrStart, innerStrEnd - innerStrStart);
      listTexts.add(StringValue(innerStrText));
    }

    if (tailLastNewlineIdx != -1 && tailFirstNewlineIdx > headLastNewlineIdx) {
      listTexts.add(StringValue("\n"));
      if (tailLastNewlineIdx < str.length - 1) {
        int numSpaces = (str.length - tailLastNewlineIdx) - 1;
        var trailingSpaces =
            StringValue(str.substring(tailLastNewlineIdx + 1, numSpaces));
        listTexts.add(trailingSpaces);
      }
    }

    return listTexts;
  }

  void PushToOutputStreamIndividual(RuntimeObject obj) {
    var glue = obj.csAs<Glue>();
    var text = obj.csAs<StringValue>();

    bool includeInOutput = true;

    // New glue, so chomp away any whitespace from the end of the stream
    if (glue != null) {
      TrimNewlinesFromOutputStream();
      includeInOutput = true;
    }

    // New text: do we really want to append it, if it's whitespace?
    // Two different reasons for whitespace to be thrown away:
    //   - Function start/end trimming
    //   - User defined glue: <>
    // We also need to know when to stop trimming, when there's non-whitespace.
    else if (text != null) {
      // Where does the current function call begin?
      var functionTrimIndex = -1;
      var currEl = callStack.currentElement;
      if (currEl.type == PushPopType.Function) {
        functionTrimIndex = currEl.functionStartInOuputStream;
      }

      // Do 2 things:
      //  - Find latest glue
      //  - Check whether we're in the middle of String evaluation
      // If we're in String eval within the current function, we
      // don't want to trim back further than the length of the current String.
      int glueTrimIndex = -1;
      for (int i = outputStream.length - 1; i >= 0; i--) {
        var o = outputStream[i];
        var c = o.csAs<ControlCommand>();
        var g = o.csAs<Glue>();

        // Find latest glue
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

      // Where is the most agressive (earliest) trim point?
      var trimIndex = -1;
      if (glueTrimIndex != -1 && functionTrimIndex != -1) {
        trimIndex = min(functionTrimIndex, glueTrimIndex);
      } else if (glueTrimIndex != -1) {
        trimIndex = glueTrimIndex;
      } else {
        trimIndex = functionTrimIndex;
      }

      // So, are we trimming then?
      if (trimIndex != -1) {
        // While trimming, we want to throw all newlines away,
        // whether due to glue or the start of a function
        if (text.isNewline) {
          includeInOutput = false;
        }

        // Able to completely reset when normal text is pushed
        else if (text.isNonWhitespace) {
          if (glueTrimIndex > -1) {
            RemoveExistingGlue();
          }

          // Tell all functions in callstack that we have seen proper text,
          // so trimming whitespace at the start is done.
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

    // Work back from the end, and try to find the point where
    // we need to start removing content.
    //  - Simply work backwards to find the first newline in a String of whitespace
    // e.g. This is the content   \n   \n\n
    //                            ^---------^ whitespace to remove
    //                        ^--- first while loop stops here
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

    // Remove the whitespace
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
        // e.g. BeginString
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
    var obj = evaluationStack[evaluationStack.length - 1];
    evaluationStack.removeAt(evaluationStack.length - 1);
    return obj;
  }

  RuntimeObject PeekEvaluationStack() {
    return evaluationStack[evaluationStack.length - 1];
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

  /// <summary>
  /// Ends the current ink flow, unwrapping the callstack but without
  /// affecting any variables. Useful if the ink is (say) in the middle
  /// a nested tunnel, and you want it to reset so that you can divert
  /// elsewhere using ChoosePathString(). Otherwise, after finishing
  /// the content you diverted to, it would continue where it left off.
  /// Calling this is equivalent to calling -> END in ink.
  /// </summary>
  void ForceEnd() {
    callStack.Reset();

    _currentFlow.currentChoices.clear();

    currentPointer = Pointer.Null;
    previousPointer = Pointer.Null;

    didSafeExit = true;
  }

  // Add the end of a function call, trim any whitespace from the end.
  // We always trim the start and end of the text that a function produces.
  // The start whitespace is discard as it is generated, and the end
  // whitespace is trimmed in one go here when we pop the function.
  void TrimWhitespaceFromFunctionEnd() {
    assert(callStack.currentElement.type == PushPopType.Function);

    var functionStartPoint =
        callStack.currentElement.functionStartInOuputStream;

    // If the start point has become -1, it means that some non-whitespace
    // text has been pushed, so it's safe to go as far back as we're able.
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
    // Add the end of a function call, trim any whitespace from the end.
    if (callStack.currentElement.type == PushPopType.Function) {
      TrimWhitespaceFromFunctionEnd();
    }

    callStack.Pop(popType);
  }

  // Don't make since the method need to be wrapped in Story for visit counting
  void SetChosenPath(Path path, bool incrementingTurnIndex) {
    // Changing direction, assume we need to clear current set of choices
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
    // Pass arguments onto the evaluation stack
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
                      : arguments[i].GetType().Name));
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

    // Do we have a returned value?
    // Potentially pop multiple values off the stack, in case we need
    // to clean up after ourselves (e.g. caller of EvaluateFunction may
    // have passed too many arguments, and we currently have no way to check for that)
    RuntimeObject? returnedObj;
    while (evaluationStack.length > originalEvaluationStackHeight) {
      var poppedObj = PopEvaluationStack();
      returnedObj ??= poppedObj;
    }

    // Finally, pop the external function evaluation
    PopCallstack(PushPopType.FunctionEvaluationFromGame);

    // What did we get back?
    if (returnedObj != null) {
      if (returnedObj is Void) {
        return null;
      }

      // Some kind of value, if not void
      var returnVal = returnedObj as Value;

      // DivertTargets get returned as the String of components
      // (rather than a Path, which isn't public)
      if (returnVal.valueType == ValueType.DivertTarget) {
        return returnVal.valueObject.ToString();
      }

      // Other types can just have their exact dynamic type:
      // int, float, String. VariablePointers get returned as Strings.
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

  // REMEMBER! REMEMBER! REMEMBER!
  // When adding state, update the Copy method and serialisation
  // REMEMBER! REMEMBER! REMEMBER!

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
