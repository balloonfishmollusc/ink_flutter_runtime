import 'dart:math';

import 'path.dart';
import 'runtime_object.dart';
import 'story_exception.dart';
import 'value.dart';
import 'void.dart';

class NativeFunctionCall extends RuntimeObject {
  static const String Add = "+";
  static const String Subtract = "-";
  static const String Divide = "/";
  static const String Multiply = "*";
  static const String Mod = "%";
  static const String Negate = "_"; // distinguish from "-" for subtraction

  static const String Equal = "==";
  static const String Greater = ">";
  static const String Less = "<";
  static const String GreaterThanOrEquals = ">=";
  static const String LessThanOrEquals = "<=";
  static const String NotEquals = "!=";
  static const String Not = "!";

  static const String And = "&&";
  static const String Or = "||";

  static const String Min = "MIN";
  static const String Max = "MAX";

  static const String Pow = "POW";
  static const String Floor = "FLOOR";
  static const String Ceiling = "CEILING";
  static const String Int = "INT";
  static const String Float = "FLOAT";

  static const String Has = "?";
  static const String Hasnt = "!?";
  static const String Intersect = "^";

  static NativeFunctionCall callWithName(String functionName) {
    return NativeFunctionCall(functionName);
  }

  static bool callExistsWithName(String functionName) {
    generateNativeFunctionsIfNecessary();
    return _nativeFunctions!.containsKey(functionName);
  }

  String? get name => _name;

  _setName(String? value) {
    _name = value;
    if (!_isPrototype) _prototype = _nativeFunctions![_name];
  }

  String? _name;

  int get numberOfParameters {
    if (_prototype != null) {
      return _prototype!.numberOfParameters;
    } else {
      return _numberOfParameters;
    }
  }

  void _setNumberOfParameters(int value) {
    _numberOfParameters = value;
  }

  int _numberOfParameters = 0;

  RuntimeObject? call(List<RuntimeObject> parameters) {
    if (_prototype != null) {
      return _prototype!.call(parameters);
    }

    if (numberOfParameters != parameters.length) {
      throw Exception("Unexpected number of parameters");
    }

    for (var p in parameters) {
      if (p is Void) {
        throw StoryException(
            "Attempting to perform operation on a void value. Did you forget to 'return' a value from a function you called here?");
      }
    }

    var coercedParams = _coerceValuesToSingleType(parameters);
    ValueType coercedType = coercedParams[0].valueType;

    if (coercedType == ValueType.Int) {
      return _call<int>(coercedParams);
    } else if (coercedType == ValueType.Float) {
      return _call<double>(coercedParams);
    } else if (coercedType == ValueType.String) {
      return _call<String>(coercedParams);
    } else if (coercedType == ValueType.DivertTarget) {
      return _call<Path>(coercedParams);
    }

    return null;
  }

  Value _call<T>(List<Value> parametersOfSingleType) {
    Value param1 = parametersOfSingleType[0];
    ValueType valType = param1.valueType;

    var val1 = param1 as Value<T>;

    int paramCount = parametersOfSingleType.length;

    if (paramCount == 2 || paramCount == 1) {
      dynamic opForTypeObj = _operationFuncs![valType];
      if (opForTypeObj == null) {
        throw StoryException("Cannot perform operation '$name' on $valType");
      }

      // Binary
      if (paramCount == 2) {
        Value param2 = parametersOfSingleType[1];

        var val2 = param2 as Value<T>;

        var opForType = opForTypeObj as BinaryOp<T>;

        // Return value unknown until it's evaluated
        dynamic resultVal = opForType(val1.value, val2.value);

        return Value.create(resultVal);
      }

      // Unary
      else {
        var opForType = opForTypeObj as UnaryOp<T>;

        var resultVal = opForType(val1.value);

        return Value.create(resultVal);
      }
    } else {
      throw Exception(
          "Unexpected number of parameters to NativeFunctionCall: " +
              parametersOfSingleType.length.toString());
    }
  }

  List<Value> _coerceValuesToSingleType(List<RuntimeObject> parametersIn) {
    ValueType valType = ValueType.Int;

    // Find out what the output type is
    // "higher level" types infect both so that binary operations
    // use the same type on both sides. e.g. binary operation of
    // int and float causes the int to be casted to a float.
    for (var obj in parametersIn) {
      var val = obj as Value;
      if (val.valueType.index > valType.index) {
        valType = val.valueType;
      }
    }

    // Coerce to this chosen type
    var parametersOut = <Value>[];

    for (Value val in parametersIn.cast()) {
      var castedValue = val.cast(valType);
      parametersOut.add(castedValue);
    }

    return parametersOut;
  }

  NativeFunctionCall([String? name, int? numberOfParameters]) {
    if (numberOfParameters == null) {
      generateNativeFunctionsIfNecessary();
    } else {
      _isPrototype = true;
      _setNumberOfParameters(numberOfParameters);
    }

    if (name != null) _setName(name);
  }

  static dynamic identity<T>(T t) {
    return t;
  }

