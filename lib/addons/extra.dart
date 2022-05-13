// reviewed

import 'dart:collection';

abstract class Struct {
  Struct clone();
}

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
