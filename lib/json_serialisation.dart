// reviewed

import 'path.dart';
import 'void.dart';
import 'divert.dart';
import 'addons/extra.dart';
import 'choice.dart';
import 'choice_point.dart';
import 'container.dart';
import 'glue.dart';
import 'native_function_call.dart';
import 'push_pop.dart';
import 'runtime_object.dart';
import 'control_command.dart';
import 'tag.dart';
import 'value.dart';
import 'variable_assignment.dart';
import 'variable_reference.dart';

class Json {
  static List<T> JArrayToRuntimeObjList<T extends RuntimeObject>(
      List<dynamic> jArray,
      [bool skipLast = false]) {
    int count = jArray.length;
    if (skipLast) count--;

    var list = <T>[];

    for (int i = 0; i < count; i++) {
      var jTok = jArray[i];
      var runtimeObj = JTokenToRuntimeObject(jTok) as T;
      list.add(runtimeObj);
    }

    return list;
  }

  static Map<String, dynamic> WriteDictionaryRuntimeObjs(
      Map<String, RuntimeObject> dictionary) {
    var dict = <String, dynamic>{};
    for (var keyVal in dictionary.entries) {
      dict[keyVal.key] = WriteRuntimeObject(keyVal.value);
    }
    return dict;
  }

  static List WriteListRuntimeObjs(List<RuntimeObject> list) {
    List<dynamic> ret = [];
    for (var val in list) {
      ret.add(WriteRuntimeObject(val));
    }
    return ret;
  }

  static Map<String, int> WriteIntDictionary(Map<String, int> dict) {
    return dict;
  }

  static dynamic WriteRuntimeObject(RuntimeObject obj) {
    var container = obj.csAs<Container>();
    if (container != null) {
      return WriteRuntimeContainer(container);
    }

    var divert = obj.csAs<Divert>();
    if (divert != null) {
      String divTypeKey = "->";
      if (divert.isExternal) {
        divTypeKey = "x()";
      } else if (divert.pushesToStack) {
        if (divert.stackPushType == PushPopType.Function) {
          divTypeKey = "f()";
        } else if (divert.stackPushType == PushPopType.Tunnel) {
          divTypeKey = "->t->";
        }
      }

      String? targetStr;
      if (divert.hasVariableTarget) {
        targetStr = divert.variableDivertName;
      } else {
        targetStr = divert.targetPathString;
      }

      var dict = <String, dynamic>{};
      dict[divTypeKey] = targetStr;

      if (divert.hasVariableTarget) dict["var"] = true;

      if (divert.isConditional) dict["c"] = true;

      if (divert.externalArgs > 0) dict["exArgs"] = divert.externalArgs;

      return dict;
    }

    var choicePoint = obj.csAs<ChoicePoint>();
    if (choicePoint != null) {
      var dict = <String, dynamic>{};
      dict["*"] = choicePoint.pathStringOnChoice;
      dict["flg"] = choicePoint.flags;
      return dict;
    }

    var boolVal = obj.csAs<BoolValue>();
    if (boolVal != null) {
      return boolVal.value;
    }

    var intVal = obj.csAs<IntValue>();
    if (intVal != null) {
      return intVal.value;
    }

    var floatVal = obj.csAs<FloatValue>();
    if (floatVal != null) {
      return floatVal.value;
    }

    var strVal = obj.csAs<StringValue>();
    if (strVal != null) {
      if (strVal.isNewline) {
        return "\n";
      } else {
        return "^" + strVal.value;
      }
    }

    var divTargetVal = obj.csAs<DivertTargetValue>();
    if (divTargetVal != null) {
      var dict = <String, dynamic>{};
      dict["^->"] = divTargetVal.value!.componentsString;
      return dict;
    }

    var varPtrVal = obj.csAs<VariablePointerValue>();
    if (varPtrVal != null) {
      var dict = <String, dynamic>{};
      dict["^var"] = varPtrVal.value;
      dict["ci"] = varPtrVal.contextIndex;
      return dict;
    }

    var glue = obj.csAs<Glue>();
    if (glue != null) {
      return "<>";
    }

    var controlCmd = obj.csAs<ControlCommand>();
    if (controlCmd != null) {
      return _controlCommandNames[controlCmd.commandType];
    }

    var nativeFunc = obj.csAs<NativeFunctionCall>();
    if (nativeFunc != null) {
      var name = nativeFunc.name;

      // Avoid collision with ^ used to indicate a string
      if (name == "^") name = "L^";

      return name;
    }

    // Variable reference
    var varRef = obj.csAs<VariableReference>();
    if (varRef != null) {
      var dict = <String, dynamic>{};

      String? readCountPath = varRef.pathStringForCount;
      if (readCountPath != null) {
        dict["CNT?"] = readCountPath;
      } else {
        dict["VAR?"] = varRef.name;
      }
      return dict;
    }

    // Variable assignment
    var varAss = obj.csAs<VariableAssignment>();
    if (varAss != null) {
      var dict = <String, dynamic>{};

      String key = varAss.isGlobal ? "VAR=" : "temp=";
      dict[key] = varAss.variableName;

      // Reassignment?
      if (!varAss.isNewDeclaration) dict["re"] = true;
      return dict;
    }

    // Void
    var voidObj = obj.csAs<Void>();
    if (voidObj != null) {
      return "void";
    }

    // Tag
    var tag = obj.csAs<Tag>();
    if (tag != null) {
      var dict = <String, dynamic>{};
      dict["#"] = tag.text;
      return dict;
    }

    // Used when serialising save state only
    var choice = obj.csAs<Choice>();
    if (choice != null) {
      return WriteChoice(choice);
    }

    throw Exception(
        "Failed to write runtime dynamic to JSON: " + obj.toString());
  }

