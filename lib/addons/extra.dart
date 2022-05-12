// reviewed

abstract class Struct {
  Struct clone();
}

T? tryCast<T extends Object>(dynamic obj) {
  if (obj is T) return obj;
  return null;
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
          fn.call();
          break;
        case 1:
          fn.call(args[0]);
          break;
        case 2:
          fn.call(args[0], args[1]);
          break;
        case 3:
          fn.call(args[0], args[1], args[2]);
          break;
        case 4:
          fn.call(args[0], args[1], args[2], args[3]);
          break;
      }
    }
  }
}
