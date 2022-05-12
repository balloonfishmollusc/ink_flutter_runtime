// reviewed

import 'container.dart';
import 'runtime_object.dart';
import 'path.dart';

class VariableReference extends RuntimeObject {
  String? name;

  Path? pathForCount;

  Container? get containerForCount {
    return ResolvePath(pathForCount!).container;
  }

  String? get pathStringForCount {
    if (pathForCount == null) return null;
    return CompactPathString(pathForCount!);
  }

  set pathStringForCount(String? value) {
    if (value == null) {
      pathForCount = null;
    } else {
      pathForCount = Path.new3(value);
    }
  }

  VariableReference([this.name]);

  @override
  String toString() {
    if (name != null) {
      return "var($name)";
    } else {
      var pathStr = pathStringForCount;
      return "read_count($pathStr)";
    }
  }
}
