import 'container.dart';
import 'runtime_object.dart';

class StatePatch {
  Map<String, RuntimeObject> get globals => _globals;
  Set<String> get changedVariables => _changedVariables;
  Map<Container, int> get visitCounts => _visitCounts;
  Map<Container, int> get turnIndices => _turnIndices;

  StatePatch(StatePatch? toCopy) {
    if (toCopy != null) {
      _globals = Map<String, RuntimeObject>.of(toCopy._globals);
      _changedVariables = Set<String>.of(toCopy._changedVariables);
      _visitCounts = Map<Container, int>.of(toCopy._visitCounts);
      _turnIndices = Map<Container, int>.of(toCopy._turnIndices);
    }
  }

  /*
        bool tryGetGlobal(String name, out RuntimeObject value)
        {
            return _globals.TryGetValue(name, out value);
        }

        bool tryGetVisitCount(Container container, out int count)
        {
            return _visitCounts.TryGetValue(container, out count);
        }

        bool tryGetTurnIndex(Container container, out int index)
        {
            return _turnIndices.TryGetValue(container, out index);
        }*/

  void setGlobal(String name, RuntimeObject value) {
    _globals[name] = value;
  }

  void addChangedVariable(String name) {
    _changedVariables.add(name);
  }

  void setVisitCount(Container container, int count) {
    _visitCounts[container] = count;
  }

  void setTurnIndex(Container container, int index) {
    _turnIndices[container] = index;
  }

  Map<String, RuntimeObject> _globals = <String, RuntimeObject>{};
  Set<String> _changedVariables = <String>{};
  Map<Container, int> _visitCounts = <Container, int>{};
  Map<Container, int> _turnIndices = <Container, int>{};
}
