import 'call_stack.dart';
import 'choice.dart';
import 'json_serialisation.dart';
import 'runtime_object.dart';
import 'story.dart';

class Flow {
  String name;
  late final CallStack callStack;
  List<RuntimeObject> outputStream = [];
  List<Choice> currentChoices = [];

  Flow(this.name, Story story, [Map<String, dynamic>? jObject]) {
    callStack = CallStack.new1(story);

    if (jObject == null) return;

    callStack.setJsonToken(jObject["callstack"], story);
    outputStream = Json.JArrayToRuntimeObjList(jObject["outputStream"]);
    currentChoices =
        Json.JArrayToRuntimeObjList<Choice>(jObject["currentChoices"]);

    // choiceThreads is optional
    dynamic jChoiceThreadsObj = jObject["choiceThreads"];
    LoadFlowChoiceThreads(jChoiceThreadsObj, story);
  }

  dynamic writeJson() {
    var dict = <String, dynamic>{};

    dict["callstack"] = callStack.writeJson();
    dict["outputStream"] = Json.WriteListRuntimeObjs(outputStream);

    // choiceThreads: optional
    // Has to come BEFORE the choices themselves are written out
    // since the originalThreadIndex of each choice needs to be set
    bool hasChoiceThreads = false;
    for (Choice c in currentChoices) {
      c.originalThreadIndex = c.threadAtGeneration!.threadIndex;

      if (callStack.ThreadWithIndex(c.originalThreadIndex) == null) {
        if (!hasChoiceThreads) {
          hasChoiceThreads = true;
          dict["choiceThreads"] = <int, dynamic>{};
        }

        dict["choiceThreads"][c.originalThreadIndex] =
            c.threadAtGeneration?.writeJson();
      }
    }

    if (hasChoiceThreads) {}

    var lst = [];
    for (var c in currentChoices) {
      lst.add(Json.WriteChoice(c));
    }
    dict["currentChoices"] = lst;

    return dict;
  }

  // Used both to load old format and current
  void LoadFlowChoiceThreads(Map<String, dynamic> jChoiceThreads, Story story) {
    for (var choice in currentChoices) {
      var foundActiveThread =
          callStack.ThreadWithIndex(choice.originalThreadIndex);
      if (foundActiveThread != null) {
        choice.threadAtGeneration = foundActiveThread.copy();
      } else {
        Map<String, dynamic> jSavedChoiceThread =
            jChoiceThreads[choice.originalThreadIndex.toString()];
        choice.threadAtGeneration =
            CallStackThread.new1(jSavedChoiceThread, story);
      }
    }
  }
}
