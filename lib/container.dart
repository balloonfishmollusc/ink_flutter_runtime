import 'package:ink_flutter_runtime/i_named_content.dart';

import 'runtime_object.dart';
import 'path.dart';
import 'search_result.dart';
import 'value.dart';

class Container extends RuntimeObject implements INamedContent {
  @override
  bool get hasValidName => name?.isNotEmpty == true;

  @override
  String? get name => _name;

  set name(String? value) => _name = value;

  String? _name;

  final List<RuntimeObject> _content = [];
  List<RuntimeObject> get content => _content;
  set content(value) => addContent(value);

  final Map<String, INamedContent> namedContent = {};

  Map<String, RuntimeObject>? get namedOnlyContent {
    Map<String, RuntimeObject>? namedOnlyContentDict = {};
    for (var kvPair in namedContent.entries) {
      namedOnlyContentDict[kvPair.key] = kvPair.value as RuntimeObject;
    }

    for (var c in content) {
      if (c is INamedContent) {
        var named = c as INamedContent;
        if (named.hasValidName) {
          namedOnlyContentDict.remove(named.name);
        }
      }
    }

    if (namedOnlyContentDict.isEmpty) namedOnlyContentDict = null;

    return namedOnlyContentDict;
  }

  set namedOnlyContent(Map<String, RuntimeObject?>? value) {
    var existingNamedOnly = namedOnlyContent;
    if (existingNamedOnly != null) {
      for (var kvPair in existingNamedOnly.entries) {
        namedContent.remove(kvPair.key);
      }
    }

    if (value == null) return;

    for (var kvPair in value.entries) {
      if (kvPair.value is INamedContent) {
        var named = kvPair.value as INamedContent;
        addToNamedContentOnly(named);
      }
    }
  }

  bool visitsShouldBeCounted = false;
  bool turnIndexShouldBeCounted = false;
  bool countingAtStartOnly = false;

  int get countFlags {
    int flags = 0;
    if (visitsShouldBeCounted) flags |= CountFlags.Visits;
    if (turnIndexShouldBeCounted) flags |= CountFlags.Turns;
    if (countingAtStartOnly) flags |= CountFlags.CountStartOnly;

    // If we're only storing CountStartOnly, it serves no purpose,
    // since it's dependent on the other two to be used at all.
    // (e.g. for setting the fact that *if* a gather or choice's
    // content is counted, then is should only be counter at the start)
    // So this is just an optimisation for storage.
    if (flags == CountFlags.CountStartOnly) {
      flags = 0;
    }

    return flags;
  }

  set countFlags(int value) {
    int flag = value;
    if ((flag & CountFlags.Visits) > 0) visitsShouldBeCounted = true;
    if ((flag & CountFlags.Turns) > 0) turnIndexShouldBeCounted = true;
    if ((flag & CountFlags.CountStartOnly) > 0) countingAtStartOnly = true;
  }

  Path? _pathToFirstLeafContent;

  Path? get pathToFirstLeafContent {
    _pathToFirstLeafContent ??=
        path?.pathByAppendingPath(internalPathToFirstLeafContent!);
    return _pathToFirstLeafContent;
  }

  Path? get internalPathToFirstLeafContent {
    List<PathComponent> components = <PathComponent>[];
    Container? container = this;
    while (container != null) {
      if (container.content.isNotEmpty) {
        components.add(PathComponent.new1(0));
        container = container.content[0] as Container;
      }
    }
    return Path.new2(components);
  }

  void addContent(RuntimeObject contentObj) {
    content.add(contentObj);

    if (contentObj.parent != null) {
      throw Exception("content is already in " + contentObj.parent.toString());
    }

    contentObj.parent = this;

    tryAddNamedContent(contentObj);
  }

  void addContents(Iterable<RuntimeObject> contentList) {
    for (var c in contentList) {
      addContent(c);
    }
  }

  void insertContent(RuntimeObject contentObj, int index) {
    content.insert(index, contentObj);

    if (contentObj.parent != null) {
      throw Exception("content is already in " + contentObj.parent.toString());
    }

    contentObj.parent = this;

    tryAddNamedContent(contentObj);
  }

