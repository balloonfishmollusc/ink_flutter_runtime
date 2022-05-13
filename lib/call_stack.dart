import 'addons/extra.dart';
import 'json_serialisation.dart';
import 'path.dart';
import 'pointer.dart';
import 'push_pop.dart';
import 'runtime_object.dart';
import 'story.dart';

class CallStackElement {
  Pointer? currentPointer;

  bool inExpressionEvaluation = false;
  Map<String, RuntimeObject?> temporaryVariables = {};
  PushPopType type = PushPopType.Function;

  // When this callstack element is actually a function evaluation called from the game,
  // we need to keep track of the size of the evaluation stack when it was called
  // so that we know whether there was any return value.
  int evaluationStackHeightWhenPushed = 0;

  // When functions are called, we trim whitespace from the start and end of what
  // they generate, so we make sure know where the function's start and end are.
  int functionStartInOuputStream = 0;

  CallStackElement(this.type, this.currentPointer,
      [this.inExpressionEvaluation = false]);

  CallStackElement copy() {
    var copy = CallStackElement(type, currentPointer, inExpressionEvaluation);
    copy.temporaryVariables =
        Map<String, RuntimeObject?>.of(temporaryVariables);
    copy.evaluationStackHeightWhenPushed = evaluationStackHeightWhenPushed;
    copy.functionStartInOuputStream = functionStartInOuputStream;
    return copy;
  }
}

class CallStackThread {
  List<CallStackElement> callstack = [];
  int threadIndex = 0;
  Pointer? previousPointer;

  CallStackThread Copy() {
    var copy = CallStackThread.new0();
    copy.threadIndex = threadIndex;
    for (var e in callstack) {
      copy.callstack.add(e.copy());
    }
    copy.previousPointer = previousPointer;
    return copy;
  }

  CallStackThread.new0();

  CallStackThread.new1(Map<String, dynamic> jThreadObj, Story storyContext) {
    threadIndex = jThreadObj["threadIndex"] as int;

    List<dynamic> jThreadCallstack = jThreadObj["callstack"];
    for (var jElTok in jThreadCallstack) {
      var jElementObj = jElTok as Map<String, dynamic>;

      PushPopType pushPopType = jElementObj["type"] as PushPopType;

      Pointer pointer = Pointer.Null;

      String? currentContainerPathStr;
      dynamic currentContainerPathStrToken = jElementObj["cPath"];

      if (currentContainerPathStrToken != null) {
        currentContainerPathStr = currentContainerPathStrToken.toString();

        var threadPointerResult =
            storyContext.ContentAtPath(Path.new3(currentContainerPathStr));
        pointer.container = threadPointerResult.container;
        pointer.index = jElementObj["idx"] as int;

        if (threadPointerResult.obj == null) {
          throw Exception(
              "When loading state, internal story location couldn't be found: " +
                  currentContainerPathStr +
                  ". Has the story changed since this save data was created?");
        } else if (threadPointerResult.approximate) {
          storyContext.Warning(
              "When loading state, exact internal story location couldn't be found: '" +
                  currentContainerPathStr +
                  "', so it was approximated to '" +
                  pointer.container!.path.toString() +
                  "' to recover. Has the story changed since this save data was created?");
        }
      }

      bool inExpressionEvaluation = jElementObj["exp"] as bool;

      var el = CallStackElement(pushPopType, pointer, inExpressionEvaluation);

      dynamic temps = jElementObj["temp"];
      if (temps != null) {
        el.temporaryVariables = Json.JObjectToDictionaryRuntimeObjs(temps);
      } else {
        el.temporaryVariables.clear();
      }

      callstack.add(el);
    }

    dynamic prevContentObjPath = jThreadObj["previousContentObject"];
    if (prevContentObjPath != null) {
      var prevPath = Path.new3(prevContentObjPath as String);
      previousPointer = storyContext.PointerAtPath(prevPath);
    }
  }

  dynamic WriteJson() {
    var dict = <String, dynamic>{};
    dict["threadIndex"] = threadIndex;

    if (!previousPointer!.isNull) {
      dict["previousContentObject"] =
          previousPointer?.Resolve()?.path.toString();
    }

    var elements = [];
    for (CallStackElement el in callstack) {
      var item = <String, dynamic>{};

      if (!el.currentPointer!.isNull) {
        item["cPath"] = el.currentPointer!.container!.path.componentsString;
        item["idx"] = el.currentPointer!.index;
      }

      item["exp"] = el.inExpressionEvaluation;
      item["type"] = el.type as int;

      if (el.temporaryVariables.isNotEmpty) {
        item["temp"] = Json.WriteDictionaryRuntimeObjs(el.temporaryVariables);
      }

      elements.add(item);
    }

    dict["callstack"] = elements;
    return dict;
  }
}

class CallStack {
  List<CallStackElement> get elements => callStack;

  int get depth => elements.length;

  CallStackElement get currentElement {
    var thread = _threads[_threads.length - 1];
    var cs = thread.callstack;
    return cs[cs.length - 1];
  }

  int get currentElementIndex => callStack.length - 1;

  CallStackThread get currentThread => _threads[_threads.length - 1];

  set currentThread(CallStackThread value) {
    assert(_threads.length == 1,
        "Shouldn't be directly setting the current thread when we have a stack of them");
    _threads.clear();
    _threads.add(value);
  }

  bool get canPop => callStack.length > 1;

  CallStack._();

  static CallStack new1(Story storyContext) {
    var cs = CallStack._();
    cs._startOfRoot = Pointer.StartOf(storyContext.rootContentContainer!);
    cs.reset();
    return cs;
  }

