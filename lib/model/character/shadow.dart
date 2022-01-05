import 'god.dart';

class Shadow extends God{
  Shadow() : super(roleName: '影子') {
    super.actionMessage = "请选择你想繼承的對象。";
    super.actionConfirmMessage = "想繼承";
  }

  @override
  void action(Map<int, Player> seatNumToPlayer, int target) {}

  @override
  String toString() {
    return 'Shadow: 影子';
  }
}