  void tryAddNamedContent(RuntimeObject contentObj) {
    if (contentObj is INamedContent) {
      var namedContentObj = contentObj as INamedContent;
      if (namedContentObj.hasValidName) {
        addToNamedContentOnly(namedContentObj);
      }
    }
  }

  void addToNamedContentOnly(INamedContent namedContentObj) {
    assert(namedContentObj is RuntimeObject,
        "Can only add Runtime.Objects to a Runtime.Container");
    var runtimeObj = namedContentObj as RuntimeObject;
    runtimeObj.parent = this;

    namedContent[namedContentObj.name!] = namedContentObj;
  }

  void addContentsOfContainer(Container otherContainer) {
    content.addAll(otherContainer.content);
    for (var obj in otherContainer.content) {
      obj.parent = this;
      tryAddNamedContent(obj);
    }
  }

  RuntimeObject? _contentWithPathComponent(PathComponent component) {
    if (component.isIndex) {
      if (component.index >= 0 && component.index < content.length) {
        return content[component.index];
      }

      // When path is out of range, quietly return nil
      // (useful as we step/increment forwards through content)
      else {
        return null;
      }
    } else if (component.isParent) {
      return parent;
    } else {
      INamedContent? foundContent = namedContent[component.name];
      if (foundContent != null) {
        return foundContent as RuntimeObject;
      } else {
        return null;
      }
    }
  }

  SearchResult contentAtPath(Path path,
      {int partialPathStart = 0, int partialPathLength = -1}) {
    if (partialPathLength == -1) partialPathLength = path.length;

    var result = SearchResult();
    result.approximate = false;

    Container? currentContainer = this;
    RuntimeObject currentObj = this;

    for (int i = partialPathStart; i < partialPathLength; ++i) {
      var comp = path.getComponent(i)!;

      // Path component was wrong type
      if (currentContainer == null) {
        result.approximate = true;
        break;
      }

      var foundObj = currentContainer._contentWithPathComponent(comp);

      // Couldn't resolve entire path?
      if (foundObj == null) {
        result.approximate = true;
        break;
      }

      currentObj = foundObj;
      currentContainer = foundObj as Container;
    }

    result.obj = currentObj;

    return result.clone() as SearchResult;
  }

  void buildStringOfHierarchy3(
      StringBuilder sb, int indentation, RuntimeObject? pointedObj) {
    var appendIndentation = () {
      const int spacesPerIndent = 4;
      for (int i = 0; i < spacesPerIndent * indentation; ++i) {
        sb.add(" ");
      }
    };

    appendIndentation();
    sb.add("[");

    if (hasValidName) {
      sb.add(" ($name)");
    }

    if (this == pointedObj) {
      sb.add("  <---");
    }

    sb.add("\n");

    indentation++;

    for (int i = 0; i < content.length; ++i) {
      var obj = content[i];

      if (obj is Container) {
        Container container = obj;
        container.buildStringOfHierarchy3(sb, indentation, pointedObj);
      } else {
        appendIndentation();
        if (obj is StringValue) {
          sb.add("\"");
          sb.add(obj.toString().replaceAll("\n", "\\n"));
          sb.add("\"");
        } else {
          sb.add(obj.toString());
        }
      }

      if (i != content.length - 1) {
        sb.add(",");
      }

      if (obj is! Container && obj == pointedObj) {
        sb.add("  <---");
      }

      sb.add("\n");
    }

    var onlyNamed = <String, INamedContent>{};

    for (var objKV in namedContent.entries) {
      if (content.contains(objKV.value as RuntimeObject)) {
        continue;
      } else {
        onlyNamed[objKV.key] = objKV.value;
      }
    }

    if (onlyNamed.isNotEmpty) {
      appendIndentation();
      sb.add("-- named: --\n");

      for (var objKV in onlyNamed.entries) {
        assert(objKV.value is Container, "Can only print out named Containers");
        var container = objKV.value as Container;
        container.buildStringOfHierarchy3(sb, indentation, pointedObj);

        sb.add("\n");
      }
    }

    indentation--;

    appendIndentation();
    sb.add("]");
  }

  String buildStringOfHierarchy() {
    var sb = StringBuilder();

    buildStringOfHierarchy3(sb, 0, null);

    return sb.toString();
  }
}

abstract class CountFlags {
  static const Visits = 1;
  static const Turns = 2;
  static const CountStartOnly = 4;
}
