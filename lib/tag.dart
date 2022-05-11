import 'runtime_object.dart';

class Tag extends RuntimeObject {
  final String text;

  Tag(this.text);

  @override
  String toString() {
    return "# " + text;
  }
}
