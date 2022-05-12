import 'dart:math';
import 'addons/stack.dart';
import 'dart:collection';

import 'container.dart';
import 'i_named_content.dart';
import 'path.dart';
import 'debug_metadata.dart';
import 'search_result.dart';

class StringBuilder extends ListBase<String> {
  final List<String> lst = <String>[];

  @override
  int get length => lst.length;

  @override
  String operator [](int index) => lst[index];

  @override
  void operator []=(int index, String value) {
    lst[index] = value;
  }

  @override
  set length(int newLength) {
    lst.length = newLength;
  }

  @override
  String toString() => lst.join();
}

class RuntimeObject {
  T? tryCast<T extends RuntimeObject>() {
    if (this is T) return this as T;
    return null;
  }

  RuntimeObject? parent;

  DebugMetadata? get debugMetadata {
    if (_debugMetadata == null) {
      if (parent != null) {
        return parent!.debugMetadata;
      }
    }
    return _debugMetadata;
  }

  set debugMetadata(value) {
    _debugMetadata = value;
  }

  DebugMetadata? get ownDebugMetadata => _debugMetadata;
  DebugMetadata? _debugMetadata;

  int? debugLineNumberOfPath(Path? path) {
    if (path == null) return null;

    // Try to get a line number from debug metadata
    var root = rootContentContainer;
    if (root != null) {
      RuntimeObject? targetContent = root.ContentAtPath(path).obj;
      if (targetContent != null) {
        var dm = targetContent.debugMetadata;
        if (dm != null) {
          return dm.startLineNumber;
        }
      }
    }

    return null;
  }

  Path? _path;
  Path? get path {
    if (_path == null) {
      if (parent == null) {
        _path = Path();
      } else {
        // Maintain a Stack so that the order of the components
        // is reversed when they're added to the Path.
        // We're iterating up the hierarchy from the leaves/children to the root.
        var comps = Stack<PathComponent>();

        RuntimeObject child = this;
        Container? container = child.parent as Container;

        while (container != null) {
          if (child is INamedContent) {
            var namedChild = child as INamedContent;
            if (namedChild.hasValidName) {
              comps.push(PathComponent.new2(namedChild.name!));
            }
          } else {
            comps.push(PathComponent.new1(container.content.indexOf(child)));
          }

          child = container;
          container = container.parent as Container;
        }

        _path = Path.new2(comps.toList());
      }
    }

    return _path;
  }

  SearchResult ResolvePath(Path path) {
    if (path.isRelative) {
      Container? nearestContainer = tryCast<Container>();
      if (nearestContainer == null) {
        assert(parent != null,
            "Can't resolve relative path because we don't have a parent");

        nearestContainer = parent!.tryCast<Container>();
        assert(nearestContainer != null, "Expected parent to be a container");
        assert(path.getComponent(0)!.isParent);
        path = path.tail;
      }

      return nearestContainer!.ContentAtPath(path);
    } else {
      return rootContentContainer!.ContentAtPath(path);
    }
  }

  Path ConvertPathToRelative(Path globalPath) {
    // 1. Find last shared ancestor
    // 2. Drill up using ".." style (actually represented as "^")
    // 3. Re-build downward chain from common ancestor

    var ownPath = path!;

    int minPathLength = min(globalPath.length, ownPath.length);
    int lastSharedPathCompIndex = -1;

    for (int i = 0; i < minPathLength; ++i) {
      var ownComp = ownPath.getComponent(i);
      var otherComp = globalPath.getComponent(i);

      if (ownComp == otherComp) {
        lastSharedPathCompIndex = i;
      } else {
        break;
      }
    }

    // No shared path components, so just use global path
    if (lastSharedPathCompIndex == -1) return globalPath;

    int numUpwardsMoves = (ownPath.length - 1) - lastSharedPathCompIndex;

    var newPathComps = <PathComponent>[];

    for (int up = 0; up < numUpwardsMoves; ++up) {
      newPathComps.add(PathComponent.toParent());
    }

    for (int down = lastSharedPathCompIndex + 1;
        down < globalPath.length;
        ++down) {
      newPathComps.add(globalPath.getComponent(down)!);
    }

    var relativePath = Path.new2(newPathComps, relative: true);
    return relativePath;
  }

  String CompactPathString(Path otherPath) {
    String? globalPathStr;
    String? relativePathStr;
    if (otherPath.isRelative) {
      relativePathStr = otherPath.componentsString;
      globalPathStr = path!.pathByAppendingPath(otherPath).componentsString;
    } else {
      var relativePath = ConvertPathToRelative(otherPath);
      relativePathStr = relativePath.componentsString;
      globalPathStr = otherPath.componentsString;
    }

    if (relativePathStr.length < globalPathStr.length)
      return relativePathStr;
    else
      return globalPathStr;
  }

  Container? get rootContentContainer {
    RuntimeObject ancestor = this;
    while (ancestor.parent != null) {
      ancestor = ancestor.parent!;
    }
    return (ancestor is Container) ? ancestor : null;
  }

  RuntimeObject copy() => throw UnimplementedError();
}