  static Map<String, RuntimeObject> JObjectToDictionaryRuntimeObjs(
      Map<String, dynamic> jObject) {
    var dict = <String, RuntimeObject>{};

    for (var keyVal in jObject.entries) {
      dict[keyVal.key] = JTokenToRuntimeObject(keyVal.value)!;
    }

    return dict;
  }

  // ----------------------
  // JSON ENCODING SCHEME
  // ----------------------
  //
  // Glue:           "<>", "G<", "G>"
  //
  // ControlCommand: "ev", "out", "/ev", "du" "pop", "->->", "~ret", "str", "/str", "nop",
  //                 "choiceCnt", "turns", "visit", "seq", "thread", "done", "end"
  //
  // NativeFunction: "+", "-", "/", "*", "%" "~", "==", ">", "<", ">=", "<=", "!=", "!"... etc
  //
  // Void:           "void"
  //
  // Value:          "^string value", "^^string value beginning with ^"
  //                 5, 5.2
  //                 {"^->": "path.target"}
  //                 {"^var": "varname", "ci": 0}
  //
  // Container:      [...]
  //                 [...,
  //                     {
  //                         "subContainerName": ...,
  //                         "#f": 5,                    // flags
  //                         "#n": "containerOwnName"    // only if not redundant
  //                     }
  //                 ]
  //
  // Divert:         {"->": "path.target", "c": true }
  //                 {"->": "path.target", "var": true}
  //                 {"f()": "path.func"}
  //                 {"->t->": "path.tunnel"}
  //                 {"x()": "externalFuncName", "exArgs": 5}
  //
  // Var Assign:     {"VAR=": "varName", "re": true}   // reassignment
  //                 {"temp=": "varName"}
  //
  // Var ref:        {"VAR?": "varName"}
  //                 {"CNT?": "stitch name"}
  //
  // ChoicePoint:    {"*": pathString,
  //                  "flg": 18 }
  //
  // Choice:         Nothing too clever, it's only used in the save state,
  //                 there's not likely to be many of them.
  //
  // Tag:            {"#": "the tag text"}
  static RuntimeObject? JTokenToRuntimeObject(dynamic token) {
    if (token is int || token is double || token is bool) {
      return Value.Create(token);
    }

    if (token is String) {
      String str = token;

      // String value
      var firstChar = str[0];
      if (firstChar == '^') {
        return StringValue(str.substring(1));
      } else if (firstChar == '\n' && str.length == 1) {
        return StringValue("\n");
      }

      // Glue
      if (str == "<>") return Glue();

      // Control commands (would looking up in a hash set be faster?)
      for (int i = 0; i < _controlCommandNames.length; ++i) {
        String cmdName = _controlCommandNames[i]!;
        if (str == cmdName) {
          return ControlCommand(i);
        }
      }

      // Native functions
      // "^" conflicts with the way to identify strings, so now
      // we know it's not a string, we can convert back to the proper
      // symbol for the operator.
      if (str == "L^") str = "^";
      if (NativeFunctionCall.CallExistsWithName(str)) {
        return NativeFunctionCall.CallWithName(str);
      }

      // Pop
      if (str == "->->") {
        return ControlCommand(CommandType.PopTunnel);
      } else if (str == "~ret") {
        return ControlCommand(CommandType.PopFunction);
      }

      // Void
      if (str == "void") return Void();
    }

    if (token is Map<String, dynamic>) {
      var obj = token;
      dynamic propValue;

      // Divert target value to path
      propValue = obj["^->"];
      if (propValue != null) {
        return DivertTargetValue(Path.new3(propValue as String));
      }

      // VariablePointerValue
      propValue = obj["^var"];
      if (propValue != null) {
        var varPtr = VariablePointerValue(propValue as String);
        propValue = obj["ci"];
        if (propValue != null) varPtr.contextIndex = propValue as int;
        return varPtr;
      }

      // Divert
      bool isDivert = false;
      bool pushesToStack = false;
      PushPopType divPushType = PushPopType.Function;
      bool external = false;

      bool _skip = false;

      if (!_skip) {
        propValue = obj["->"];
        if (propValue != null) {
          isDivert = true;
          _skip = true;
        }
      }

      if (!_skip) {
        propValue = obj["f()"];
        if (propValue != null) {
          isDivert = true;
          pushesToStack = true;
          divPushType = PushPopType.Function;
          _skip = true;
        }
      }

      if (!_skip) {
        propValue = obj["->t->"];
        if (propValue != null) {
          isDivert = true;
          pushesToStack = true;
          divPushType = PushPopType.Tunnel;
          _skip = true;
        }
      }

      if (!_skip) {
        propValue = obj["x()"];
        if (propValue != null) {
          isDivert = true;
          external = true;
          pushesToStack = false;
          divPushType = PushPopType.Function;
          _skip = true;
        }
      }

      if (isDivert) {
        var divert = Divert();
        divert.pushesToStack = pushesToStack;
        divert.stackPushType = divPushType;
        divert.isExternal = external;

        String target = propValue.toString();

        propValue = obj["var"];
        if (propValue != null) {
          divert.variableDivertName = target;
        } else {
          divert.targetPathString = target;
        }

        propValue = obj["c"];
        divert.isConditional = propValue != null;

        if (external) {
          propValue = obj["exArgs"];
          if (propValue != null) divert.externalArgs = propValue as int;
        }

        return divert;
      }

      // Choice
      propValue = obj["*"];
      if (propValue != null) {
        var choice = ChoicePoint();
        choice.pathStringOnChoice = propValue.toString();

        propValue = obj["flg"];
        if (propValue != null) choice.flags = propValue as int;

        return choice;
      }

      // Variable reference
      propValue = obj["VAR?"];
      if (propValue != null) {
        return VariableReference(propValue.toString());
      } else {
        propValue = obj["CNT?"];
        if (propValue != null) {
          var readCountVarRef = VariableReference();
          readCountVarRef.pathStringForCount = propValue.toString();
          return readCountVarRef;
        }
      }

      // Variable assignment
      bool isVarAss = false;
      bool isGlobalVar = false;

      propValue = obj["VAR="];
      if (propValue != null) {
        isVarAss = true;
        isGlobalVar = true;
      } else {
        propValue = obj["temp="];
        if (propValue != null) {
          isVarAss = true;
          isGlobalVar = false;
        }
      }

      if (isVarAss) {
        var varName = propValue.toString();
        propValue = obj["re"];
        var isNewDecl = !(propValue != null);
        var varAss = VariableAssignment(varName, isNewDecl);
        varAss.isGlobal = isGlobalVar;
        return varAss;
      }

      // Tag
      propValue = obj["#"];
      if (propValue != null) {
        return Tag(propValue as String);
      }

      // Used when serialising save state only
      if (obj["originalChoicePath"] != null) return JObjectToChoice(obj);
    }

    // Array is always a Runtime.Container
    if (token is List) {
      return JArrayToContainer(token);
    }

    if (token == null) return null;

    throw Exception("Failed to convert token to runtime dynamic: " + token);
  }

