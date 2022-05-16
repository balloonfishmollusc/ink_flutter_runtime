// reviewed

import 'runtime_object.dart';
import 'container.dart';
import 'addons/extra.dart';

class SearchResult {
  final RuntimeObject? obj;
  final bool approximate;
  RuntimeObject? get correctObj => approximate ? null : obj;
  Container? get container => obj?.csAs<Container>();

  SearchResult({this.obj, this.approximate = false});

  SearchResult withObj(RuntimeObject? obj) =>
      SearchResult(obj: obj, approximate: approximate);

  SearchResult withApprox(bool approximate) =>
      SearchResult(obj: obj, approximate: approximate);
}
