// reviewed

class Stack<T> extends Iterable<T> {
  final List<T> _list = [];

  @override
  Iterator<T> get iterator => _list.reversed.iterator;

  void push(T obj) {
    _list.add(obj);
  }

  T pop() {
    return _list.removeLast();
  }
}