  static dynamic WriteRuntimeContainer(Container container,
      [bool withoutName = false]) {
    List<dynamic> ret = [];

    for (var c in container.content) {
      ret.add(WriteRuntimeObject(c));
    }

    var namedOnlyContent = container.namedOnlyContent;
    var countFlags = container.countFlags;
    var hasNameProperty = container.name != null && !withoutName;

    bool hasTerminator =
        namedOnlyContent != null || countFlags > 0 || hasNameProperty;

    var dict = <String, dynamic>{};

    if (hasTerminator) {}

    if (namedOnlyContent != null) {
      for (var namedContent in namedOnlyContent.entries) {
        var name = namedContent.key;
        var namedContainer = namedContent.value as Container;
        dict[name] = WriteRuntimeContainer(namedContainer, true);
      }
    }

    if (countFlags > 0) dict["#f"] = countFlags;

    if (hasNameProperty) dict["#n"] = container.name;

    if (hasTerminator) {
      ret.add(dict);
    } else {
      ret.add(null);
    }

    return ret;
  }

  static Container JArrayToContainer(List<dynamic> jArray) {
    var container = Container();
    container.content = JArrayToRuntimeObjList<RuntimeObject>(jArray, true);

    var terminatingObj = jArray.last;
    if (terminatingObj != null && terminatingObj is Map<String, dynamic>) {
      var namedOnlyContent = <String, RuntimeObject?>{};

      for (var keyVal in terminatingObj.entries) {
        if (keyVal.key == "#f") {
          container.countFlags = keyVal.value as int;
        } else if (keyVal.key == "#n") {
          container.name = keyVal.value.toString();
        } else {
          var namedContentItem = JTokenToRuntimeObject(keyVal.value);
          var namedSubContainer = namedContentItem?.csAs<Container>();
          if (namedSubContainer != null) namedSubContainer.name = keyVal.key;
          namedOnlyContent[keyVal.key] = namedContentItem;
        }
      }

      container.namedOnlyContent = namedOnlyContent;
    }

    return container;
  }

