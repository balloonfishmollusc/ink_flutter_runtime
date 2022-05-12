// reviewed

import 'call_stack.dart';
import 'runtime_object.dart';
import 'path.dart';

class Choice extends RuntimeObject {
  String? text;

  String get pathStringOnChoice => targetPath.toString();
  set pathStringOnChoice(String value) => targetPath = Path.new3(value);

  String? sourcePath;

  int index = 0;

  Path? targetPath;

  CallStackThread? threadAtGeneration;
  int originalThreadIndex = 0;

  bool isInvisibleDefault = false;
}