  static void generateNativeFunctionsIfNecessary() {
    if (_nativeFunctions == null) {
      _nativeFunctions = <String, NativeFunctionCall>{};

      // Why no bool operations?
      // Before evaluation, all bools are coerced to ints in
      // CoerceValuesToSingleType (see default value for valType at top).
      // So, no operations are ever directly done in bools themselves.
      // This also means that 1 == true works, since true is always converted
      // to 1 first.
      // However, many operations return a "native" bool (equals, etc).

      // Int operations
      AddIntBinaryOp(Add, (x, y) => x + y);
      AddIntBinaryOp(Subtract, (x, y) => x - y);
      AddIntBinaryOp(Multiply, (x, y) => x * y);
      AddIntBinaryOp(Divide, (x, y) => x / y);
      AddIntBinaryOp(Mod, (x, y) => x % y);
      AddIntUnaryOp(Negate, (x) => -x);

      AddIntBinaryOp(Equal, (x, y) => x == y);
      AddIntBinaryOp(Greater, (x, y) => x > y);
      AddIntBinaryOp(Less, (x, y) => x < y);
      AddIntBinaryOp(GreaterThanOrEquals, (x, y) => x >= y);
      AddIntBinaryOp(LessThanOrEquals, (x, y) => x <= y);
      AddIntBinaryOp(NotEquals, (x, y) => x != y);
      AddIntUnaryOp(Not, (x) => x == 0);

      AddIntBinaryOp(And, (x, y) => x != 0 && y != 0);
      AddIntBinaryOp(Or, (x, y) => x != 0 || y != 0);

      AddIntBinaryOp(Max, (x, y) => max(x, y));
      AddIntBinaryOp(Min, (x, y) => min(x, y));

      // Have to cast to float since you could do POW(2, -1)
      AddIntBinaryOp(Pow, (x, y) => pow(x, y));
      AddIntUnaryOp(Floor, identity);
      AddIntUnaryOp(Ceiling, identity);
      AddIntUnaryOp(Int, identity);
      AddIntUnaryOp(Float, (x) => x * 1.0);

      // Float operations
      AddFloatBinaryOp(Add, (x, y) => x + y);
      AddFloatBinaryOp(Subtract, (x, y) => x - y);
      AddFloatBinaryOp(Multiply, (x, y) => x * y);
      AddFloatBinaryOp(Divide, (x, y) => x / y);
      AddFloatUnaryOp(Negate, (x) => -x);

      AddFloatBinaryOp(Equal, (x, y) => x == y);
      AddFloatBinaryOp(Greater, (x, y) => x > y);
      AddFloatBinaryOp(Less, (x, y) => x < y);
      AddFloatBinaryOp(GreaterThanOrEquals, (x, y) => x >= y);
      AddFloatBinaryOp(LessThanOrEquals, (x, y) => x <= y);
      AddFloatBinaryOp(NotEquals, (x, y) => x != y);
      AddFloatUnaryOp(Not, (x) => (x == 0.0));

      AddFloatBinaryOp(And, (x, y) => x != 0.0 && y != 0.0);
      AddFloatBinaryOp(Or, (x, y) => x != 0.0 || y != 0.0);

      AddFloatBinaryOp(Max, (x, y) => max(x, y));
      AddFloatBinaryOp(Min, (x, y) => min(x, y));

      AddFloatBinaryOp(Pow, (x, y) => pow(x, y));
      AddFloatUnaryOp(Floor, (x) => (x).floor());
      AddFloatUnaryOp(Ceiling, (x) => (x).ceil());
      AddFloatUnaryOp(Int, (x) => (x).floor());
      AddFloatUnaryOp(Float, identity);

      // String operations
      AddStringBinaryOp(Add, (x, y) => x + y); // concat
      AddStringBinaryOp(Equal, (x, y) => x == y);
      AddStringBinaryOp(NotEquals, (x, y) => !(x == y));
      AddStringBinaryOp(Has, (x, y) => x.contains(y));
      AddStringBinaryOp(Hasnt, (x, y) => !x.contains(y));

      // Special case: The only operations you can do on divert target values
      BinaryOp<Path> divertTargetsEqual = (Path d1, Path d2) {
        return d1 == d2;
      };
      BinaryOp<Path> divertTargetsNotEqual = (Path d1, Path d2) {
        return !(d1 == d2);
      };
      AddOpToNativeFunc(Equal, 2, ValueType.DivertTarget, divertTargetsEqual);
      AddOpToNativeFunc(
          NotEquals, 2, ValueType.DivertTarget, divertTargetsNotEqual);
    }
  }

  void AddOpFuncForType(ValueType valType, dynamic op) {
    _operationFuncs ??= <ValueType, dynamic>{};
    _operationFuncs![valType] = op;
  }

  static void AddOpToNativeFunc(
      String name, int args, ValueType valType, dynamic op) {
    NativeFunctionCall? nativeFunc;
    nativeFunc = _nativeFunctions![name];
    if (nativeFunc == null) {
      nativeFunc = NativeFunctionCall(name, args);
      _nativeFunctions![name] = nativeFunc;
    }

    nativeFunc.AddOpFuncForType(valType, op);
  }

  static void AddIntBinaryOp(String name, BinaryOp<int> op) {
    AddOpToNativeFunc(name, 2, ValueType.Int, op);
  }

  static void AddIntUnaryOp(String name, UnaryOp<int> op) {
    AddOpToNativeFunc(name, 1, ValueType.Int, op);
  }

  static void AddFloatBinaryOp(String name, BinaryOp<double> op) {
    AddOpToNativeFunc(name, 2, ValueType.Float, op);
  }

  static void AddStringBinaryOp(String name, BinaryOp<String> op) {
    AddOpToNativeFunc(name, 2, ValueType.String, op);
  }

  static void AddFloatUnaryOp(String name, UnaryOp<double> op) {
    AddOpToNativeFunc(name, 1, ValueType.Float, op);
  }

  @override
  String toString() => "Native '$name'";

  NativeFunctionCall? _prototype;
  bool _isPrototype = false;

  // Operations for each data type, for a single operation (e.g. "+")
  Map<ValueType, dynamic>? _operationFuncs;

  static Map<String, NativeFunctionCall>? _nativeFunctions;
}

typedef BinaryOp<T> = Function(T left, T right);
typedef UnaryOp<T> = Function(T val);
