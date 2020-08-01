import 'dart:math';
import 'package:werewolfjudge/util/list_extension.dart';

import 'hunter.dart';
import 'role.dart';
import 'villager.dart';
import 'wolf.dart';
import 'wolf_queen.dart';
import 'seer.dart';
import 'witch.dart';
import 'guard.dart';
import 'slacker.dart';
import 'nightmare.dart';
import 'gargoyle.dart';

export 'player.dart';

List<Role> allActionOrder = <Role>[
  Slacker(),
  Magician(),
  Celebrity(),
  Gargoyle(),
  Nightmare(),
  Guard(),
  Wolf(),
  WolfQueen(),
  Witch(),
  Seer(),
  Hunter(),
  Moderator(),
];

abstract class Template {
  final String name;
  final int numberOfPlayers;
  final List<Role> roles;
  final List<Role> actionOrder;

  Set<Type> get rolesType => roles.map((e) => e.runtimeType).toSet();

  Template({this.name, this.numberOfPlayers, this.roles, this.actionOrder});
}

//Order: guard -> wolf -> wolf queen -> witch -> seer -> hunter
@Deprecated("测试用")
class WolfQueenTemplate extends Template {
  WolfQueenTemplate.newGame()
      : super(name: '预女猎守狼美人12人局', numberOfPlayers: 12, roles: [
          Villager(),
          Villager(),
          Villager(),
          Villager(),
          Wolf(),
          Wolf(),
          Wolf(),
          WolfQueen(),
          Seer(),
          Hunter(),
          Witch(),
          Guard(),
        ], actionOrder: [
          Guard(),
          Wolf(),
          WolfQueen(),
          Witch(),
          Seer(),
          Hunter(),
        ]) {
    roles.shuffle(Random(DateTime.now().millisecondsSinceEpoch));
  }

  WolfQueenTemplate.from({List<dynamic> roles})
      : super(name: '预女猎守狼美人12人局', numberOfPlayers: roles.length, roles: roles.map((e) => e as Role).toList(), actionOrder: [
          Guard(),
          Wolf(),
          WolfQueen(),
          Witch(),
          Seer(),
          Hunter(),
        ]) {
    print('constructing ${this.roles}');
  }
}

class CustomTemplate extends Template {
  CustomTemplate.newGame({List<Role> roles})
      : super(name: '', numberOfPlayers: roles.length, roles: roles, actionOrder: allActionOrder.where((value) => roles.hasType(value)).toList()) {
    roles.shuffle(Random(DateTime.now().millisecondsSinceEpoch));
  }

  CustomTemplate.from({List<dynamic> roles})
      : super(
            name: '',
            numberOfPlayers: roles.length,
            roles: roles.map((e) => e as Role).toList(),
            actionOrder: allActionOrder.where((value) => roles.hasType(value)).toList());
}