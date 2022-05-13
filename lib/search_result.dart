// reviewed

import 'runtime_object.dart';
import 'container.dart';
import 'addons/extra.dart';

class SearchResult extends Struct {
  RuntimeObject? obj;
  bool approximate = false;
  RuntimeObject? get correctObj => approximate ? null : obj;
  Container? get container => obj?.csAs<Container>();

  @override
  Struct clone() {
    return SearchResult()
      ..obj = obj
      ..approximate = approximate;
  }
}
