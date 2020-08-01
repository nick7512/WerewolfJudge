import 'package:werewolfjudge/model/psychic.dart';
import 'package:werewolfjudge/resource/firestore_provider.dart';

import 'template.dart';
import 'role.dart';

export 'role.dart';

enum RoomStatus { seating, seated, ongoing, terminated }

const String roomNumberKey = 'roomNumber';

class Room {
  String hostUid;
  Template template;
  String roomNumber;
  RoomStatus roomStatus;

  ///seatNumber to Player
  Map<int, Player> players = {};

  ///Role to target
  Map<Type, int> actions;

  List<Map<Role, int>> rounds;

  int currentActionerIndex;

  bool hasPoison = false, hasAntidote = false;

  Role get currentActionRole => currentActionerIndex == template.actionOrder.length ? null : template.actionOrder[currentActionerIndex];

  bool get hunterStatus {
    var killedByWitch = actions[Witch];
    if (killedByWitch != null && killedByWitch < 0 && players[(killedByWitch + 1).abs()].role is Hunter) return false;
    return true;
  }

  bool get wolfKingStatus {
    var killedByWitch = actions[Witch];
    if (killedByWitch != null && killedByWitch < 0 && players[(killedByWitch + 1).abs()].role is WolfKing) return false;
    return true;
  }

  ///Whether or not the skill of the current actioner has been effected by nightmare.
  bool get currentActionerSkillStatus {
    if (template.rolesType.contains(Nightmare)) {
      var nightmaredIndex = actions[Nightmare];

      print("The nightmared index is $nightmaredIndex");
      print(currentActionerIndex);

      if (nightmaredIndex != null && players[nightmaredIndex].role.runtimeType == template.actionOrder[currentActionerIndex].runtimeType)
        return false;
      else
        return true;
    }

    if (actions[Nightmare] == currentActionerIndex) {
      return false;
    }

    return true;
  }

  String get lastNightInfo {
    var killedByWolf = actions[Wolf];
    var killedByWitch = (actions[Witch] ?? 1) < 0 ? -1 * actions[Witch] - 1 : null;
    var savedByWitch = (actions[Witch] ?? -1) > 0 ? actions[Witch] : null;
    var queenIndex =
        actions.containsKey(WolfQueen) ? players.values.singleWhere((element) => element.role is WolfQueen, orElse: () => null).seatNumber : null;
    var sleptWith = actions[WolfQueen];
    var guardedByGuard = actions[Guard];
    var moderatedByModerator = actions[Moderator];
    var nightWalker = actions[Celebrity];
    //var killedByWitcher = actions[Witcher];
    int firstExchanged, secondExchanged;
    if (actions.keys.contains(Magician) && actions[Magician] != -1) {
      firstExchanged = actions[Magician] % 100;
      secondExchanged = (actions[Magician] - firstExchanged) ~/ 100;
    }

    //尝试获取摄梦人号码
    var celebrityIndex =
        actions.containsKey(Celebrity) ? players.values.singleWhere((element) => element.role is Celebrity, orElse: () => null).seatNumber : null;

    Set<int> deaths = {};

    print("killedByWolf: $killedByWolf");
    print("killedByWitch: $killedByWitch");
    print("savedByWitch: $savedByWitch");
    print("queenIndex: $queenIndex");
    print("sleptWith: $sleptWith");
    print("firstExchanged: $firstExchanged");
    print("secondExchanged: $secondExchanged");

    //奶死
    if (savedByWitch != null && savedByWitch == guardedByGuard) {
      deaths.add(savedByWitch);
    }

    //没有被救或守
    if (killedByWolf != null && killedByWolf != -1 && killedByWolf != guardedByGuard && (savedByWitch == null || savedByWitch != killedByWolf)) {
      deaths.add(killedByWolf);
    }

    //毒死
    if (killedByWitch != null) {
      deaths.add(killedByWitch);
    }

    //如果狼美人死亡，被连的人殉情
    if (deaths.contains(queenIndex)) {
      deaths.add(sleptWith);
    }

    //摄梦人使死亡失效
    deaths.remove(nightWalker);

    //如果摄梦人死亡，则梦游者也死亡
    if (deaths.contains(celebrityIndex)) {
      deaths.add(nightWalker);
    }

//    if(killedByWitcher != null){
//      if(players[killedByWitcher].role is Wolf == false){
//        deaths.add()
//      }
//    }

    if (deaths.contains(firstExchanged) && deaths.contains(secondExchanged) == false) {
      deaths.remove(firstExchanged);
      deaths.add(secondExchanged);
    } else if (deaths.contains(firstExchanged) == false && deaths.contains(secondExchanged)) {
      deaths.remove(secondExchanged);
      deaths.add(firstExchanged);
    }

    if (deaths.isEmpty) {
      return "昨天晚上是平安夜。";
    }

    String info = "昨天晚上";
    for (var i in deaths) {
      info += "${i + 1}号, ";
    }

    info = info.substring(0, info.length - 2);
    info += "玩家死亡。";

    if (moderatedByModerator == nightWalker) moderatedByModerator = null;

    //禁票信息
    if (moderatedByModerator != null) {
      if (moderatedByModerator == -1)
        info += "\n无人被禁票";
      else
        info += "\n${moderatedByModerator + 1}号被禁票";
    }

    return info;
  }

