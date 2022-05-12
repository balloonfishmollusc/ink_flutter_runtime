// reviewed

import 'container.dart';
import 'runtime_object.dart';

class StatePatch {
  StatePatch(StatePatch? toCopy) {
    if (toCopy != null) {
      globals.addAll(Map.of(toCopy.globals));
      changedVariables.addAll(Set.of(toCopy.changedVariables));
      visitCounts.addAll(Map.of(toCopy.visitCounts));
      turnIndices.addAll(Map.of(toCopy.turnIndices));
    }
  }

  final Map<String, RuntimeObject> globals = <String, RuntimeObject>{};
  final Set<String> changedVariables = <String>{};
  final Map<Container, int> visitCounts = <Container, int>{};
  final Map<Container, int> turnIndices = <Container, int>{};
}
