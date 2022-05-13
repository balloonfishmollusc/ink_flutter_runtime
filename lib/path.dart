// reviewed

class PathComponent {
  final int index;
  final String? name;
  bool get isIndex => index >= 0;
  bool get isParent => name == Path.parentId;

  const PathComponent._({this.index = -1, this.name});

  static PathComponent new1(int index) {
    assert(index >= 0);
    return PathComponent._(index: index);
  }

  static PathComponent new2(String name) {
    assert(name.isNotEmpty);
    return PathComponent._(name: name);
  }

  static PathComponent ToParent() {
    return new2(Path.parentId);
  }

  @override
  String toString() => isIndex ? index.toString() : name!;

  @override
  int get hashCode => isIndex ? index : name!.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! PathComponent) return false;
    PathComponent otherComp = other;
    if (otherComp.isIndex == isIndex) {
      if (isIndex) {
        return index == otherComp.index;
      } else {
        return name == otherComp.name;
      }
    }
    return false;
  }
}

class Path {
  static const String parentId = "^";

  final List<PathComponent> _components = [];
  bool _isRelative = false;
  String? _componentsString;

  bool get isRelative => _isRelative;
  int get length => _components.length;

  PathComponent GetComponent(int index) {
    return _components[index];
  }

  PathComponent? getComponentSafe(int index) {
    if (index < 0 || index >= length) return null;
    return _components[index];
  }

  PathComponent? get head => getComponentSafe(0);
  PathComponent? get lastComponent => getComponentSafe(length - 1);

  Path get tail {
    if (_components.length >= 2) {
      List<PathComponent> tailComps = _components.sublist(1);
      return Path.new2(tailComps);
    } else {
      return Path.self;
    }
  }

  Path();

  Path.new1(PathComponent head, Path tail) {
    _components.add(head);
    _components.addAll(tail._components);
  }

  Path.new2(Iterable<PathComponent> components, {bool relative = false}) {
    _components.addAll(components);
    _isRelative = relative;
  }

  Path.new3(String? componentsString) {
    _setComponentsString(componentsString);
  }

  static Path get self => Path().._isRelative = true;

  Path PathByAppendingPath(Path pathToAppend) {
    Path p = Path();

    int upwardMoves = 0;
    for (int i = 0; i < pathToAppend._components.length; ++i) {
      if (pathToAppend._components[i].isParent) {
        upwardMoves++;
      } else {
        break;
      }
    }

    for (int i = 0; i < _components.length - upwardMoves; ++i) {
      p._components.add(_components[i]);
    }

    for (int i = upwardMoves; i < pathToAppend._components.length; ++i) {
      p._components.add(pathToAppend._components[i]);
    }

    return p;
  }

  Path PathByAppendingComponent(PathComponent c) {
    Path p = Path();
    p._components.addAll(_components);
    p._components.add(c);
    return p;
  }

  String get componentsString {
    if (_componentsString == null) {
      _componentsString = _components.join(".");
      if (isRelative) _componentsString = "." + _componentsString!;
    }
    return _componentsString!;
  }

  void _setComponentsString(String? value) {
    _components.clear();

    _componentsString = value;

    if (_componentsString?.isNotEmpty != true) return;

    if (_componentsString![0] == '.') {
      _isRelative = true;
      _componentsString = _componentsString!.substring(1);
    } else {
      _isRelative = false;
    }

    var componentStrings = _componentsString!.split('.');
    for (var str in componentStrings) {
      int? index = int.tryParse(str);
      if (index != null) {
        _components.add(PathComponent.new1(index));
      } else {
        _components.add(PathComponent.new2(str));
      }
    }
  }

  @override
  String toString() => componentsString;

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! Path) return false;
    Path otherPath = other;
    if (otherPath._components.length != _components.length) return false;
    if (otherPath.isRelative != isRelative) return false;

    for (int i = 0; i < length; i++) {
      if (otherPath._components[i] != _components[i]) return false;
    }
    return true;
  }
}
