// reviewed

import 'container.dart';
import 'runtime_object.dart';
import 'path.dart';
import 'addons/extra.dart';

class Pointer extends Struct {
  Container? container;
  int index;

  Pointer({required this.container, required this.index});

  RuntimeObject? Resolve() {
    if (index < 0) return container;
    if (container == null) return null;
    if (container!.content.isEmpty) return container;
    if (index >= container!.content.length) return null;
    return container!.content[index];
  }

  bool get isNull => container == null;

  Path? get path {
    if (isNull) return null;

    if (index >= 0) {
      return container!.path
          .PathByAppendingComponent(PathComponent.new1(index));
    } else {
      return container!.path;
    }
  }

  @override
  String toString() {
    if (container == null) return "Ink Pointer (null)";
    return "Ink Pointer -> " + container!.path.toString() + " -- index $index";
  }

  static Pointer StartOf(Container? container) {
    return Pointer(container: container, index: 0);
  }

  static Pointer get Null => Pointer(container: null, index: -1);

  @override
  Struct clone() {
    return Pointer(container: container, index: index);
  }
}
