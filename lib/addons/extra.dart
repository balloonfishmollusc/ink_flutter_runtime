// reviewed

import 'dart:collection';

abstract class Struct {
  Struct clone();
}

String stringExtJoin(String separator, List objects) {
  var sb = StringBuilder();

  var isFirst = true;
  for (var o in objects) {
    if (!isFirst) sb.add(separator);

    sb.add(o.toString());

    isFirst = false;
  }

  return sb.toString();
}

extension StringEx on String {
  String trimWhitespaces() {
    return trimEx({" ", "\t"});
  }

  String trimRightEx(Set<String> charSet) {
    if (length == 0) return "";

    const int startPos = 0;
    int endPos = length - 1;

    while (startPos <= endPos) {
      if (charSet.contains(this[endPos])) {
        endPos--;
      }
    }
    return substring(startPos, endPos - startPos + 1);
  }

  String trimEx(Set<String> charSet) {
    if (length == 0) return "";

    int startPos = 0;
    int endPos = length - 1;

    while (startPos <= endPos) {
      if (charSet.contains(this[startPos])) {
        startPos++;
      } else if (charSet.contains(this[endPos])) {
        endPos--;
      }
    }
    return substring(startPos, endPos - startPos + 1);
  }
}

class StringBuilder extends ListMixin<String> {
  final List<String> lst = <String>[];

  @override
  String toString() => lst.join();

  @override
  int get length => lst.length;

  @override
  String operator [](int index) {
    return lst[index];
  }

  @override
  void operator []=(int index, String value) {
    lst[index] = value;
  }

  @override
  set length(int newLength) {
    lst.length = newLength;
  }

  @override
  void add(String element) => lst.add(element);

  @override
  void addAll(Iterable<String> iterable) => lst.addAll(iterable);
}

extension CsObject on Object {
  T? csAs<T extends Object>() {
    if (this is T) return this as T;
    return null;
  }
}

class Event extends Iterable<Function> {
  final int argsCount;
  List<Function> delegates = [];

  Event(this.argsCount) {
    if (argsCount > 4) {
      throw Exception("Event arguments count should not be greater than 4");
    }
  }

  @override
  Iterator<Function> get iterator => delegates.iterator;

  void addListener(Function fn) => delegates.add(fn);

  void fire([List args = const []]) {
    if (args.length != argsCount) {
      throw Exception("Event arguments count mismatch.");
    }
    for (var fn in delegates) {
      switch (argsCount) {
        case 0:
          fn();
          break;
        case 1:
          fn(args[0]);
          break;
        case 2:
          fn(args[0], args[1]);
          break;
        case 3:
          fn(args[0], args[1], args[2]);
          break;
        case 4:
          fn(args[0], args[1], args[2], args[3]);
          break;
      }
    }
  }
}
