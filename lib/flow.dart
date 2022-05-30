// reviewed

import 'call_stack.dart';
import 'choice.dart';
import 'json_serialisation.dart';
import 'runtime_object.dart';
import 'story.dart';

class Flow {
  String name;
  late CallStack callStack;
  List<RuntimeObject> outputStream = [];
  List<Choice> currentChoices = [];

  Flow(this.name, Story story, [Map<String, dynamic>? jObject]) {
    callStack = CallStack.new1(story);

    if (jObject == null) return;

    callStack.SetJsonToken(jObject["callstack"], story);
    outputStream = Json.JArrayToRuntimeObjList(jObject["outputStream"]);
    currentChoices =
        Json.JArrayToRuntimeObjList<Choice>(jObject["currentChoices"]);

    Map<String, dynamic> jChoiceThreadsObj = jObject["choiceThreads"];
    LoadFlowChoiceThreads(jChoiceThreadsObj, story);
  }

  dynamic WriteJson() {
    var dict = <String, dynamic>{};

    dict["callstack"] = callStack.WriteJson();
    dict["outputStream"] = Json.WriteListRuntimeObjs(outputStream);

    bool hasChoiceThreads = false;
    for (Choice c in currentChoices) {
      c.originalThreadIndex = c.threadAtGeneration!.threadIndex;

      if (callStack.ThreadWithIndex(c.originalThreadIndex) == null) {
        if (!hasChoiceThreads) {
          hasChoiceThreads = true;
          dict["choiceThreads"] = <String, dynamic>{};
        }

        dict["choiceThreads"][c.originalThreadIndex.toString()] =
            c.threadAtGeneration!.WriteJson();
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
        choice.threadAtGeneration = foundActiveThread.Copy();
      } else {
        Map<String, dynamic> jSavedChoiceThread =
            jChoiceThreads[choice.originalThreadIndex.toString()];
        choice.threadAtGeneration =
            CallStackThread.new1(jSavedChoiceThread, story);
      }
    }
  }
}
