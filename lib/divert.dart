// reviewed

import 'container.dart';
import 'push_pop.dart';
import 'runtime_object.dart';
import 'path.dart';
import 'pointer.dart';
import 'addons/extra.dart';

class Divert extends RuntimeObject {
  Path? _targetPath;

  Path? get targetPath {
    if (_targetPath != null && _targetPath!.isRelative) {
      var targetObj = targetPointer.Resolve();
      if (targetObj != null) {
        _targetPath = targetObj.path;
      }
    }
    return _targetPath;
  }

  set targetPath(Path? value) {
    _targetPath = value;
    _targetPointer = Pointer.Null;
  }

  Pointer get targetPointer {
    if (_targetPointer.isNull) {
      var targetObj = ResolvePath(_targetPath!).obj!;

      if (_targetPath!.lastComponent!.isIndex) {
        _targetPointer.container = targetObj.parent?.csAs<Container>();
        _targetPointer.index = _targetPath!.lastComponent!.index;
      } else {
        _targetPointer = Pointer.StartOf(targetObj.csAs<Container>());
      }
    }
    return _targetPointer.clone() as Pointer;
  }

  Pointer _targetPointer = Pointer.Null;

  String? get targetPathString {
    if (targetPath == null) return null;

    return CompactPathString(targetPath!);
  }

  set targetPathString(String? value) {
    if (value == null) {
      targetPath = null;
    } else {
      targetPath = Path.new3(value);
    }
  }

  String? variableDivertName;
  bool get hasVariableTarget => variableDivertName != null;

  bool pushesToStack = false;
  PushPopType stackPushType = PushPopType.Function;

  bool isExternal = false;
  int externalArgs = 0;

  bool isConditional = false;

  Divert([PushPopType? stackPushType]) {
    if (stackPushType == null) {
      pushesToStack = false;
    } else {
      pushesToStack = true;
      this.stackPushType = stackPushType;
    }
  }

  @override
  int get hashCode {
    if (hasVariableTarget) {
      const int variableTargetSalt = 12345;
      return variableDivertName.hashCode + variableTargetSalt;
    } else {
      const int pathTargetSalt = 54321;
      return targetPath.hashCode + pathTargetSalt;
    }
  }

  @override
  bool operator ==(Object other) {
    var otherDivert = other.csAs<Divert>();
    if (otherDivert != null) {
      if (hasVariableTarget == otherDivert.hasVariableTarget) {
        if (hasVariableTarget) {
          return variableDivertName == otherDivert.variableDivertName;
        } else {
          return targetPath == otherDivert.targetPath;
        }
      }
    }
    return false;
  }

  @override
  String toString() {
    if (hasVariableTarget) {
      return "Divert(variable: $variableDivertName)";
    } else if (targetPath == null) {
      return "Divert(null)";
    } else {
      var sb = StringBuilder();

      String targetStr = targetPath.toString();
      int? targetLineNum = debugLineNumberOfPath(targetPath);
      if (targetLineNum != null) {
        targetStr = "line $targetLineNum";
      }

      sb.add("Divert");

      if (isConditional) sb.add("?");

      if (pushesToStack) {
        if (stackPushType == PushPopType.Function) {
          sb.add(" function");
        } else {
          sb.add(" tunnel");
        }
      }

      sb.add(" -> ");
      sb.add(targetPathString.toString());

      sb.add(" (");
      sb.add(targetStr);
      sb.add(")");

      return sb.toString();
    }
  }
}
