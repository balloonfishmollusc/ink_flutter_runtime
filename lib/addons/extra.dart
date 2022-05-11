abstract class Struct {
  Struct clone();
}

T? tryCast<T>(dynamic obj) {
  if (obj is T) return obj;
  return null;
}

class Event {
  final int argsCount;
  List<Function> delegates = [];

  Event(this.argsCount);

  int get length => delegates.length;

  bool get isNotEmpty => delegates.isNotEmpty;

  void addListener(Function fn) => delegates.add(fn);

  void fire([List? args]) {
    assert((args == null && argsCount == 0) || args!.length == argsCount);
    for (var fn in delegates) {
      switch (argsCount) {
        case 0:
          fn.call();
          break;
        case 1:
          fn.call(args![0]);
          break;
        case 2:
          fn.call(args![0], args[1]);
          break;
        case 3:
          fn.call(args![0], args[1], args[2]);
          break;
        case 4:
          fn.call(args![0], args[1], args[2], args[3]);
          break;
      }
    }
  }
}
