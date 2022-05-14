import 'dart:convert';
import 'dart:math';

import 'package:ink_flutter_runtime/choice_point.dart';
import 'package:ink_flutter_runtime/control_command.dart';
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
  /// <summary>
  /// The current version of the ink story file format.
  /// </summary>
  static const int inkVersionCurrent = 20;

  // Version numbers are for engine itself and story file, rather
  // than the story state save format
  //  -- old engine, format: always fail
  //  -- engine, old format: possibly cope, based on this number
  // When incrementing the version number above, the question you
  // should ask yourself is:
  //  -- Will the engine be able to load an old story file from
  //     before I made these changes to the engine?
  //     If possible, you should support it, though it's not as
  //     critical as loading old save games, since it's an
  //     in-development problem only.

  /// <summary>
  /// The minimum legacy version of ink that can be loaded by the current version of the code.
  /// </summary>
  static const int inkVersionMinimumCompatible = 18;

  /// <summary>
  /// The list of Choice dynamics available at the current point in
  /// the Story. This list will be populated as the Story is stepped
  /// through with the Continue() method. Once canContinue becomes
  /// false, this list will be populated, and is usually
  /// (but not always) on the final Continue() step.
  /// </summary>
  List<Choice> get currentChoices {
    // Don't include invisible choices for external usage.
    var choices = <Choice>[];
    for (var c in _state!.currentChoices) {
      if (!c.isInvisibleDefault) {
        c.index = choices.length;
        choices.add(c);
      }
    }
    return choices;
  }

  /// <summary>
  /// The latest line of text to be generated from a Continue() call.
  /// </summary>
  String get currentText => state.currentText!;

  /// <summary>
  /// Gets a list of tags as defined with '#' in source that were seen
  /// during the latest Continue() call.
  /// </summary>
  List<String> get currentTags => state.currentTags;

  /// <summary>
  /// Any errors generated during evaluation of the Story.
  /// </summary>
  List<String> get currentErrors => state.currentErrors;

  /// <summary>
  /// Any warnings generated during evaluation of the Story.
  /// </summary>
  List<String> get currentWarnings => state.currentWarnings;

  /// <summary>
  /// The current flow name if using multi-flow functionality - see SwitchFlow
  /// </summary>
  String get currentFlowName => state.currentFlowName;

  /// <summary>
  /// Is the default flow currently active? By definition, will also return true if not using multi-flow functionality - see SwitchFlow
  /// </summary>
  bool get currentFlowIsDefaultFlow => state.currentFlowIsDefaultFlow;

  /// <summary>
  /// Names of currently alive flows (not including the default flow)
  /// </summary>

  List<String> get aliveFlowNames => state.aliveFlowNames;

  /// <summary>
  /// Whether the currentErrors list contains any errors.
  /// THIS MAY BE REMOVED - you should be setting an error handler directly
  /// using Story.onError.
  /// </summary>
  bool get hasError => state.hasError;

  /// <summary>
  /// Whether the currentWarnings list contains any warnings.
  /// </summary>
  bool get hasWarning => state.hasWarning;

  /// <summary>
  /// The VariablesState dynamic contains all the global variables in the story.
  /// However, note that there's more to the state of a Story than just the
  /// global variables. This is a convenience accessor to the full state dynamic.
  /// </summary>
  VariablesState? get variablesState => state.variablesState;

  /// <summary>
  /// The entire current state of the story including (but not limited to):
  ///
  ///  * Global variables
  ///  * Temporary variables
  ///  * Read/visit and turn counts
  ///  * The callstack and evaluation stacks
  ///  * The current threads
  ///
  /// </summary>
  StoryState get state => _state!;

  /// <summary>
  /// Error handler for all runtime errors in ink - i.e. problems
  /// with the source ink itself that are only discovered when playing
  /// the story.
  /// It's strongly recommended that you assign an error handler to your
  /// story instance to avoid getting exceptions for ink errors.
  /// </summary>
  Event onError = Event(2);

  /// <summary>
  /// Callback for when ContinueInternal is complete
  /// </summary>
  Event onDidContinue = Event(0);

  /// <summary>
  /// Callback for when a choice is about to be executed
  /// </summary>
  //event Action<Choice> onMakeChoice;
  Event onMakeChoice = Event(1);

  /// <summary>
  /// Callback for when a function is about to be evaluated
  /// </summary>
  //event Action<String, dynamic[]> onEvaluateFunction;
  Event onEvaluateFunction = Event(2);

  /// <summary>
  /// Callback for when a function has been evaluated
  /// This is necessary because evaluating a function can cause continuing
  /// </summary>
  //event Action<String, dynamic[], String, dynamic> onCompleteEvaluateFunction;
  Event onCompleteEvaluateFunction = Event(3);

  /// <summary>
  /// Callback for when a path String is chosen
  /// </summary>
  //event Action<String, dynamic[]> onChoosePathString;
  Event onChoosePathString = Event(2);

  // Warning: When creating a Story using this constructor, you need to
  // call ResetState on it before use. Intended for compiler use only.
  // For normal use, use the constructor that takes a json String.
  Story.new1(this._mainContentContainer);

  /// <summary>
  /// Construct a Story dynamic using a JSON String compiled through inklecate.
  /// </summary>
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

  /// <summary>
  /// Reset the Story back to its initial state as it was when it was
  /// first constructed.
  /// </summary>
  void ResetState() {
    _state = StoryState(this);
    ResetGlobals();
  }

  void ResetErrors() {
    _state!.ResetErrors();
  }

  /// <summary>
  /// Unwinds the callstack. Useful to reset the Story's evaluation
  /// without actually changing any meaningful state, for example if
  /// you want to exit a section of story prematurely and tell it to
  /// go elsewhere with a call to ChoosePathString(...).
  /// Doing so without calling ResetCallstack() could cause unexpected
  /// issues if, for example, the Story was in a tunnel already.
  /// </summary>
  void ResetCallstack() {
    _state!.ForceEnd();
  }

  void ResetGlobals() {
    if (_mainContentContainer.namedContent.containsKey("global decl")) {
      var originalPointer = state.currentPointer;

      ChoosePath(Path.new3("global decl"), false);

      // Continue, but without validating external bindings,
      // since we may be doing this reset at initialisation time.
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

  /// <summary>
  /// Continue the story for one line of content, if possible.
  /// If you're not sure if there's more content available, for example if you
  /// want to check whether you're at a choice point or at the end of the story,
  /// you should call <c>canContinue</c> before calling this function.
  /// </summary>
  /// <returns>The line of text content.</returns>
  String Continue() {
    ContinueInternal();
    return currentText;
  }

  /// <summary>
  /// Check whether more content is available if you were to call <c>Continue()</c> - i.e.
  /// are we mid story rather than at a choice point or at the end.
  /// </summary>
  /// <value><c>true</c> if it's possible to call <c>Continue()</c>.</value>
  bool get canContinue {
    return state.canContinue;
  }

  void ContinueInternal() {
    //if( _profiler != null )
    //    _profiler.PreContinue();

    _recursiveContinueCount++;

    // Doing either:
    //  - full run through non-async (so not active and don't want to be)
    //  - Starting async run-through

    if (!canContinue) {
      throw Exception(
          "Can't continue - should check canContinue before calling Continue");
    }

    _state!.didSafeExit = false;
    _state!.ResetOutput();

    // It's possible for ink to call game to call ink to call game etc
    // In this case, we only want to batch observe variable changes
    // for the outermost call.
    if (_recursiveContinueCount == 1) {
      _state!.variablesState!.batchObservingVariableChanges = true;
    }

    bool outputStreamEndsInNewline = false;
    _sawLookaheadUnsafeFunctionAfterNewline = false;
    do {
      try {
        outputStreamEndsInNewline = ContinueSingleStep();
      } on StoryException catch (e) {
        AddError(e.message, e.useEndLineNumber);
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
    //
    // Successfully finished evaluation in time (or in error)
    if (outputStreamEndsInNewline || !canContinue) {
      // Need to rewind, due to evaluating further than we should?
      if (_stateSnapshotAtLastNewline != null) {
        RestoreStateSnapshot();
      }

      // Finished a section of content / reached a choice point?
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

    // Report any errors that occured during evaluation.
    // This may either have been StoryExceptions that were thrown
    // and caught during evaluation, or directly added with AddError.
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
      }

      // Throw an exception since there's no error handler
      else {
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

        // If you get this exception, please assign an error handler to your story.
        // If you're using Unity, you can do something like this when you create
        // your story:
        //
        // var story = Ink.Story(jsonTxt);
        // story.onError = (errorMessage, errorType) => {
        //     if( errorType == ErrorType.Warning )
        //         Debug.LogWarning(errorMessage);
        //     else
        //         Debug.LogError(errorMessage);
        // };
        //
        //
        throw StoryException(sb.toString());
      }
    }
  }

  bool ContinueSingleStep() {
    //if (_profiler != null)
    //    _profiler.PreStep ();

    // Run main step function (walks through content)
    Step();

    //if (_profiler != null)
    //    _profiler.PostStep ();

    // Run out of content and we have a default invisible choice that we can follow?
    if (!canContinue && !state.callStack.elementIsEvaluateFromGame) {
      TryFollowDefaultInvisibleChoice();
    }

    //if (_profiler != null)
    //    _profiler.PreSnapshot ();

    // Don't save/rewind during String evaluation, which is e.g. used for choices
    if (!state.inStringEvaluation) {
      // We previously found a newline, but were we just double checking that
      // it wouldn't immediately be removed by glue?
      if (_stateSnapshotAtLastNewline != null) {
        // Has proper text or a tag been added? Then we know that the newline
        // that was previously added is definitely the end of the line.
        var change = CalculateNewlineOutputStateChange(
            _stateSnapshotAtLastNewline!.currentText!,
            state.currentText!,
            _stateSnapshotAtLastNewline!.currentTags.length,
            state.currentTags.length);

        // The last time we saw a newline, it was definitely the end of the line, so we
        // want to rewind to that point.
        if (change == OutputStateChange.ExtendedBeyondNewline ||
            _sawLookaheadUnsafeFunctionAfterNewline) {
          RestoreStateSnapshot();

          // Hit a newline for sure, we're done
          return true;
        }

        // Newline that previously existed is no longer valid - e.g.
        // glue was encounted that caused it to be removed.
        else if (change == OutputStateChange.NewlineRemoved) {
          DiscardSnapshot();
        }
      }

      // Current content ends in a newline - approaching end of our evaluation
      if (state.outputStreamEndsInNewline) {
        // If we can continue evaluation for a bit:
        // Create a snapshot in case we need to rewind.
        // We're going to continue stepping in case we see glue or some
        // non-text content such as choices.
        if (canContinue) {
          // Don't bother to record the state beyond the current newline.
          // e.g.:
          // Hello world\n            // record state at the end of here
          // ~ complexCalculation()   // don't actually need this unless it generates text
          if (_stateSnapshotAtLastNewline == null) {
            StateSnapshot();
          }
        }

        // Can't continue, so we're about to exit - make sure we
        // don't have an old state hanging around.
        else {
          DiscardSnapshot();
        }
      }
    }

    //if (_profiler != null)
    //    _profiler.PostSnapshot ();

    // outputStreamEndsInNewline = false
    return false;
  }

  OutputStateChange CalculateNewlineOutputStateChange(
      String prevText, String currText, int prevTagCount, int currTagCount) {
    // Simple case: nothing's changed, and we still have a newline
    // at the end of the current content
    var newlineStillExists = currText.length >= prevText.length &&
        currText[prevText.length - 1] == '\n';
    if (prevTagCount == currTagCount &&
        prevText.length == currText.length &&
        newlineStillExists) {
      return OutputStateChange.NoChange;
    }

    // Old newline has been removed, it wasn't the end of the line after all
    if (!newlineStillExists) {
      return OutputStateChange.NewlineRemoved;
    }

    // Tag added - definitely the start of a line
    if (currTagCount > prevTagCount) {
      return OutputStateChange.ExtendedBeyondNewline;
    }

    // There must be content - check whether it's just whitespace
    for (int i = prevText.length; i < currText.length; i++) {
      var c = currText[i];
      if (c != ' ' && c != '\t') {
        return OutputStateChange.ExtendedBeyondNewline;
      }
    }

    // There's text but it's just spaces and tabs, so there's still the potential
    // for glue to kill the newline.
    return OutputStateChange.NoChange;
  }

  /// <summary>
  /// Continue the story until the next choice point or until it runs out of content.
  /// This is as opposed to the Continue() method which only evaluates one line of
  /// output at a time.
  /// </summary>
  /// <returns>The resulting text evaluated by the ink engine, concatenated together.</returns>
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

  // Maximum snapshot stack:
  //  - stateSnapshotDuringSave -- not retained, but returned to game code
  //  - _stateSnapshotAtLastNewline (has older patch)
  //  - _state (current, being patched)

  void StateSnapshot() {
    _stateSnapshotAtLastNewline = _state;
    _state = _state!.CopyAndStartPatching();
  }

  void RestoreStateSnapshot() {
    // Patched state had temporarily hijacked our
    // VariablesState and set its own callstack on it,
    // so we need to restore that.
    // If we're in the middle of saving, we may also
    // need to give the VariablesState the old patch.
    _stateSnapshotAtLastNewline!.RestoreAfterPatch();

    _state = _stateSnapshotAtLastNewline;
    _stateSnapshotAtLastNewline = null;

    // If save completed while the above snapshot was
    // active, we need to apply any changes made since
    // the save was started but before the snapshot was made.
    if (!_asyncSaving) {
      _state!.ApplyAnyPatch();
    }
  }

  void DiscardSnapshot() {
    // Normally we want to integrate the patch
    // into the main global/counts dictionaries.
    // However, if we're in the middle of async
    // saving, we simply stay in a "patching" state,
    // albeit with the newer cloned patch.
    if (!_asyncSaving) {
      _state!.ApplyAnyPatch();
    }

    // No longer need the snapshot.
    _stateSnapshotAtLastNewline = null;
  }

  /// <summary>
  /// Advanced usage!
  /// If you have a large story, and saving state to JSON takes too long for your
  /// framerate, you can temporarily freeze a copy of the state for saving on
  /// a separate thread. Internally, the engine maintains a "diff patch".
  /// When you've finished saving your state, call BackgroundSaveComplete()
  /// and that diff patch will be applied, allowing the story to continue
  /// in its usual mode.
  /// </summary>
  /// <returns>The state for background thread save.</returns>
  StoryState CopyStateForBackgroundThreadSave() {
    if (_asyncSaving) {
      throw Exception(
          "Story is already in background saving mode, can't call CopyStateForBackgroundThreadSave again!");
    }
    var stateToSave = _state;
    _state = _state!.CopyAndStartPatching();
    _asyncSaving = true;
    return stateToSave!;
  }

  /// <summary>
  /// See CopyStateForBackgroundThreadSave. This method releases the
  /// "frozen" save state, applying its patch that it was using internally.
  /// </summary>
  void BackgroundSaveComplete() {
    // CopyStateForBackgroundThreadSave must be called outside
    // of any async ink evaluation, since otherwise you'd be saving
    // during an intermediate state.
    // However, it's possible to *complete* the save in the middle of
    // a glue-lookahead when there's a state stored in _stateSnapshotAtLastNewline.
    // This state will have its own patch that is newer than the save patch.
    // We hold off on the final apply until the glue-lookahead is finished.
    // In that case, the apply is always done, it's just that it may
    // apply the looked-ahead changes OR it may simply apply the changes
    // made during the save process to the old _stateSnapshotAtLastNewline state.
    if (_stateSnapshotAtLastNewline == null) {
      _state!.ApplyAnyPatch();
    }

    _asyncSaving = false;
  }

  void Step() {
    bool shouldAddToStream = true;

    // Get current content
    var pointer = state.currentPointer;
    if (pointer.isNull) {
      return;
    }

    // Step directly to the first element of content in a container (if necessary)
    Container? containerToEnter = pointer.Resolve()?.csAs<Container>();
    while (containerToEnter != null) {
      // Mark container as being entered
      VisitContainer(containerToEnter, true);

      // No content? the most we can do is step past it
      if (containerToEnter.content.isEmpty) {
        break;
      }

      pointer = Pointer.StartOf(containerToEnter);
      containerToEnter = pointer.Resolve()?.csAs<Container>();
    }
    state.currentPointer = pointer;

    //if( _profiler != null ) {
    //	_profiler.Step(state.callStack);
    //}

    // Is the current content dynamic:
    //  - Normal content
    //  - Or a logic/flow statement - if so, do it
    // Stop flow if we hit a stack pop when we're unable to pop (e.g. return/done statement in knot
    // that was diverted to rather than called as a function)
    var currentContentObj = pointer.Resolve();
    bool isLogicOrFlowControl = PerformLogicAndFlowControl(currentContentObj!);

    // Has flow been forced to end by flow control above?
    if (state.currentPointer.isNull) {
      return;
    }

    if (isLogicOrFlowControl) {
      shouldAddToStream = false;
    }

    // Choice with condition?
    var choicePoint = currentContentObj.csAs<ChoicePoint>();
    if (choicePoint != null) {
      var choice = ProcessChoice(choicePoint);
      if (choice != null) {
        state.generatedChoices.add(choice);
      }

      currentContentObj = null;
      shouldAddToStream = false;
    }

    // If the container has no content, then it will be
    // the "content" itself, but we skip over it.
    if (currentContentObj is Container) {
      shouldAddToStream = false;
    }

    // Content to add to evaluation stack or the output stream
    if (shouldAddToStream) {
      // If we're pushing a variable pointer onto the evaluation stack, ensure that it's specific
      // to our current (possibly temporary) context index. And make a copy of the pointer
      // so that we're not editing the original runtime dynamic.
      var varPointer = currentContentObj?.csAs<VariablePointerValue>();
      if (varPointer != null && varPointer.contextIndex == -1) {
        // Create dynamic so we're not overwriting the story's own data
        var contextIdx =
            state.callStack.ContextForVariableNamed(varPointer.variableName);
        currentContentObj =
            VariablePointerValue(varPointer.variableName, contextIdx);
      }

      // Expression evaluation content
      if (state.inExpressionEvaluation) {
        state.PushEvaluationStack(currentContentObj!);
      }
      // Output stream content (i.e. not expression evaluation)
      else {
        state.PushToOutputStream(currentContentObj!);
      }
    }

    // Increment the content pointer, following diverts if necessary
    NextContent();

    // Starting a thread should be done after the increment to the content pointer,
    // so that when returning from the thread, it returns to the content after this instruction.
    var controlCmd = currentContentObj?.csAs<ControlCommand>();
    if (controlCmd != null &&
        controlCmd.commandType == CommandType.StartThread) {
      state.callStack.PushThread();
    }
  }

  // Mark a container as having been visited
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

    // Unless we're pointing *directly* at a piece of content, we don't do
    // counting here. Otherwise, the main stepping function will do the counting.
    if (pointer.isNull || pointer.index == -1) {
      return;
    }

    // First, find the previously open set of containers
    _prevContainers.clear();
    if (!previousPointer.isNull) {
      Container? prevAncestor = previousPointer.Resolve()?.csAs<Container>() ??
          previousPointer.container as Container;
      while (prevAncestor != null) {
        _prevContainers.add(prevAncestor);
        prevAncestor = prevAncestor.parent as Container;
      }
    }

    // If the dynamic is a container itself, it will be visited automatically at the next actual
    // content step. However, we need to walk up the ancestry to see if there are more containers
    RuntimeObject? currentChildOfContainer = pointer.Resolve();

    // Invalid pointer? May happen if attemptingto
    if (currentChildOfContainer == null) return;

    Container? currentContainerAncestor =
        currentChildOfContainer.parent?.csAs<Container>();

    bool allChildrenEnteredAtStart = true;
    while (currentContainerAncestor != null &&
        (!_prevContainers.contains(currentContainerAncestor) ||
            currentContainerAncestor.countingAtStartOnly)) {
      // Check whether this ancestor container is being entered at the start,
      // by checking whether the child dynamic is the first.
      bool enteringAtStart = currentContainerAncestor.content.isNotEmpty &&
          currentChildOfContainer == currentContainerAncestor.content[0] &&
          allChildrenEnteredAtStart;

      // Don't count it as entering at start if we're entering random somewhere within
      // a container B that happens to be nested at index 0 of container A. It only counts
      // if we're diverting directly to the first leaf node.
      if (!enteringAtStart) {
        allChildrenEnteredAtStart = false;
      }

      // Mark a visit to this container
      VisitContainer(currentContainerAncestor, enteringAtStart);

      currentChildOfContainer = currentContainerAncestor;
      currentContainerAncestor = currentContainerAncestor.parent as Container;
    }
  }

  Choice? ProcessChoice(ChoicePoint choicePoint) {
    bool showChoice = true;

    // Don't create choice if choice point doesn't pass conditional
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

    // Don't create choice if player has already read this content
    if (choicePoint.onceOnly) {
      var visitCount = state.VisitCountForContainer(choicePoint.choiceTarget!);
      if (visitCount > 0) {
        showChoice = false;
      }
    }

    // We go through the full process of creating the choice above so
    // that we consume the content for it, since otherwise it'll
    // be shown on the output stream.
    if (!showChoice) {
      return null;
    }

    var choice = Choice();
    choice.targetPath = choicePoint.pathOnChoice;
    choice.sourcePath = choicePoint.path.toString();
    choice.isInvisibleDefault = choicePoint.isInvisibleDefault;

    // We need to capture the state of the callstack at the point where
    // the choice was generated, since after the generation of this choice
    // we may go on to pop out from a tunnel (possible if the choice was
    // wrapped in a conditional), or we may pop out from a thread,
    // at which point that thread is discarded.
    // Fork clones the thread, gives it a ID, but without affecting
    // the thread stack itself.
    choice.threadAtGeneration = state.callStack.ForkThread();

    // Set final text for the choice
    choice.text = (startText + choiceOnlyText).trim();

    return choice;
  }

  // Does the expression result represented by this dynamic evaluate to true?
  // e.g. is it a Number that's not equal to 1?
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

  /// <summary>
  /// Checks whether contentObj is a control or flow dynamic rather than a piece of content,
  /// and performs the required command if necessary.
  /// </summary>
  /// <returns><c>true</c> if dynamic was logic or flow control, <c>false</c> if it's normal content.</returns>
  /// <param name="contentObj">Content dynamic.</param>
  bool PerformLogicAndFlowControl(RuntimeObject? contentObj) {
    if (contentObj == null) {
      return false;
    }

    // Divert
    if (contentObj is Divert) {
      Divert currentDivert = contentObj;

      if (currentDivert.isConditional) {
        var conditionValue = state.PopEvaluationStack();

        // False conditional? Cancel divert
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
        // Human readable name available - runtime divert is part of a hard-written divert that to missing content
        if (currentDivert.debugMetadata?.sourceName != null) {
          Error("Divert target doesn't exist: " +
              currentDivert.debugMetadata!.sourceName!);
        } else {
          Error("Divert resolution failed: " + currentDivert.toString());
        }
      }

      return true;
    }

    // Start/end an expression evaluation? Or print out the result?
    else if (contentObj is ControlCommand) {
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

          // If the expression turned out to be empty, there may not be anything on the stack
          if (state.evaluationStack.isNotEmpty) {
            var output = state.PopEvaluationStack();

            // Functions may evaluate to Void, in which case we skip output
            if (output is! Void) {
              // TODO: Should we really always blanket convert to String?
              // It would be okay to have numbers in the output stream the
              // only problem is when exporting text for viewing, it skips over numbers etc.
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

          // Tunnel onwards is allowed to specify an optional override
          // divert to go to immediately after returning: ->-> target
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

            // Does tunnel onwards override by diverting to a ->-> target?
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

          // Since we're iterating backward through the content,
          // build a stack so that when we build the String,
          // it's in the right order
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

          // Consume the content that was produced for this String
          state.PopFromOutputStream(outputCountConsumed);

          // Build String out of the content we collected
          var sb = StringBuilder();

          for (var c in contentStackForString) {
            sb.add(c.toString());
          }

          // Return to expression evaluation (from content mode)
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
            } // visit count, assume 0 to default to allowing entry

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

            // +1 because it's inclusive of min and max, for e.g. RANDOM(1,6) for a dice roll.
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

            // Next random number (rather than keeping the Random dynamic around)
            state.previousRandom = nextRandom;
            break;
          }

        case CommandType.SeedRandom:
          var seed = state.PopEvaluationStack().csAs<IntValue>();
          if (seed == null) {
            Error("Invalid value passed to SEED_RANDOM");
          }

          // Story seed affects both RANDOM and shuffle behaviour
          state.storySeed = seed!.value;
          state.previousRandom = 0;

          // SEED_RANDOM returns nothing.
          state.PushEvaluationStack(Void());
          break;

        case CommandType.VisitIndex:
          var count =
              state.VisitCountForContainer(state.currentPointer.container!) -
                  1; // index not count
          state.PushEvaluationStack(IntValue(count));
          break;

        case CommandType.SequenceShuffleIndex:
          var shuffleIndex = NextSequenceShuffleIndex();
          state.PushEvaluationStack(IntValue(shuffleIndex));
          break;

        case CommandType.StartThread:
          // Handled in main step function
          break;

        case CommandType.Done:

          // We may exist in the context of the initial
          // act of creating the thread, or in the context of
          // evaluating the content.
          if (state.callStack.canPopThread) {
            state.callStack.PopThread();
          }

          // In normal flow - allow safe exit without warning
          else {
            state.didSafeExit = true;

            // Stop flow in current thread
            state.currentPointer = Pointer.Null;
          }

          break;

        // Force flow to end completely
        case CommandType.End:
          state.ForceEnd();
          break;
        default:
          Error("unhandled ControlCommand: $evalCommand");
          break;
      }

      return true;
    }

    // Variable assignment
    else if (contentObj is VariableAssignment) {
      var varAss = contentObj;
      var assignedVal = state.PopEvaluationStack();

      // When in temporary evaluation, don't create variables purely within
      // the temporary context, but attempt to create them globally
      //var prioritiseHigherInCallStack = _temporaryEvaluationContainer != null;

      state.variablesState!.Assign(varAss, assignedVal);

      return true;
    }

    // Variable reference
    else if (contentObj is VariableReference) {
      var varRef = contentObj;
      RuntimeObject? foundValue;

      // Explicit read count value
      if (varRef.pathForCount != null) {
        var container = varRef.containerForCount;
        int count = state.VisitCountForContainer(container!);
        foundValue = IntValue(count);
      }

      // Normal variable reference
      else {
        foundValue = state.variablesState!.GetVariableWithName(varRef.name!);

        if (foundValue == null) {
          Warning(
              "Variable not found: '${varRef.name}'. Using default value of 0 (false). This can happen with temporary variables if the declaration hasn't yet been hit. Globals are always given a default value on load if a value doesn't exist in the save state.");
          foundValue = IntValue(0);
        }
      }

      state.PushEvaluationStack(foundValue);

      return true;
    }

    // Native function call
    else if (contentObj is NativeFunctionCall) {
      var func = contentObj;
      var funcParams = state.PopEvaluationStackMulti(func.numberOfParameters);
      var result = func.Call(funcParams);
      state.PushEvaluationStack(result!);
      return true;
    }

    // No control content, must be ordinary content
    return false;
  }

  /// <summary>
  /// Change the current position of the story to the given path. From here you can
  /// call Continue() to evaluate the next line.
  ///
  /// The path String is a dot-separated path as used internally by the engine.
  /// These examples should work:
  ///
  ///    myKnot
  ///    myKnot.myStitch
  ///
  /// Note however that this won't necessarily work:
  ///
  ///    myKnot.myStitch.myLabelledChoice
  ///
  /// ...because of the way that content is nested within a weave structure.
  ///
  /// By default this will reset the callstack beforehand, which means that any
  /// tunnels, threads or functions you were in at the time of calling will be
  /// discarded. This is different from the behaviour of ChooseChoiceIndex, which
  /// will always keep the callstack, since the choices are known to come from the
  /// correct state, and known their source thread.
  ///
  /// You have the option of passing false to the resetCallstack parameter if you
  /// don't want this behaviour, and will leave any active threads, tunnels or
  /// function calls in-tact.
  ///
  /// This is potentially dangerous! If you're in the middle of a tunnel,
  /// it'll redirect only the inner-most tunnel, meaning that when you tunnel-return
  /// using '->->', it'll return to where you were before. This may be what you
  /// want though. However, if you're in the middle of a function, ChoosePathString
  /// will throw an exception.
  ///
  /// </summary>
  /// <param name="path">A dot-separted path String, as specified above.</param>
  /// <param name="resetCallstack">Whether to reset the callstack first (see summary description).</param>
  /// <param name="arguments">Optional set of arguments to pass, if path is to a knot that takes them.</param>
  void ChoosePathString(String path,
      [bool resetCallstack = true, List? arguments]) {
    onChoosePathString.fire([path, arguments]);
    if (resetCallstack) {
      ResetCallstack();
    } else {
      // ChoosePathString is potentially dangerous since you can call it when the stack is
      // pretty much in any state. Let's catch one of the worst offenders.
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

    // Take a note of newly visited containers for read counts etc
    VisitChangedContainersDueToDivert();
  }

  /// <summary>
  /// Chooses the Choice from the currentChoices list with the given
  /// index. Internally, this sets the current content path to that
  /// pointed to by the Choice, ready to continue story evaluation.
  /// </summary>
  void ChooseChoiceIndex(int choiceIdx) {
    var choices = currentChoices;
    Assert(choiceIdx >= 0 && choiceIdx < choices.length, "choice out of range");

    // Replace callstack with the one from the thread at the choosing point,
    // so that we can jump into the right place in the flow.
    // This is important in case the flow was forked by a thread, which
    // can create multiple leading edges for the story, each of
    // which has its own context.
    var choiceToChoose = choices[choiceIdx];
    onMakeChoice.fire([choiceToChoose]);
    state.callStack.currentThread = choiceToChoose.threadAtGeneration!;

    ChoosePath(choiceToChoose.targetPath!);
  }

  /// <summary>
  /// Checks if a function exists.
  /// </summary>
  /// <returns>True if the function exists, else false.</returns>
  /// <param name="functionName">The name of the function as declared in ink.</param>
  bool HasFunction(String functionName) {
    try {
      return KnotContainerWithName(functionName) != null;
    } catch (_) {
      return false;
    }
  }

  /// <summary>
  /// Evaluates a function defined in ink.
  /// </summary>
  /// <returns>The return value as returned from the ink function with `~ return myValue`, or null if nothing is returned.</returns>
  /// <param name="functionName">The name of the function as declared in ink.</param>
  /// <param name="arguments">The arguments that the ink function takes, if any. Note that we don't (can't) do any validation on the number of arguments right now, so make sure you get it right!</param>
  dynamic EvaluateFunction(String functionName, [List? arguments]) {
    var dict = EvaluateFunction(functionName, arguments);
    return dict['return_value'];
  }

  /// <summary>
  /// Evaluates a function defined in ink, and gathers the possibly multi-line text as generated by the function.
  /// This text output is any text written as normal content within the function, as opposed to the return value, as returned with `~ return`.
  /// </summary>
  /// <returns>The return value as returned from the ink function with `~ return myValue`, or null if nothing is returned.</returns>
  /// <param name="functionName">The name of the function as declared in ink.</param>
  /// <param name="textOutput">The text content produced by the function via normal ink, if any.</param>
  /// <param name="arguments">The arguments that the ink function takes, if any. Note that we don't (can't) do any validation on the number of arguments right now, so make sure you get it right!</param>
  Map<String, dynamic> EvaluateFunctionWithTextOutput(String functionName,
      [List? arguments]) {
    onEvaluateFunction.fire([functionName, arguments]);

    if (functionName.isEmpty || functionName.trim().isEmpty) {
      throw Exception("Function is empty or white space.");
    }

    // Get the content that we need to run
    var funcContainer = KnotContainerWithName(functionName);
    if (funcContainer == null) {
      throw Exception("Function doesn't exist: '" + functionName + "'");
    }

    // Snapshot the output stream
    var outputStreamBefore = List<RuntimeObject>.of(state.outputStream);
    _state!.ResetOutput();

    // State will temporarily replace the callstack in order to evaluate
    state.StartFunctionEvaluationFromGame(funcContainer, arguments);

    // Evaluate the function, and collect the String output
    var stringOutput = StringBuilder();
    while (canContinue) {
      stringOutput.add(Continue());
    }

    var ret = <String, dynamic>{};
    ret['text_output'] = stringOutput.toString();

    // Restore the output stream in case this was called
    // during main story evaluation.
    _state!.ResetOutput(outputStreamBefore);

    // Finish evaluation, and see whether anything was produced
    var result = state.CompleteFunctionEvaluationFromGame();
    onCompleteEvaluateFunction
        .fire([functionName, arguments, ret['text_output'], result]);
    ret['return_value'] = result;
    return ret;
  }

  // Evaluate a "hot compiled" piece of ink content, as used by the REPL-like
  // CommandLinePlayer.
  RuntimeObject? EvaluateExpression(Container exprContainer) {
    int startCallStackHeight = state.callStack.elements.length;

    state.callStack.Push(PushPopType.Tunnel);

    _temporaryEvaluationContainer = exprContainer;

    state.GoToStart();

    int evalStackHeight = state.evaluationStack.length;

    Continue();

    _temporaryEvaluationContainer = null;

    // Should have fallen off the end of the Container, which should
    // have auto-popped, but just in case we didn't for some reason,
    // manually pop to restore the state (including currentPath).
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

  /// <summary>
  /// An ink file can provide a fallback functions for when when an EXTERNAL has been left
  /// unbound by the client, and the fallback function will be called instead. Useful when
  /// testing a story in playmode, when it's not possible to write a client-side C# external
  /// function, but you don't want it to fail to run.
  /// </summary>
  bool allowExternalFunctionFallbacks = false;

  void CallExternalFunction(String funcName, int numberOfArguments) {
    ExternalFunctionDef? funcDef = _externals[funcName];
    Container? fallbackFunctionContainer;

    var foundExternal = funcDef != null;

    // Should this function break glue? Abort run if we've already seen a newline.
    // Set a bool to tell it to restore the snapshot at the end of this instruction.
    if (foundExternal &&
        !funcDef.lookaheadSafe &&
        _stateSnapshotAtLastNewline != null) {
      _sawLookaheadUnsafeFunctionAfterNewline = true;
      return;
    }

    // Try to use fallback function?
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

    // Pop arguments
    var arguments = [];
    for (int i = 0; i < numberOfArguments; ++i) {
      var poppedObj = state.PopEvaluationStack() as Value;
      var valueObj = poppedObj.valueObject;
      arguments.add(valueObj);
    }

    // Reverse arguments from the order they were popped,
    // so they're the right way round again.
    arguments = arguments.reversed.toList();

    // Run the function!
    dynamic funcResult = funcDef!.function(arguments);

    // Convert return value (if any) to the a type that the ink engine can use
    RuntimeObject? returnObj;
    if (funcResult != null) {
      returnObj = Value.Create(funcResult);
    } else {
      returnObj = Void();
    }

    state.PushEvaluationStack(returnObj);
  }

  /// <summary>
  /// Most general form of function binding that returns an dynamic
  /// and takes an array of dynamic parameters.
  /// The only way to bind a function with more than 3 arguments.
  /// </summary>
  /// <param name="funcName">EXTERNAL ink function name to bind to.</param>
  /// <param name="func">The C# function to bind.</param>
  /// <param name="lookaheadSafe">The ink engine often evaluates further
  /// than you might expect beyond the current line just in case it sees
  /// glue that will cause the two lines to become one. In this case it's
  /// possible that a function can appear to be called twice instead of
  /// just once, and earlier than you expect. If it's safe for your
  /// function to be called in this way (since the result and side effect
  /// of the function will not change), then you can pass 'true'.
  /// Usually, you want to pass 'false', especially if you want some action
  /// to be performed in game code when this function is called.</param>
  void BindExternalFunctionGeneral(String funcName, ExternalFunction func,
      [bool lookaheadSafe = false]) {
    Assert(!_externals.containsKey(funcName),
        "Function '" + funcName + "' has already been bound.");
    _externals[funcName] =
        ExternalFunctionDef(function: func, lookaheadSafe: lookaheadSafe);
  }

  /// <summary>
  /// Remove a binding for a named EXTERNAL ink function.
  /// </summary>
  void UnbindExternalFunction(String funcName) {
    Assert(_externals.containsKey(funcName),
        "Function '" + funcName + "' has not been bound.");
    _externals.remove(funcName);
  }

  void VariableStateDidChangeEvent(
      String variableName, RuntimeObject newValueObj) {}

  /// <summary>
  /// Get any global tags associated with the story. These are defined as
  /// hash tags defined at the very top of the story.
  /// </summary>
  List<String> get globalTags => TagsAtStartOfFlowContainerWithPathString("");

  /// <summary>
  /// Gets any tags associated with a particular knot or knot.stitch.
  /// These are defined as hash tags defined at the very top of a
  /// knot or stitch.
  /// </summary>
  /// <param name="path">The path of the knot or stitch, in the form "knot" or "knot.stitch".</param>
  List<String> TagsForContentAtPath(String path) {
    return TagsAtStartOfFlowContainerWithPathString(path);
  }

  List<String> TagsAtStartOfFlowContainerWithPathString(String pathString) {
    var path = Path.new3(pathString);

    // Expected to be global story, knot or stitch
    var flowContainer = ContentAtPath(path).container;
    while (true) {
      var firstContent = flowContainer?.content[0];
      if (firstContent is Container) {
        flowContainer = firstContent;
      } else {
        break;
      }
    }

    // Any initial tag dynamics count as the "main tags" associated with that story/knot/stitch
    List<String>? tags;
    for (var c in flowContainer!.content) {
      var tag = c.csAs<Tag>();
      if (tag != null) {
        tags ??= <String>[];
        tags.add(tag.text);
      } else {
        break;
      }
    }

    return tags!;
  }

  void NextContent() {
    // Setting previousContentObject is critical for VisitChangedContainersDueToDivert
    state.previousPointer = state.currentPointer;

    // Divert step?
    if (!state.divertedPointer.isNull) {
      state.currentPointer = state.divertedPointer;
      state.divertedPointer = Pointer.Null;

      // Internally uses state.previousContentObject and state.currentContentObject
      VisitChangedContainersDueToDivert();

      // Diverted location has valid content?
      if (!state.currentPointer.isNull) {
        return;
      }

      // Otherwise, if diverted location doesn't have valid content,
      // drop down and attempt to increment.
      // This can happen if the diverted path is intentionally jumping
      // to the end of a container - e.g. a Conditional that's re-joining
    }

    bool successfulPointerIncrement = IncrementContentPointer();

    // Ran out of content? Try to auto-exit from a function,
    // or finish evaluating the content of a thread
    if (!successfulPointerIncrement) {
      bool didPop = false;

      if (state.callStack.CanPop(PushPopType.Function)) {
        // Pop from the call stack
        state.PopCallstack(PushPopType.Function);

        // This pop was due to dropping off the end of a function that didn't return anything,
        // so in this case, we make sure that the evaluator has something to chomp on if it needs it
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
    pointer.index++;

    // Each time we step off the end, we fall out to the next container, all the
    // while we're in indexed rather than named content
    while (pointer.index >= pointer.container!.content.length) {
      successfulIncrement = false;

      Container? nextAncestor = pointer.container?.parent?.csAs<Container>();
      if (nextAncestor == null) {
        break;
      }

      var indexInAncestor = nextAncestor.content.indexOf(pointer.container!);
      if (indexInAncestor == -1) {
        break;
      }

      pointer = Pointer(container: nextAncestor, index: indexInAncestor);

      // Increment to next content in outer container
      pointer.index++;

      successfulIncrement = true;
    }

    if (!successfulIncrement) pointer = Pointer.Null;

    state.callStack.currentElement.currentPointer = pointer;

    return successfulIncrement;
  }

  bool TryFollowDefaultInvisibleChoice() {
    var allChoices = _state!.currentChoices;

    // Is a default invisible choice the ONLY choice?
    var invisibleChoices =
        allChoices.where((c) => c.isInvisibleDefault).toList();
    if (invisibleChoices.isEmpty ||
        allChoices.length > invisibleChoices.length) {
      return false;
    }

    var choice = invisibleChoices[0];

    // Invisible choice may have been generated on a different thread,
    // in which case we need to restore it before we continue
    state.callStack.currentThread = choice.threadAtGeneration!;

    // If there's a chance that this state will be rolled back to before
    // the invisible choice then make sure that the choice thread is
    // left intact, and it isn't re-entered in an old state.
    if (_stateSnapshotAtLastNewline != null) {
      state.callStack.currentThread = state.callStack.ForkThread();
    }

    ChoosePath(choice.targetPath!, false);

    return true;
  }

  // Note that this is O(n), since it re-evaluates the shuffle indices
  // from a consistent seed each time.
  // TODO: Is this the best algorithm it can be?
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

    // Generate the same shuffle based on:
    //  - The hash of this container, to make sure it's consistent
    //    each time the runtime returns to the sequence
    //  - How many times the runtime has looped around this full shuffle
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

  // Throw an exception that gets caught and causes AddError to be called,
  // then exits the flow.
  void Error(String message, [bool useEndLineNumber = false]) {
    var e = StoryException(message);
    e.useEndLineNumber = useEndLineNumber;
    throw e;
  }

  void Warning(String message) {
    AddError(message, true);
  }

  void AddError(String message,
      [bool isWarning = false, bool useEndLineNumber = false]) {
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

    // In a broken state don't need to know about any other errors.
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

    // Try to get from the current path first
    var pointer = state.currentPointer;
    if (!pointer.isNull) {
      dm = pointer.Resolve()!.debugMetadata;
      if (dm != null) {
        return dm;
      }
    }

    // Move up callstack if possible
    for (int i = state.callStack.elements.length - 1; i >= 0; --i) {
      pointer = state.callStack.elements[i].currentPointer;
      if (!pointer.isNull && pointer.Resolve() != null) {
        dm = pointer.Resolve()!.debugMetadata;
        if (dm != null) {
          return dm;
        }
      }
    }

    // Current/previous path may not be valid if we've just had an error,
    // or if we've simply run out of content.
    // As a last resort, try to grab something from the output stream
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

// Assumption: prevText is the snapshot where we saw a newline, and we're checking whether we're really done
//             with that line. Therefore prevText will definitely end in a newline.
//
// We take tags into account too, so that a tag following a content line:
//   Content
//   # tag
// ... doesn't cause the tag to be wrongly associated with the content above.
enum OutputStateChange { NoChange, ExtendedBeyondNewline, NewlineRemoved }

class ExternalFunctionDef extends Struct {
  ExternalFunction function;
  bool lookaheadSafe;

  @override
  Struct clone() {
    return ExternalFunctionDef(
        function: function, lookaheadSafe: lookaheadSafe);
  }

  ExternalFunctionDef({required this.function, this.lookaheadSafe = false});
}

/// <summary>
/// General purpose delegate definition for bound EXTERNAL function definitions
/// from ink. Note that this version isn't necessary if you have a function
/// with three arguments or less - see the overloads of BindExternalFunction.
/// </summary>
typedef ExternalFunction = dynamic Function(List args);

/// <summary>
/// Delegate definition for variable observation - see ObserveVariable.
/// </summary>
typedef VariableObserver = void Function(String variableName, dynamic newValue);
