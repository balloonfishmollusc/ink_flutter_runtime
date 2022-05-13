// reviewed

import 'runtime_object.dart';
import 'path.dart';
import 'story_exception.dart';

enum ValueType {
  // Bool is new addition, keep enum values the same, with Int==0, Float==1 etc,
  // but for coersion rules, we want to keep bool with a lower value than Int
  // so that it converts in the right direction
  Bool,
  // Used in coersion
  Int,
  Float,
  String,

  // Not used for coersion described above
  DivertTarget,
  VariablePointer,
}

abstract class Value<T> extends RuntimeObject {
  T value;

  get valueObject => value;

  Value(this.value);

  @override
  String toString() => value.toString();

  static Value Create(dynamic val) {
    if (val is bool) {
      return BoolValue(val);
    } else if (val is int) {
      return IntValue(val);
    } else if (val is double) {
      return FloatValue(val);
    } else if (val is String) {
      return StringValue(val);
    } else if (val is Path) {
      return DivertTargetValue(val);
    }
    throw Exception("Invalid value passed: $val");
  }

  ValueType get valueType;
  bool get isTruthy;

  Value Cast(ValueType newType);

  @override
  RuntimeObject Copy() => Create(valueObject);

  StoryException badCastException(ValueType targetType) {
    return StoryException(
        "Can't cast $valueObject from $valueType to $targetType");
  }
}

class BoolValue extends Value<bool> {
  BoolValue([bool value = false]) : super(value);

  @override
  Value Cast(ValueType newType) {
    if (newType == valueType) {
      return this;
    }

    if (newType == ValueType.Int) {
      return IntValue(value ? 1 : 0);
    }

    if (newType == ValueType.Float) {
      return FloatValue(value ? 1.0 : 0.0);
    }

    if (newType == ValueType.String) {
      return StringValue(value.toString());
    }

    throw badCastException(newType);
  }

  @override
  bool get isTruthy => value;

  @override
  ValueType get valueType => ValueType.Bool;
}

class IntValue extends Value<int> {
  IntValue([int value = 0]) : super(value);

  @override
  Value Cast(ValueType newType) {
    if (newType == valueType) {
      return this;
    }

    if (newType == ValueType.Bool) {
      return BoolValue(value != 0);
    }

    if (newType == ValueType.Float) {
      return FloatValue(value * 1.0);
    }

    if (newType == ValueType.String) {
      return StringValue(value.toString());
    }

    throw badCastException(newType);
  }

  @override
  bool get isTruthy => value != 0;

  @override
  ValueType get valueType => ValueType.Int;
}

class FloatValue extends Value<double> {
  FloatValue([double value = 0]) : super(value);

  @override
  Value Cast(ValueType newType) {
    if (newType == valueType) {
      return this;
    }

    if (newType == ValueType.Bool) {
      return BoolValue(value != 0.0);
    }

    if (newType == ValueType.String) {
      return StringValue(value.toString());
    }

    throw badCastException(newType);
  }

  @override
  bool get isTruthy => value != 0.0;

  @override
  ValueType get valueType => ValueType.Float;
}

class StringValue extends Value<String> {
  late final bool isNewline;
  late final bool isInlineWhitespace;

  StringValue([String value = ""]) : super(value) {
    isNewline = value == "\n";
    isInlineWhitespace = value.trim().isEmpty;
  }

  bool get isNonWhitespace => !isNewline && !isInlineWhitespace;

  @override
  Value Cast(ValueType newType) {
    if (newType == valueType) {
      return this;
    }

    throw badCastException(newType);
  }

  @override
  bool get isTruthy => value.isNotEmpty;

  @override
  ValueType get valueType => ValueType.String;
}

class DivertTargetValue extends Value<Path?> {
  DivertTargetValue([Path? value]) : super(value);

  Path? get targetPath => value;
  set targetPath(Path? value) => this.value = value;

  @override
  Value Cast(ValueType newType) {
    if (newType == valueType) return this;

    throw badCastException(newType);
  }

  @override
  bool get isTruthy => throw UnimplementedError();

  @override
  ValueType get valueType => ValueType.DivertTarget;

  @override
  String toString() {
    return "DivertTargetValue($targetPath)";
  }
}

class VariablePointerValue extends Value<String> {
  VariablePointerValue(String value, [this.contextIndex = -1]) : super(value);

  String get variableName => value;
  set variableName(String value) => this.value = value;

  int contextIndex;

  @override
  Value Cast(ValueType newType) {
    if (newType == valueType) return this;

    throw badCastException(newType);
  }

  @override
  bool get isTruthy => throw UnimplementedError();

  @override
  ValueType get valueType => ValueType.VariablePointer;

  @override
  String toString() {
    return "VariablePointerValue($variableName)";
  }

  @override
  RuntimeObject Copy() {
    return VariablePointerValue(variableName, contextIndex);
  }
}
