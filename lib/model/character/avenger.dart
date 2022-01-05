import 'god.dart';

class Avenger extends God {
  Avenger() : super(roleName: '復仇者') {
    super.actionMessage = '你的陣營是';
    super.actionConfirmMessage = "猎杀";
  }
}