  static Choice JObjectToChoice(Map<String, dynamic> jObj) {
    var choice = Choice();
    choice.text = jObj["text"].toString();
    choice.index = jObj["index"] as int;
    choice.sourcePath = jObj["originalChoicePath"].toString();
    choice.originalThreadIndex = jObj["originalThreadIndex"] as int;
    choice.pathStringOnChoice = jObj["targetPath"].toString();
    return choice;
  }

  static Map<String, dynamic> WriteChoice(Choice choice) {
    var dict = <String, dynamic>{};
    dict["text"] = choice.text;
    dict["index"] = choice.index;
    dict["originalChoicePath"] = choice.sourcePath;
    dict["originalThreadIndex"] = choice.originalThreadIndex;
    dict["targetPath"] = choice.pathStringOnChoice;
    return dict;
  }

  static const Map<int, String> _controlCommandNames = {
    CommandType.EvalStart: "ev",
    CommandType.EvalOutput: "out",
    CommandType.EvalEnd: "/ev",
    CommandType.Duplicate: "du",
    CommandType.PopEvaluatedValue: "pop",
    CommandType.PopFunction: "~ret",
    CommandType.PopTunnel: "->->",
    CommandType.BeginString: "str",
    CommandType.EndString: "/str",
    CommandType.NoOp: "nop",
    CommandType.ChoiceCount: "choiceCnt",
    CommandType.Turns: "turn",
    CommandType.TurnsSince: "turns",
    CommandType.ReadCount: "readc",
    CommandType.Random: "rnd",
    CommandType.SeedRandom: "srnd",
    CommandType.VisitIndex: "visit",
    CommandType.SequenceShuffleIndex: "seq",
    CommandType.StartThread: "thread",
    CommandType.Done: "done",
    CommandType.End: "end",
  };
}
