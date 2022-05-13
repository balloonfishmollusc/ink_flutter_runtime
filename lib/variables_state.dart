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
  final Event variableChangedEvent = Event(2);

  StatePatch? patch;

  set batchObservingVariableChanges(bool value) {
    _batchObservingVariableChanges = value;
    if (value) {
      _changedVariablesForBatchObs = <String>{};
    }

    // Finished observing variables in a batch - now send
    // notifications for changed variables all in one go.
    else {
      if (_changedVariablesForBatchObs != null) {
        for (var variableName in _changedVariablesForBatchObs!) {
          var currentValue = _globalVariables[variableName]!;
          variableChangedEvent.fire([variableName, currentValue]);
        }
      }

      _changedVariablesForBatchObs = null;
    }
  }

  bool get batchObservingVariableChanges => _batchObservingVariableChanges;
  bool _batchObservingVariableChanges = false;

  operator [](String? variableName) {
    RuntimeObject? varContents = patch?.globals[variableName];

    if (patch != null && varContents != null) {
      return (varContents as Value).valueObject;
    }

    // Search main dictionary first.
    // If it's not found, it might be because the story content has changed,
    // and the original default value hasn't be instantiated.
    // Should really warn somehow, but it's difficult to see how...!
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

    var val = Value.create(value);
    SetGlobal(variableName, val);
  }

  @override
  Iterator<String> get iterator => _globalVariables.keys.iterator;

  VariablesState(this.callStack);

  void ApplyPatch() {
    for (var namedVar in patch!.globals.entries) {
      _globalVariables[namedVar.key] = namedVar.value;
    }

    if (_changedVariablesForBatchObs != null) {
      for (var name in patch!.changedVariables) {
        _changedVariablesForBatchObs!.add(name);
      }
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

  bool RuntimeObjectsEqual(RuntimeObject obj1, RuntimeObject obj2) {
    if (obj1.runtimeType != obj2.runtimeType) return false;

    // Perform equality on int/float/bool manually to avoid boxing
    var boolVal = obj1.csAs<BoolValue>();
    if (boolVal != null) {
      return boolVal.value == (obj2 as BoolValue).value;
    }

    var intVal = obj1.csAs<IntValue>();
    if (intVal != null) {
      return intVal.value == (obj2 as IntValue).value;
    }

    var floatVal = obj1.csAs<FloatValue>();
    if (floatVal != null) {
      return floatVal.value == (obj2 as FloatValue).value;
    }

    // Other Value type (using proper Equals: list, string, divert path)
    var val1 = obj1.csAs<Value>();
    var val2 = obj2.csAs<Value>();
    if (val1 != null) {
      return val1.valueObject == val2?.valueObject;
    }

    throw Exception(
        "FastRoughDefinitelyEquals: Unsupported runtime object type: " +
            obj1.runtimeType.toString());
  }

  RuntimeObject? TryGetDefaultVariableValue(String name) {
    return _defaultGlobalVariables[name];
  }

  bool GlobalVariableExistsWithName(String name) {
    return _globalVariables.containsKey(name) ||
        true && _defaultGlobalVariables.containsKey(name);
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

      // Getting variables can actually happen during globals set up since you can do
      //  VAR x = A_LIST_ITEM
      // So _defaultGlobalVariables may be null.
      // We need to do this check though in case a new global is added, so we need to
      // revert to the default globals dictionary since an initial value hasn't yet been set.
      varValue = _defaultGlobalVariables[name];

      if (varValue != null) {
        return varValue;
      }
    }

    // Temporary
    varValue = callStack.getTemporaryVariableWithName(name, contextIndex);

    return varValue;
  }

  RuntimeObject? ValueAtVariablePointer(VariablePointerValue pointer) {
    return GetVariableWithName(pointer.variableName!, pointer.contextIndex);
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
      callStack.setTemporaryVariable(
          name!, value, varAss.isNewDeclaration, contextIndex);
    }
  }

  void SnapshotDefaultGlobals() {
    _defaultGlobalVariables.clear();
    _defaultGlobalVariables
        .addAll(Map<String, RuntimeObject>.of(_globalVariables));
  }

  void SetGlobal(String variableName, RuntimeObject value) {
    RuntimeObject? oldValue = patch?.globals[variableName];
    if (patch == null || !(oldValue != null)) {
      oldValue = _globalVariables[variableName];
    }

    if (patch != null) {
      patch!.globals[variableName] = value;
    } else {
      _globalVariables[variableName] = value;
    }

    if (variableChangedEvent.isNotEmpty && !(value == oldValue)) {
      if (batchObservingVariableChanges) {
        if (patch != null) {
          patch!.changedVariables.add(variableName);
        } else if (_changedVariablesForBatchObs != null) {
          _changedVariablesForBatchObs!.add(variableName);
        }
      } else {
        variableChangedEvent.fire([variableName, value]);
      }
    }
  }

  // Given a variable pointer with just the name of the target known, resolve to a variable
  // pointer that more specifically points to the exact instance: whether it's global,
  // or the exact position of a temporary on the callstack.
  VariablePointerValue ResolveVariablePointer(VariablePointerValue varPointer) {
    int contextIndex = varPointer.contextIndex;

    if (contextIndex == -1) {
      contextIndex = GetContextIndexOfVariableNamed(varPointer.variableName!);
    }

    var valueOfVariablePointedTo =
        GetRawVariableWithName(varPointer.variableName!, contextIndex);

    // Extra layer of indirection:
    // When accessing a pointer to a pointer (e.g. when calling nested or
    // recursive functions that take a variable references, ensure we don't create
    // a chain of indirection by just returning the final target.
    var doubleRedirectionPointer =
        valueOfVariablePointedTo?.csAs<VariablePointerValue>();
    if (doubleRedirectionPointer != null) {
      return doubleRedirectionPointer;
    }

    // Make copy of the variable pointer so we're not using the value direct from
    // the runtime. Temporary must be local to the current scope.
    else {
      return VariablePointerValue(varPointer.variableName, contextIndex);
    }
  }

  // 0  if named variable is global
  // 1+ if named variable is a temporary in a particular call stack element
  int GetContextIndexOfVariableNamed(String varName) {
    if (GlobalVariableExistsWithName(varName)) return 0;

    return callStack.currentElementIndex;
  }

  final Map<String, RuntimeObject> _globalVariables = {};

  final Map<String, RuntimeObject> _defaultGlobalVariables = {};

  // Used for accessing temporary variables
  CallStack callStack;
  Set<String>? _changedVariablesForBatchObs;
}
