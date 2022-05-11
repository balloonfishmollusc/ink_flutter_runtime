import 'runtime_object.dart';

class VariableAssignment extends RuntimeObject {
  final String? variableName;
  final bool isNewDeclaration;
  bool isGlobal = false;

  VariableAssignment([this.variableName, this.isNewDeclaration = false]);

  @override
  String toString() {
    return "VarAssign to $variableName";
  }
}
