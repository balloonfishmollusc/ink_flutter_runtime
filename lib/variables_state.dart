// reviewed

import 'call_stack.dart';
import 'addons/extra.dart';
import 'json_serialisation.dart';
import 'runtime_object.dart';
import 'state_patch.dart';
import 'story_exception.dart';
import 'value.dart';
import 'variable_assignment.dart';

//typedef VariableChanged = void Function(
//    String variableName, RuntimeObject newValue);

class VariablesState extends Iterable<String> {
  StatePatch? patch;
  bool batchObservingVariableChanges = false;

  operator [](String variableName) {
    RuntimeObject? varContents = patch?.globals[variableName];

    if (patch != null && varContents != null) {
      return (varContents as Value).valueObject;
    }

    varContents = _globalVariables[variableName];
    varContents ??= _defaultGlobalVariables[variableName];
    if (varContents != null) {
      return (varContents as Value).valueObject;
    } else {
      return null;
    }
  }

  operator []=(String variableName, value) {
    if (!_defaultGlobalVariables.containsKey(variableName)) {
      throw StoryException(
          "Cannot assign to a variable ($variableName) that hasn't been declared in the story");
    }

    var val = Value.Create(value);
    SetGlobal(variableName, val);
  }

  @override
  Iterator<String> get iterator => _globalVariables.keys.iterator;

  VariablesState(this.callStack);

  void ApplyPatch() {
    for (var namedVar in patch!.globals.entries) {
      _globalVariables[namedVar.key] = namedVar.value;
    }
    patch = null;
  }

  void SetJsonToken(Map<String, dynamic> jToken) {
    _globalVariables.clear();

    for (var varVal in _defaultGlobalVariables.entries) {
      dynamic loadedToken = jToken[varVal.key];
      if (loadedToken != null) {
        _globalVariables[varVal.key] = Json.JTokenToRuntimeObject(loadedToken)!;
      } else {
        _globalVariables[varVal.key] = varVal.value;
      }
    }
  }

  dynamic WriteJson() {
    var dict = <String, dynamic>{};
    for (var keyVal in _globalVariables.entries) {
      var name = keyVal.key;
      var val = keyVal.value;
      dict[name] = Json.WriteRuntimeObject(val);
    }
    return dict;
  }

  RuntimeObject? TryGetDefaultVariableValue(String name) {
    return _defaultGlobalVariables[name];
  }

  bool GlobalVariableExistsWithName(String name) {
    return _globalVariables.containsKey(name) ||
        _defaultGlobalVariables.containsKey(name);
  }

  RuntimeObject? GetVariableWithName(String name, [int contextIndex = -1]) {
    RuntimeObject? varValue = GetRawVariableWithName(name, contextIndex);

    // Get value from pointer?
    var varPointer = varValue?.csAs<VariablePointerValue>();
    if (varPointer != null) {
      varValue = ValueAtVariablePointer(varPointer);
    }

    return varValue;
  }

  RuntimeObject? GetRawVariableWithName(String name, int contextIndex) {
    RuntimeObject? varValue;

    // 0 context = global
    if (contextIndex == 0 || contextIndex == -1) {
      varValue = patch?.globals[name];
      if (patch != null && varValue != null) return varValue;

      varValue = _globalVariables[name];
      if (varValue != null) return varValue;

      varValue = _defaultGlobalVariables[name];

      if (varValue != null) return varValue;
    }

    // Temporary
    varValue = callStack.GetTemporaryVariableWithName(name, contextIndex);

    return varValue;
  }

  RuntimeObject? ValueAtVariablePointer(VariablePointerValue pointer) {
    return GetVariableWithName(pointer.variableName, pointer.contextIndex);
  }

  void Assign(VariableAssignment varAss, RuntimeObject value) {
    var name = varAss.variableName;
    int contextIndex = -1;

    // Are we assigning to a global variable?
    bool setGlobal = false;
    if (varAss.isNewDeclaration) {
      setGlobal = varAss.isGlobal;
    } else {
      setGlobal = GlobalVariableExistsWithName(name!);
    }

    // Constructing new variable pointer reference
    if (varAss.isNewDeclaration) {
      var varPointer = value.csAs<VariablePointerValue>();
      if (varPointer != null) {
        var fullyResolvedVariablePointer = ResolveVariablePointer(varPointer);
        value = fullyResolvedVariablePointer;
      }
    }

    // Assign to existing variable pointer?
    // Then assign to the variable that the pointer is pointing to by name.
    else {
      // De-reference variable reference to point to
      VariablePointerValue? existingPointer;
      do {
        existingPointer = GetRawVariableWithName(name!, contextIndex)
            ?.csAs<VariablePointerValue>();
        if (existingPointer != null) {
          name = existingPointer.variableName;
          contextIndex = existingPointer.contextIndex;
          setGlobal = (contextIndex == 0);
        }
      } while (existingPointer != null);
    }

    if (setGlobal) {
      SetGlobal(name!, value);
    } else {
      callStack.SetTemporaryVariable(
          name!, value, varAss.isNewDeclaration, contextIndex);
    }
  }

  void SnapshotDefaultGlobals() {
    _defaultGlobalVariables.clear();
    _defaultGlobalVariables.addAll(Map.of(_globalVariables));
  }

  void SetGlobal(String variableName, RuntimeObject value) {
    RuntimeObject? oldValue = patch?.globals[variableName];
    if (patch == null || oldValue == null) {
      oldValue = _globalVariables[variableName];
    }

    if (patch != null) {
      patch!.globals[variableName] = value;
    } else {
      _globalVariables[variableName] = value;
    }
  }

  VariablePointerValue ResolveVariablePointer(VariablePointerValue varPointer) {
    int contextIndex = varPointer.contextIndex;

    if (contextIndex == -1) {
      contextIndex = GetContextIndexOfVariableNamed(varPointer.variableName);
    }

    var valueOfVariablePointedTo =
        GetRawVariableWithName(varPointer.variableName, contextIndex);

    var doubleRedirectionPointer =
        valueOfVariablePointedTo?.csAs<VariablePointerValue>();
    if (doubleRedirectionPointer != null) {
      return doubleRedirectionPointer;
    } else {
      return VariablePointerValue(varPointer.variableName, contextIndex);
    }
  }

  int GetContextIndexOfVariableNamed(String varName) {
    if (GlobalVariableExistsWithName(varName)) return 0;

    return callStack.currentElementIndex;
  }

  final Map<String, RuntimeObject> _globalVariables = {};

  final Map<String, RuntimeObject> _defaultGlobalVariables = {};

  // Used for accessing temporary variables
  CallStack callStack;
}
