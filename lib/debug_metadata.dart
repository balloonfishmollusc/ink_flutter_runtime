// reviewed

import 'dart:math';

class DebugMetadata {
  int startLineNumber = 0;
  int endLineNumber = 0;
  int startCharacterNumber = 0;
  int endCharacterNumber = 0;
  String? fileName;
  String? sourceName;

  DebugMetadata Merge(DebugMetadata dm) {
    var newDebugMetadata = DebugMetadata();

    newDebugMetadata.fileName = fileName;
    newDebugMetadata.sourceName = sourceName;

    if (startLineNumber < dm.startLineNumber) {
      newDebugMetadata.startLineNumber = startLineNumber;
      newDebugMetadata.startCharacterNumber = startCharacterNumber;
    } else if (startLineNumber > dm.startLineNumber) {
      newDebugMetadata.startLineNumber = dm.startLineNumber;
      newDebugMetadata.startCharacterNumber = dm.startCharacterNumber;
    } else {
      newDebugMetadata.startLineNumber = startLineNumber;
      newDebugMetadata.startCharacterNumber =
          min(startCharacterNumber, dm.startCharacterNumber);
    }

    if (endLineNumber > dm.endLineNumber) {
      newDebugMetadata.endLineNumber = endLineNumber;
      newDebugMetadata.endCharacterNumber = endCharacterNumber;
    } else if (endLineNumber < dm.endLineNumber) {
      newDebugMetadata.endLineNumber = dm.endLineNumber;
      newDebugMetadata.endCharacterNumber = dm.endCharacterNumber;
    } else {
      newDebugMetadata.endLineNumber = endLineNumber;
      newDebugMetadata.endCharacterNumber =
          max(endCharacterNumber, dm.endCharacterNumber);
    }

    return newDebugMetadata;
  }

  @override
  String toString() {
    if (fileName != null) {
      return "line $startLineNumber of $fileName";
    } else {
      return "line $startLineNumber";
    }
  }
}
