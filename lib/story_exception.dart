// reviewed

class StoryException implements Exception {
  bool useEndLineNumber = false;

  final String message;

  StoryException(this.message);

  @override
  String toString() {
    return message;
  }
}
