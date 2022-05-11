import 'runtime_object.dart';

abstract class CommandType {
  static const NotSet = -1;
  static const EvalStart = 0;
  static const EvalOutput = 1;
  static const EvalEnd = 2;
  static const Duplicate = 3;
  static const PopEvaluatedValue = 4;
  static const PopFunction = 5;
  static const PopTunnel = 6;
  static const BeginString = 7;
  static const EndString = 8;
  static const NoOp = 9;
  static const ChoiceCount = 10;
  static const Turns = 11;
  static const TurnsSince = 12;
  static const ReadCount = 13;
  static const Random = 14;
  static const SeedRandom = 15;
  static const VisitIndex = 16;
  static const SequenceShuffleIndex = 17;
  static const StartThread = 18;
  static const Done = 19;
  static const End = 20;
  //----
  static const TOTAL_VALUES = 21;
}

class ControlCommand extends RuntimeObject {
  final int commandType;

  ControlCommand(this.commandType);

  @override
  RuntimeObject copy() => ControlCommand(commandType);

  @override
  String toString() => commandType.toString();
}
