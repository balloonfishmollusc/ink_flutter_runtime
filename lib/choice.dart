import 'call_stack.dart';
import 'runtime_object.dart';
import 'path.dart';

class Choice extends RuntimeObject {
  /// <summary>
  /// The main text to presented to the player for this Choice.
  /// </summary>
  String? text;

  /// <summary>
  /// The target path that the Story should be diverted to if
  /// this Choice is chosen.
  /// </summary>

  String get pathStringOnChoice => targetPath.toString();
  set pathStringOnChoice(String value) => targetPath = Path.new3(value);

  /// <summary>
  /// Get the path to the original choice point - where was this choice defined in the story?
  /// </summary>
  /// <value>A dot separated path into the story data.</value>
  String? sourcePath;

  /// <summary>
  /// The original index into currentChoices list on the Story when
  /// this Choice was generated, for convenience.
  /// </summary>
  int index = 0;

  Path? targetPath;

  CallStackThread? threadAtGeneration;
  int originalThreadIndex = 0;

  bool isInvisibleDefault = false;
}