  int get killedIndex => actions[Wolf] ?? -1;

  Room.create({this.hostUid, this.roomNumber, this.template}) : roomStatus = RoomStatus.seating;

  Room.from(
      {this.actions, this.hostUid, this.roomNumber, this.template, this.roomStatus, this.currentActionerIndex, this.hasAntidote, this.hasPoison});

  Room.fromMap(Map<String, dynamic> map) {
    this.roomNumber = map[roomNumberKey];
    this.actions = (map[actionsKey] as Map<int, int>).map((k, v) => MapEntry<Type, int>(Player.indexToRoleType(k), v));
    this.players = (map[actionsKey] as Map<int, Map>).map((k, v) => MapEntry<int, Player>(k, Player.fromMap(v)));
  }

  Map toMap() => {
        actionsKey: actions.map((key, value) => MapEntry<int, int>(Player.roleTypeToIndex(key), value)),
        players: players.map((key, value) => MapEntry<int, Map>(key, value.toMap())),
        roomNumberKey: roomNumber
      };

  void startGame() {
    FirestoreProvider.instance.startGame();
  }

  ///Take the seat number of target and return message if needed.
  String action(int target, {bool usePoison = false}) {
    if (currentActionRole is Seer) {
      if (actions.values.contains(Magician) && actions[Magician] != -1) {
        int first = actions[Magician] % 100;
        int second = (actions[Magician] - first) ~/ 100;

        if (target == first) {
          return players[second].role is Wolf ? "狼人" : "好人";
        } else if (target == second) {
          return players[first].role is Wolf ? "狼人" : "好人";
        }
      }

      return players[target].role is Wolf ? "狼人" : "好人";
    } else if (currentActionRole is Psychic)
      return players[target].role.roleName;
    else if (currentActionRole is WolfRobot)
      return players[target].role.roleName;
    else if (currentActionRole is Gargoyle)
      return players[target].role.roleName;
    else
      return null;
  }

  //Order: guard -> wolf -> wolf queen -> witch -> seer -> hunter
  void proceed(int target, {bool usePoison = true}) {
    //var currentActionRole = template.actionOrder[currentActionerIndex];

//    Player currentActionPlayer;
//
//    if (currentActionRole is Wolf == false) {
//      currentActionPlayer = players.values.singleWhere((player) => player.role.runtimeType == currentActionRole.runtimeType);
//    }

    FirestoreProvider.instance.performAction(currentActionRole, target, currentActionerIndex + 1, usePoison: usePoison);
  }
}
