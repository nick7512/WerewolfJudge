import 'actionable_mixin.dart';
import 'role.dart';

export 'wolfQueen.dart';
export 'wolfKing.dart';

class Wolf extends Role with ActionableMixin {
  final String roleName;

  Wolf({String roleName})
      : roleName = roleName ?? '狼人',
        super(roleName: '狼人'){
    super.actionMessage = '请选择猎杀对象。';
    super.actionConfirmMessage = "猎杀";
    super.actionResult = '';
  }
}
