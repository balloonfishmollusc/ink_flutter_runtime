import 'container.dart';
import 'runtime_object.dart';
import 'path.dart';

class VariableReference extends RuntimeObject {
  // Normal named variable
  String? name;

  // Variable reference is actually a path for a visit (read) count
  Path? pathForCount;

  Container? get containerForCount {
    if (pathForCount == null) return null;
    return resolvePath(pathForCount!).container;
  }

  String? get pathStringForCount {
    if (pathForCount == null) return null;
    return compactPathString(pathForCount!);
  }

  set pathStringForCount(String? value) {
    if (value == null)
      pathForCount = null;
    else
      pathForCount = Path.new3(value);
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
