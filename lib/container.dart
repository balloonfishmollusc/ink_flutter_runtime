// reviewed

import 'i_named_content.dart';
import 'addons/extra.dart';
import 'runtime_object.dart';
import 'path.dart';
import 'search_result.dart';

class Container extends RuntimeObject implements INamedContent {
  @override
  bool get hasValidName => name?.isNotEmpty == true;

  @override
  String? get name => _name;
  set name(String? value) => _name = value;

  String? _name;

  final List<RuntimeObject> _content = [];
  List<RuntimeObject> get content => _content;
  set content(value) => AddContents(value);

  final Map<String, INamedContent> namedContent = {};

  Map<String, RuntimeObject>? get namedOnlyContent {
    Map<String, RuntimeObject>? namedOnlyContentDict = {};
    for (var kvPair in namedContent.entries) {
      namedOnlyContentDict[kvPair.key] = kvPair.value as RuntimeObject;
    }

    for (var c in content) {
      var named = c.csAs<INamedContent>();
      if (named != null && named.hasValidName) {
        namedOnlyContentDict.remove(named.name);
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
      var named = kvPair.value?.csAs<INamedContent>();
      if (named != null) AddToNamedContentOnly(named);
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

  Path? get internalPathToFirstLeafContent {
    List<PathComponent> components = [];
    Container? container = this;
    while (container != null) {
      if (container.content.isNotEmpty) {
        components.add(PathComponent.new1(0));
        container = container.content[0].csAs<Container>();
      }
    }
    return Path.new2(components);
  }

  void AddContent(RuntimeObject contentObj) {
    content.add(contentObj);

    if (contentObj.parent != null) {
      throw Exception("content is already in " + contentObj.parent.toString());
    }

    contentObj.parent = this;

    TryAddNamedContent(contentObj);
  }

  void AddContents(Iterable<RuntimeObject> contentList) {
    for (var c in contentList) {
      AddContent(c);
    }
  }

  void InsertContent(RuntimeObject contentObj, int index) {
    content.insert(index, contentObj);

    if (contentObj.parent != null) {
      throw Exception("content is already in " + contentObj.parent.toString());
    }

    contentObj.parent = this;

    TryAddNamedContent(contentObj);
  }

  void TryAddNamedContent(RuntimeObject contentObj) {
    var namedContentObj = contentObj.csAs<INamedContent>();
    if (namedContentObj != null && namedContentObj.hasValidName) {
      AddToNamedContentOnly(namedContentObj);
    }
  }

  void AddToNamedContentOnly(INamedContent namedContentObj) {
    assert(namedContentObj is RuntimeObject,
        "Can only add Runtime.Objects to a Runtime.Container");
    var runtimeObj = namedContentObj as RuntimeObject;
    runtimeObj.parent = this;

    namedContent[namedContentObj.name!] = namedContentObj;
  }

  void AddContentsOfContainer(Container otherContainer) {
    content.addAll(otherContainer.content);
    for (var obj in otherContainer.content) {
      obj.parent = this;
      TryAddNamedContent(obj);
    }
  }

  RuntimeObject? ContentWithPathComponent(PathComponent component) {
    if (component.isIndex) {
      if (component.index >= 0 && component.index < content.length) {
        return content[component.index];
      } else {
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

  SearchResult ContentAtPath(Path path,
      {int partialPathStart = 0, int partialPathLength = -1}) {
    if (partialPathLength == -1) partialPathLength = path.length;

    var result = SearchResult();
    result.approximate = false;

    Container? currentContainer = this;
    RuntimeObject currentObj = this;

    for (int i = partialPathStart; i < partialPathLength; ++i) {
      var comp = path.GetComponent(i);

      // Path component was wrong type
      if (currentContainer == null) {
        result.approximate = true;
        break;
      }

      var foundObj = currentContainer.ContentWithPathComponent(comp);

      // Couldn't resolve entire path?
      if (foundObj == null) {
        result.approximate = true;
        break;
      }

      currentObj = foundObj;
      currentContainer = foundObj.csAs<Container>();
    }

    result.obj = currentObj;

    return result;
  }
}

abstract class CountFlags {
  static const Visits = 1;
  static const Turns = 2;
  static const CountStartOnly = 4;
}