  static CallStack new2(CallStack toCopy) {
    var cs = CallStack._();
    for (var otherThread in toCopy._threads) {
      cs._threads.add(otherThread.Copy());
    }
    cs._threadCounter = toCopy._threadCounter;
    cs._startOfRoot = toCopy._startOfRoot;
    return cs;
  }

  void reset() {
    _threads = <CallStackThread>[];
    _threads.add(CallStackThread.new0());

    _threads[0]
        .callstack
        .add(CallStackElement(PushPopType.Tunnel, _startOfRoot));
  }

  // Unfortunately it's not possible to implement jsonToken since
  // the setter needs to take a Story as a context in order to
  // look up objects from paths for currentContainer within elements.
  void SetJsonToken(Map<String, dynamic> jObject, Story storyContext) {
    _threads.clear();

    var jThreads = jObject["threads"] as List;

    for (dynamic jThreadTok in jThreads) {
      var jThreadObj = jThreadTok as Map<String, dynamic>;
      var thread = CallStackThread.new1(jThreadObj, storyContext);
      _threads.add(thread);
    }

    _threadCounter = jObject["threadCounter"] as int;
    _startOfRoot = Pointer.StartOf(storyContext.rootContentContainer!);
  }

  dynamic WriteJson() {
    List<dynamic> threads = [];
    for (CallStackThread thread in _threads) {
      threads.add(thread.WriteJson());
    }

    return <String, dynamic>{
      "threads": threads,
      "threadCounter": _threadCounter,
    };
  }

  void pushThread() {
    var newThread = currentThread.Copy();
    _threadCounter++;
    newThread.threadIndex = _threadCounter;
    _threads.add(newThread);
  }

  CallStackThread forkThread() {
    var forkedThread = currentThread.Copy();
    _threadCounter++;
    forkedThread.threadIndex = _threadCounter;
    return forkedThread;
  }

  void popThread() {
    if (canPopThread) {
      _threads.remove(currentThread);
    } else {
      throw Exception("Can't pop thread");
    }
  }

  bool get canPopThread => _threads.length > 1 && !elementIsEvaluateFromGame;

  bool get elementIsEvaluateFromGame {
    return currentElement.type == PushPopType.FunctionEvaluationFromGame;
  }

  void push(PushPopType type,
      {int externalEvaluationStackHeight = 0,
      int outputStreamLengthWithPushed = 0}) {
    // When pushing to callstack, maintain the current content path, but jump out of expressions by default
    var element = CallStackElement(type, currentElement.currentPointer, false);

    element.evaluationStackHeightWhenPushed = externalEvaluationStackHeight;
    element.functionStartInOuputStream = outputStreamLengthWithPushed;

    callStack.add(element);
  }

  bool canPopType([PushPopType? type]) {
    if (!canPop) return false;

    if (type == null) return true;

    return currentElement.type == type;
  }

  void pop([PushPopType? type]) {
    if (canPopType(type)) {
      callStack.removeAt(callStack.length - 1);
      return;
    } else {
      throw Exception("Mismatched push/pop in Callstack");
    }
  }

  // Get variable value, dereferencing a variable pointer if necessary
  RuntimeObject? getTemporaryVariableWithName(String name,
      [int contextIndex = -1]) {
    if (contextIndex == -1) contextIndex = currentElementIndex + 1;

    var contextElement = callStack[contextIndex - 1];

    RuntimeObject? varValue = contextElement.temporaryVariables[name];

    return varValue;
  }

  void setTemporaryVariable(String name, RuntimeObject value, bool declareNew,
      [int contextIndex = -1]) {
    if (contextIndex == -1) contextIndex = currentElementIndex + 1;

    var contextElement = callStack[contextIndex - 1];

    if (!declareNew && !contextElement.temporaryVariables.containsKey(name)) {
      throw Exception("Could not find temporary variable to set: " + name);
    }

    contextElement.temporaryVariables[name] = value;
  }

  // Find the most appropriate context for this variable.
  // Are we referencing a temporary or global variable?
  // Note that the compiler will have warned us about possible conflicts,
  // so anything that happens here should be safe!
  int contextForVariableNamed(String name) {
    // Current temporary context?
    // (Shouldn't attempt to access contexts higher in the callstack.)
    if (currentElement.temporaryVariables.containsKey(name)) {
      return currentElementIndex + 1;
    }

    // Global
    else {
      return 0;
    }
  }

  CallStackThread? ThreadWithIndex(int index) {
    var iterable = _threads.where((t) => t.threadIndex == index);
    if (iterable.isEmpty) return null;
    return iterable.first;
  }

  List<CallStackElement> get callStack {
    return currentThread.callstack;
  }

  String get callStackTrace {
    var sb = StringBuilder();

    for (int t = 0; t < _threads.length; t++) {
      var thread = _threads[t];
      var isCurrent = (t == _threads.length - 1);
      sb.add(
          '=== THREAD ${t + 1}/${_threads.length} ${isCurrent ? "(current) " : ""}===\n');

      for (int i = 0; i < thread.callstack.length; i++) {
        if (thread.callstack[i].type == PushPopType.Function) {
          sb.add("  [FUNCTION] ");
        } else {
          sb.add("  [TUNNEL] ");
        }

        var pointer = thread.callstack[i].currentPointer;
        if (!pointer!.isNull) {
          sb.add("<SOMEWHERE IN ");
          sb.add(pointer.container!.path.toString());
          sb.add(">\n");
        }
      }
    }

    return sb.toString();
  }

  List<CallStackThread> _threads = [];
  int _threadCounter = 0;
  Pointer? _startOfRoot;
}
