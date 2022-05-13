import 'dart:math';
import 'addons/extra.dart';

import 'addons/stack.dart';

import 'container.dart';
import 'i_named_content.dart';
import 'path.dart';
import 'debug_metadata.dart';
import 'search_result.dart';

class RuntimeObject {
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
  Path get path {
    if (_path == null) {
      if (parent == null) {
        _path = Path();
      } else {
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

    return _path!;
  }

  SearchResult ResolvePath(Path path) {
    if (path.isRelative) {
      Container? nearestContainer = csAs<Container>();
      if (nearestContainer == null) {
        assert(parent != null,
            "Can't resolve relative path because we don't have a parent");

        nearestContainer = parent!.csAs<Container>();
        assert(nearestContainer != null, "Expected parent to be a container");
        assert(path.GetComponent(0).isParent);
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

    var ownPath = path;

    int minPathLength = min(globalPath.length, ownPath.length);
    int lastSharedPathCompIndex = -1;

    for (int i = 0; i < minPathLength; ++i) {
      var ownComp = ownPath.GetComponent(i);
      var otherComp = globalPath.GetComponent(i);

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
      newPathComps.add(PathComponent.ToParent());
    }

    for (int down = lastSharedPathCompIndex + 1;
        down < globalPath.length;
        ++down) {
      newPathComps.add(globalPath.GetComponent(down));
    }

    var relativePath = Path.new2(newPathComps, relative: true);
    return relativePath;
  }

  String CompactPathString(Path otherPath) {
    String? globalPathStr;
    String? relativePathStr;
    if (otherPath.isRelative) {
      relativePathStr = otherPath.componentsString;
      globalPathStr = path.PathByAppendingPath(otherPath).componentsString;
    } else {
      var relativePath = ConvertPathToRelative(otherPath);
      relativePathStr = relativePath.componentsString;
      globalPathStr = otherPath.componentsString;
    }

    if (relativePathStr.length < globalPathStr.length) {
      return relativePathStr;
    } else {
      return globalPathStr;
    }
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
