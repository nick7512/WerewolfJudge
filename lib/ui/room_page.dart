import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:wakelock/wakelock.dart';
import 'package:werewolfjudge/model/actionable_mixin.dart';
import 'package:werewolfjudge/resource/firebase_auth_provider.dart';
import 'package:werewolfjudge/resource/firestore_provider.dart';
import 'package:werewolfjudge/resource/judge_audio_provider.dart';
import 'package:werewolfjudge/resource/role_image_provider.dart';
import 'package:werewolfjudge/resource/shared_prefs_provider.dart';
import 'package:werewolfjudge/ui/components/tap_down_wrapper.dart';

import 'components/black_trader_dialog.dart';

class RoomPage extends StatefulWidget {
  final String roomNumber;

  RoomPage({@required this.roomNumber})
      : assert(roomNumber != null && roomNumber.length == 4);

  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final audioPlayer = AudioPlayer();
  final endingDuration = Duration(seconds: 1);
  final scaffoldKey = GlobalKey<ScaffoldState>();

  ///Reserved for Magician.
  int anotherIndex;
  int mySeatNumber;
  Role myRole;
  bool imHost = false,
      imActioner = false,
      showWolves = false,
      hasShown = false,
      firstNightEnded = false,
      imMagician = false,
      luckySonPlayed = false,
      hasShownLuckySonDialog = false,
      hasPlayedLuckSon = false,
      artworkEnabled = false,
      mHasSkilledWolf = false,
      giftDialogShowed = false;
  Room mRoom;
  Role mRole;
  double gridHeight;

  ///天亮后的发言顺序
  String orderMsg;

  @override
  void initState() {
    if (!kIsWeb) Wakelock.enable();

    super.initState();

    artworkEnabled = SharedPreferencesProvider.instance.getArtworkEnabled();
  }

  @override
  void dispose() {
    Wakelock.disable();
    audioPlayer.stop();
    audioPlayer.dispose();
    super.dispose();
  }

  @Deprecated('Overwrite leading button is more customizable.')
  Future<bool> onWillPop() async {
    if (mRoom.roomStatus == RoomStatus.terminated) return true;

    Widget cancelButton = TextButton(
      child: Text("取消"),
      onPressed: () => Navigator.pop(context, false),
    );

    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context, true);
      },
    );

    AlertDialog alert = AlertDialog(
      title: Text("离开房间？"),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var myUid = FirebaseAuthProvider.instance.currentUser.uid;

    return WillPopScope(
        child: Scaffold(
            key: scaffoldKey,
            appBar: AppBar(
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios),
                  onPressed: () {
                    if (mRoom.roomStatus == RoomStatus.terminated) {
                      Navigator.popUntil(context, (route) => route.isFirst);
                      return null;
                    }

                    Widget cancelButton = TextButton(
                      child: Text("取消"),
                      onPressed: () => Navigator.pop(context),
                    );

                    Widget continueButton = TextButton(
                      child: Text("确定"),
                      onPressed: () {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                    );

                    AlertDialog alert = AlertDialog(
                      title: Text("离开房间？"),
                      actions: [
                        cancelButton,
                        continueButton,
                      ],
                    );

                    return showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return alert;
                      },
                    );
                  },
                ),
                title: Text('房间${widget.roomNumber}')),
            body: StreamBuilder(
              stream: FirestoreProvider.instance.fetchRoom(widget.roomNumber),
              builder: (_, AsyncSnapshot<Room> snapshot) {
                //TODO: Why need if
                if (snapshot.hasData) {
                  mRoom = snapshot.data;
                  gridHeight ??=
                      ((MediaQuery.of(context).size.width / 4) + 12) *
                          ((mRoom.template.roles.length / 4).ceil());
                  mHasSkilledWolf ??= mRoom.hasSkilledWolf;
                  //check user is host or not
                  imHost = isHostUid(myUid);

                  var players = mRoom.players;
                  var seatToPlayerMap = mRoom.players;
                  var status = mRoom.roomStatus;

                  for (var i in Iterable.generate(players.length)) {
                    if (players[i] != null && players[i].uid == myUid)
                      mySeatNumber = i;
                  }

                  //provide user role
                  if (status != RoomStatus.seating && mySeatNumber != null)
                    myRole = mRoom.template.roles[mySeatNumber];

                  if (status == RoomStatus.seating)
                    initialRoomStatus();
                  else if (status == RoomStatus.ongoing) {
                    debugPrint("天黑了");
                    if (mRoom.currentActionRole == null) {
                      firstNightEnded = true;
                      imActioner = false;
                      showWolves = false;
                    } else if (mRoom.currentActionRole is LuckySon) {
                      imActioner = false;

                      if (hasShownLuckySonDialog == false) {
                        hasShownLuckySonDialog = true;

                        WidgetsBinding.instance
                            .addPostFrameCallback((timeStamp) {
                          showLuckySonVerificationDialog();
                        });
                      }
                    } else if (myRole.runtimeType ==
                        mRoom.currentActionRole.runtimeType) {
                      //wolfking.runtimeType does not equal to wolf.runTimeType
                      imActioner = true;

                      if (hasShown == false) {
                        hasShown = true;

                        WidgetsBinding.instance
                            .addPostFrameCallback((timeStamp) {
                          Timer(Duration(seconds: 3), () {
                            if (mRoom.isSkillBlockByNightmare) {
                              if (myRole is Witch) {
                                showWitchActionDialog(mRoom.killedIndex);
                              } else if (myRole is Hunter) {
                                showHunterStatusDialog(
                                    myRole as ActionableMixin);
                              } else if (myRole is WolfBrother) {
                                showWolfBrotherActionMessage(
                                    myRole as ActionableMixin);
                              } else if (myRole is Avenger) {
                                //TODO
                                showAvengerStatusDialog(mRoom.killedIndex,
                                    myRole as ActionableMixin);
                              } else {
                                showActionMessage(myRole as ActionableMixin);
                              }
                            } else {
                              showActionForbiddenDialog();
                            }
                          });
                        });
                      }

                      showWolves = isShowingWolf();

                      //如果有与普通狼人见面的技能狼，普狼不能开刀
                      if (mRoom.currentActionRole.runtimeType == Wolf) {
                        if (mRoom.hasSkilledWolf &&
                            myRole.runtimeType == Wolf) {
                          imActioner = false;
                        } else if (mySeatNumber == mRoom.actionWolfIndex) {
                          imActioner = true;
                        } else {
                          imActioner = false;
                        }
                      }
                    } else if (isSpecialWolf(mRoom.currentActionRole)) {
                      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                        Timer(Duration(seconds: 3), () {
                          if (mRoom.isSkillBlockByNightmare)
                            showActionMessage(Wolf());
                          else
                            showActionForbiddenDialog();
                        });
                      });
                      imActioner = true;
                      showWolves = true;
                    } else {
                      imActioner = false;
                      showWolves = false;
                    }

                    print("firstNightEnded: $firstNightEnded");

                    if (imHost && mRoom.roomStatus != RoomStatus.terminated) {
                      if (firstNightEnded) {
                        if (mRoom.template.rolesType.contains(BlackTrader)) {
                          String endAudioPath =
                              JudgeAudioProvider.instance.night;
                          String audioPath =
                              JudgeAudioProvider.instance.nightEnd;

                          var timelapse = Duration(seconds: 5);

                          playAudio(endAudioPath);

                          Timer(timelapse, () {
                            playAudio(audioPath);
                            mRoom.terminate();
                          });
                        } else {
                          String endAudioPath = JudgeAudioProvider.instance
                              .getEndingAudio(mRoom.lastActionRole);
                          var timelapse = Duration(seconds: 5);
                          playAudio(endAudioPath);
                          Timer(timelapse, () {
                            playAudio(JudgeAudioProvider.instance.nightEnd);
                            mRoom.terminate();
                          });
                        }
                      } else {
                        String endAudioPath = JudgeAudioProvider.instance
                            .getEndingAudio(mRoom.lastActionRole);
                        String audioPath = JudgeAudioProvider.instance
                            .getBeginningAudio(mRoom.currentActionRole);

                        var timelapse = Duration(seconds: 5);

                        if (mRoom.template.rolesType.contains(BlackTrader) ==
                                false ||
                            (mRoom.template.rolesType.contains(BlackTrader) &&
                                hasPlayedLuckSon == false)) {
                          if (mRoom.currentActionRole is LuckySon)
                            hasPlayedLuckSon = true;

                          if (endAudioPath != null) {
                            playAudio(endAudioPath);
                          }

                          if (audioPath != null)
                            Timer(timelapse, () {
                              playAudio(audioPath);
                            });
                        }
                      }
                    }
                  } else if (mRoom.roomStatus == RoomStatus.terminated)
                    firstNightEnded = true;

                  String actionMessage;
                  var role = mRoom.currentActionRole;
                  if (imActioner) {
                    if (role.runtimeType == Wolf)
                      actionMessage = Wolf().actionMessage;
                    else
                      actionMessage = (myRole as ActionableMixin).actionMessage;
                  }

                  debugPrint("currentRole是房間的角色");
                  print("CRole is $role");
                  print("CRole.runtimeType is ${role.runtimeType}");
                  print("CRole is Wolf? ${role is Wolf}");
                  print(
                      "CRole.runtimeType is Wolf? ${role.runtimeType is Wolf}");
                  debugPrint("myRole是啥？？");
                  print("myRole is $myRole");
                  print("myRole.runtimeType is ${myRole.runtimeType}");

                  bool scrollable =
                      gridHeight > MediaQuery.of(context).size.height;

                  Widget child = Column(
                    children: <Widget>[
                      Padding(
                          padding: EdgeInsets.all(12),
                          child: Wrap(
                            children: <Widget>[
                              Text("房间信息：${mRoom.roomInfo}"),
                            ],
                          )),
                      Container(
                        height: gridHeight,
                        child: Stack(
                          children: <Widget>[
                            Positioned(
                              top: 20,
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: GridView.count(
                                shrinkWrap: true,
                                crossAxisCount: 4,
                                crossAxisSpacing: 0,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.0,
                                physics: NeverScrollableScrollPhysics(),
                                children: <Widget>[
                                  for (var i in Iterable.generate(
                                      mRoom.template.roles.length))
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: 12, horizontal: 6),
                                      child: Stack(
                                        children: <Widget>[
                                          if (seatToPlayerMap[i] != null)
                                            Positioned(
                                                bottom: 0,
                                                left: 0,
                                                right: 0,
                                                child: FutureBuilder(
                                                  future: FirestoreProvider
                                                      .instance
                                                      .fetchPlayerDisplayName(
                                                          seatToPlayerMap[i]
                                                              .uid),
                                                  builder: (_,
                                                      AsyncSnapshot<String>
                                                          userNameSnapshot) {
                                                    if (userNameSnapshot
                                                        .hasData) {
                                                      return Text(
                                                        userNameSnapshot.data,
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 1,
                                                        style: TextStyle(
                                                            fontSize: 13),
                                                      );
                                                    }
                                                    return Container();
                                                  },
                                                ))
                                        ],
                                      ),
                                    )
                                ],
                              ),
                            ),
                            Align(
                              alignment: Alignment.topCenter,
                              child: GridView.count(
                                shrinkWrap: true,
                                crossAxisCount: 4,
                                crossAxisSpacing: 0,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.0,
                                physics: NeverScrollableScrollPhysics(),
                                children: <Widget>[
                                  for (var i in Iterable.generate(
                                      mRoom.template.roles.length))
                                    Padding(
                                      padding: EdgeInsets.all(12),
                                      child: TapDownWrapper(
                                        child: Material(
                                          color: (isNeedMarkPosition(i))
                                              ? Colors.red
                                              : Colors.orange,
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(16)),
                                          elevation: 8,
                                          child: Stack(
                                            children: <Widget>[
                                              if (seatToPlayerMap[i] != null)
                                                Positioned.fill(
                                                  child: FutureBuilder(
                                                    future: FirestoreProvider
                                                        .instance
                                                        .getAvatar(
                                                            seatToPlayerMap[i]
                                                                .uid),
                                                    builder: (_,
                                                        AsyncSnapshot<String>
                                                            urlSnapshot) {
                                                      Widget avatar =
                                                          Container();
                                                      if (urlSnapshot.hasData) {
                                                        var url =
                                                            urlSnapshot.data;
                                                        avatar = FadeInImage
                                                            .memoryNetwork(
                                                          placeholder:
                                                              kTransparentImage,
                                                          image: url,
                                                          fit: BoxFit.cover,
                                                          width: 26,
                                                          height: 26,
                                                        );
                                                      } else {
                                                        if (!kIsWeb) {
                                                          String rawSvg =
                                                              Jdenticon.toSvg(
                                                                  seatToPlayerMap[
                                                                          i]
                                                                      .uid);
                                                          avatar =
                                                              SvgPicture.string(
                                                            rawSvg,
                                                            fit: BoxFit.cover,
                                                            height: 26,
                                                            width: 26,
                                                          );
                                                        }
                                                      }

                                                      return Stack(
                                                        alignment:
                                                            Alignment.center,
                                                        children: <Widget>[
                                                          Positioned.fill(
                                                              child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        16),
                                                            child: Container(
                                                                color: Colors
                                                                    .white),
                                                          )),
                                                          Positioned.fill(
                                                              child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        16),
                                                            child: avatar,
                                                          )),
                                                          Positioned.fill(
                                                              child: ClipRRect(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              16),
                                                                  child:
                                                                      ImageFiltered(
                                                                    imageFilter: ImageFilter.blur(
                                                                        sigmaX:
                                                                            0,
                                                                        sigmaY:
                                                                            0),
                                                                    child: Container(
                                                                        decoration: BoxDecoration(
                                                                            color: (isNeedMarkPosition(i))
                                                                                ? Colors.red.shade400.withOpacity(0.8)
                                                                                : Colors.grey.shade200.withOpacity(0.4)),
                                                                        child: Container()),
                                                                  ))),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ),
                                              Container(
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                      left: 12, top: 12),
                                                  child: Text(
                                                      (i + 1).toString(),
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ),
                                                decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.all(
                                                            Radius.circular(
                                                                16))),
                                              ),
                                              if (mySeatNumber == i)
                                                Align(
                                                  alignment:
                                                      Alignment.bottomRight,
                                                  child: Container(
                                                    child: Padding(
                                                      padding: EdgeInsets.only(
                                                          right: 8, bottom: 8),
                                                      child: Icon(
                                                          Icons.event_seat),
                                                    ),
                                                    decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.all(
                                                                Radius.circular(
                                                                    16))),
                                                  ),
                                                ),
                                              Positioned.fill(
                                                child: InkWell(
                                                  splashColor:
                                                      Colors.orangeAccent,
                                                  borderRadius:
                                                      BorderRadius.all(
                                                          Radius.circular(16)),
                                                  child: Container(
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        onTap: () => onSeatTapped(i),
                                      ),
                                    )
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (scrollable == false) Spacer(),
                      if (imActioner)
                        Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(actionMessage)),
                      if (mRoom.currentActionRole is LuckySon)
                        Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text("请确认自己是否是幸运儿")),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: buildPadding(children: [
                          if (mRoom.currentActionRole is LuckySon &&
                              giftDialogShowed == false)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('查看礼物'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  if (giftDialogShowed == false)
                                    showGiftDialog();
                                },
                              ),
                            ),
                          if (imHost && mRoom.roomStatus == RoomStatus.seating)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('准备看牌'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  if (players.values
                                          .where((element) => element != null)
                                          .length !=
                                      mRoom.template.numberOfPlayers) {
                                    showNotAllSeatedDialog();
                                  } else {
                                    showFlipRoleCardDialog();
                                  }
                                },
                              ),
                            ),
                          if (imHost && mRoom.roomStatus == RoomStatus.seated)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('开始游戏'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  showStartGameDialog();
                                },
                              ),
                            ),
                          if (imActioner &&
                              myRole is! Hunter &&
                              myRole is! BlackTrader &&
                              myRole is! WolfRobot)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('不使用技能'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  showActionConfirmDialog(-1);
                                },
                              ),
                            ),
                          // 第一晚結束 加查看死亡信息Button給host
                          if (imHost && firstNightEnded)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('查看昨晚信息'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  showLastNightConfirmDialog();
                                },
                              ),
                            ),
                          // enable所有人查看身份button
                          if (mRoom.roomStatus != RoomStatus.seating &&
                              mySeatNumber != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('查看身份'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  showRoleCardDialog();
                                },
                              ),
                            ),
                          //第一晚結束 加重新开始button給host
                          if (imHost && firstNightEnded)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('重新开始'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).primaryColor,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  showRestartConfirmDialog();
                                },
                              ),
                            ),
                          //人沒坐滿 disable查看身份button
                          if (mRoom.roomStatus == RoomStatus.seating &&
                              mySeatNumber != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: ElevatedButton(
                                child: Text('查看身份'),
                                style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    shape: StadiumBorder()),
                                onPressed: () {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text('等待房主确认所有人已入座'),
                                    action: SnackBarAction(
                                        label: '好',
                                        onPressed: () =>
                                            ScaffoldMessenger.of(context)
                                                .hideCurrentSnackBar()),
                                  ));
                                },
                              ),
                            ),
                        ]),
                      ),
                      SizedBox(height: 12)
                    ],
                  );

                  return scrollable
                      ? SingleChildScrollView(child: child)
                      : child;
                }

                return Center(
                  child: Text('无'),
                );
              },
            )),
        onWillPop: () => Future.value(false));
  }

  //TODO ??
  bool isNeedMarkPosition(i) {
    return (showWolves &&
            mRoom.players[i].role is Wolf &&
            mRoom.players[i].role.runtimeType != WolfRobot &&
            mRoom.players[i].role.runtimeType != Gargoyle ||
        ((anotherIndex ?? -1) == i));
  }

  List<Widget> buildPadding({List<Widget> children}) {
    for (int i = 1; i < children.length; i += 2)
      children.insert(i, SizedBox(width: 12));
    return children;
  }

  bool isShowingWolf() {
    return myRole is Wolf &&
        myRole is Nightmare == false &&
        myRole is Gargoyle == false &&
        myRole is HiddenWolf == false &&
        myRole is WolfRobot == false &&
        myRole is WolfBrother == false;
  }

  bool isSpecialWolf(Role role) {
    return role is Wolf && myRole is WolfKing ||
        myRole is WolfQueen ||
        myRole is Nightmare ||
        myRole is WolfBrother ||
        myRole is BloodMoon;
  }

  bool isHostUid(String myUid) {
    if (myUid == mRoom.hostUid) return true;
    return false;
  }

  void initialRoomStatus() {
    imActioner = false;
    showWolves = false;
    hasShown = false;
    firstNightEnded = false;
    imMagician = false;
    luckySonPlayed = false;
    hasShownLuckySonDialog = false;
    hasPlayedLuckSon = false;
    mHasSkilledWolf = false;
    giftDialogShowed = false;
  }

  void onSeatTapped(int index) {
    if (mRoom.roomStatus == RoomStatus.seating) {
      if (imHost == false && index == mySeatNumber)
        showLeaveSeatDialog(index);
      else
        showEnterSeatDialog(index);
    } else if (imActioner) {
      if (mRoom.currentActionRole is Magician && anotherIndex == null) {
        setState(() {
          anotherIndex = index;
        });
      } else if (mRoom.currentActionRole is BlackTrader) {
        if (index != mySeatNumber) showBlackTraderActionDialog(index);
      } else {
        showActionConfirmDialog(index);
      }
    }
  }

  void showEnterSeatDialog(int index) {
    // set up the buttons
    Widget cancelButton = TextButton(
      child: Text("取消"),
      onPressed: () => Navigator.pop(context),
    );
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        FirestoreProvider.instance
            .takeSeat(widget.roomNumber, index, mySeatNumber)
            .then((result) {
          Navigator.pop(context);

          if (result == -1) showConflictDialog(index);
        });
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("入座"),
      content: Text("确定在${index + 1}号位入座?"),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showLeaveSeatDialog(int index) {
    // set up the buttons
    Widget cancelButton = TextButton(
      child: Text("取消"),
      onPressed: () => Navigator.pop(context),
    );

    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        mySeatNumber = null;

        FirestoreProvider.instance
            .leaveSeat(widget.roomNumber, index)
            .then((_) => Navigator.pop(context));
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("离席"),
      content: Text("确定离开${index + 1}号?"),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showConflictDialog(int index) {
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () => Navigator.pop(context),
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("${index + 1}号座已被占用"),
      content: Text("请选择其他位置。"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showActionResultDialog(int index, String msg) {
    Widget continueButton = TextButton(
        child: Text("确定"),
        onPressed: () {
          Navigator.pop(context);

          Timer(endingDuration, () => mRoom.proceed(index));
        });

    AlertDialog alert = AlertDialog(
      title: Text("${index + 1}号是$msg。"),
      actions: [
        continueButton,
      ],
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showBlackTraderActionDialog(int giftedIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BlackTraderDialog(
            index: giftedIndex,
            onCancel: () => Navigator.pop(context),
            onContinue: (Type giftedType) {
              Navigator.pop(context);
              Timer(endingDuration,
                  () => mRoom.proceed(giftedIndex, giftedByOther: giftedType));
            });
      },
    );
  }

  void showWitchActionDialog(int killedIndex) {
    Widget cancelButton = TextButton(
      child: Text("不救助"),
      onPressed: () {
        Navigator.pop(context);
        showWitchNextStepDialog();
      },
    );
    Widget continueButton = TextButton(
      child: Text(
        "救助",
        style: TextStyle(
            color: killedIndex == mySeatNumber ? Colors.grey : Colors.orange),
      ),
      onPressed: () {
        if (killedIndex == mySeatNumber) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('女巫无法自救'),
            action: SnackBarAction(
                label: '惨',
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar()),
          ));
        } else {
          Navigator.pop(context);
          Timer(endingDuration,
              () => mRoom.proceed(killedIndex, usePoison: false));
        }
      },
    );

    ///狼队空刀，无人倒台
    if (killedIndex == -1) {
      continueButton = TextButton(
        child: Text(
          "好",
          style: TextStyle(
              color: killedIndex == mySeatNumber ? Colors.grey : Colors.orange),
        ),
        onPressed: () => Navigator.pop(context),
      );
    }

    AlertDialog alert = AlertDialog(
      title: Text(killedIndex == -1 ? "昨夜无人倒台" : "昨夜倒台玩家为${killedIndex + 1}号。"),
      content: Text(killedIndex == -1 ? "" : "是否救助?"),
      actions: [
        if (killedIndex != -1) cancelButton,
        continueButton,
      ],
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///在女巫选择不救助后，提示女巫下一步操作，即是否使用毒药
  void showWitchNextStepDialog() {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () => Navigator.pop(context),
    );

    AlertDialog alert = AlertDialog(
      title: Text("请选择是否使用毒药。"),
      content: Text("点击玩家头像使用毒药，如不使用毒药，请点击下方「不使用技能」"),
      actions: [
        continueButton,
      ],
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showActionConfirmDialog(int index) {
    Widget cancelButton = TextButton(
        child: Text("取消"),
        onPressed: () {
          anotherIndex = null;
          Navigator.pop(context);
        });
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);

        //如果index为-1，则视为不发动技能
        if (index == -1) {
          Timer(endingDuration, () => mRoom.proceed(null));
          return;
        }

        var msg = mRoom.action(index);
        if (msg != null) {
          if (mRoom.currentActionRole is Shadow)
            showShadowStatusDialog(msg);
          else
            showActionResultDialog(index, msg);
        } else if (mRoom.currentActionRole is Magician) {
          var target = anotherIndex + index * 100;

          anotherIndex = null;

          Timer(endingDuration, () => mRoom.proceed(target));
        } else
          Timer(endingDuration, () => mRoom.proceed(index));
      },
    );

    String msg = "";
    var role = mRoom.currentActionRole;
    if (index == -1) {
      msg = "确定不发动技能吗？";
    } else if (role.runtimeType == Wolf) {
      msg = "确定${Wolf().actionConfirmMessage}${index + 1}号玩家?";
    } else {
      msg =
          "确定${(myRole as ActionableMixin).actionConfirmMessage}${index + 1}号${anotherIndex == null ? "" : "和${anotherIndex + 1}号玩家"}?";
    }

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text(index == -1 ? "不发动技能" : "使用技能"),
      content: Text(msg),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///Confirm to see the last night information.
  void showLastNightConfirmDialog() {
    Widget cancelButton = TextButton(
      child: Text("取消"),
      onPressed: () => Navigator.pop(context),
    );

    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);
        showLastNightInfoDialog();
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("确定查看昨夜信息？"),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///Confirm to see the last night information.
  void showLastNightInfoDialog() {
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("昨夜信息"),
      content: Text(mRoom.lastNightInfo),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///Display the role card.
  void showRoleCardDialog() {
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      backgroundColor: Colors.black,
      title: Text(
        "你的底牌是：",
        style: TextStyle(color: Colors.white),
      ),
      content: this.artworkEnabled
          ? Container(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Image.asset(RoleImageProvider.instance[myRole],
                      height: 300, fit: BoxFit.fitHeight),
                  Text(
                    myRole.roleName,
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : Text(
              myRole.roleName,
              style: TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///Allowing everybody to see their role.
  void showFlipRoleCardDialog() {
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);

        FirestoreProvider.instance.prepare();
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("允许看牌？"),
      content: Text("所有座位已被占用。"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///Start the game.
  void showStartGameDialog() {
    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);

        playAudio(JudgeAudioProvider.instance.night);

        Timer(Duration(seconds: 8), () => mRoom.startGame());
        //FirestoreProvider.instance.startGame();
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("开始游戏？"),
      content: Text("请将您的手机音量调整到最大。"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///Confirm to see the last night information.
  void showRestartConfirmDialog() {
    Widget cancelButton = TextButton(
      child: Text("取消"),
      onPressed: () => Navigator.pop(context),
    );

    Widget continueButton = TextButton(
      child: Text("确定"),
      onPressed: () {
        Navigator.pop(context);
        this.mRoom.restart();
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("重新开始游戏？"),
      content: Text("使用相同板子开始新一局游戏。"),
      actions: [
        cancelButton,
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  ///If not all seated, then game cannot be started.
  void showNotAllSeatedDialog() {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () => Navigator.pop(context),
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("无法开始游戏"),
      content: Text("有座位尚未被占用。"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showActionMessage(ActionableMixin actionableMixin) {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () => Navigator.pop(context),
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text(actionableMixin.actionMessage),
      content: Text(""),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showActionForbiddenDialog() {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () {
        Navigator.pop(context);

        if (imActioner) Timer(endingDuration, () => mRoom.proceed(null));
      },
    );

    String title = '你的技能已被封锁', msg = '点击"好"后请闭眼';
    if (myRole is Wolf) {
      title = '狼队的技能已被封锁';
      if (imActioner)
        msg = '请先讨论战术再点击"好"';
      else
        msg = '';
    }

    AlertDialog alert = AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showWolfBrotherActionMessage(ActionableMixin actionableMixin) {
    Widget continueButton = TextButton(
        child: Text("结束互认"),
        onPressed: () {
          Navigator.pop(context);
          //playEndingAudio();
          mRoom.proceed(null);
        });

    AlertDialog alert = AlertDialog(
      title: Text(actionableMixin.actionMessage),
      content: Text(""),
      actions: [
        continueButton,
      ],
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showHunterStatusDialog(ActionableMixin actionableMixin) {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () {
        Navigator.pop(context);
        Timer(endingDuration, () => mRoom.proceed(null));
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text(actionableMixin.actionMessage),
      content: Text(mRoom.hunterStatus ? "可以发动" : "不可发动"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showWolfKingStatusDialog(ActionableMixin actionableMixin) {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () {
        Navigator.pop(context);

        Timer(endingDuration, () => mRoom.proceed(null));
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text(actionableMixin.actionMessage),
      content: Text(mRoom.wolfKingStatus ? "可以发动" : "不可发动"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  //TODO
  void showShadowStatusDialog(String message) {
    Widget continueButton = TextButton(
      child: Text(message),
      onPressed: () => Navigator.pop(context),
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("是否在復仇者回合一同睜眼"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showAvengerStatusDialog(
      int killedIndex, ActionableMixin actionableMixin) {
    var msg;
    var number = mRoom.shadowSeatNumber;
    if (mRoom.avengerSide == 0)
      msg = "好人復仇者";
    else if (mRoom.avengerSide == 1)
      msg = "狼人復仇者";
    else
      msg = "與$number號影子為第三方";

    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () {
        Navigator.pop(context);
        showAvengerNextStepDialog();
      },
    );

    AlertDialog alert = AlertDialog(
      title: Text(actionableMixin.actionMessage),
      content: Text(msg),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showAvengerNextStepDialog() {
    var isKilled = mRoom.isAvengerBeKilled;
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () {
        Navigator.pop(context);
        if (!isKilled) mRoom.proceed(null);
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text(isKilled ? "昨夜倒台玩家为${mySeatNumber + 1}号。" : "無法使用技能"),
      content: Text(isKilled ? "点击玩家头像使用技能，如不使用技能，请点击下方「不使用技能」" : ""),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showLuckySonVerificationDialog() {
    Widget continueButton = TextButton(
      child: Text("好"),
      onPressed: () {
        Navigator.pop(context);
      },
    );

    // set up the AlertDialog
    AlertDialog alert = AlertDialog(
      title: Text("请确认自己是否是幸运儿"),
      actions: [
        continueButton,
      ],
    );

    // show the dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  void showGiftDialog() {
    Widget continueButton = TextButton(
      child: Text("确认"),
      onPressed: () {
        Navigator.pop(context);

        mRoom.checkInForLuckySonVerifications(mySeatNumber);

        giftDialogShowed = true;
      },
    );

    AlertDialog alert = AlertDialog(
      title: Text(mySeatNumber == mRoom.luckySonIndex ? "你收到了礼物" : "你没有收到礼物"),
      content: Text(mySeatNumber == mRoom.luckySonIndex ? mRoom.giftInfo : ''),
      actions: [
        continueButton,
      ],
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  //音頻
  void playAudio(String audioPath) async {
    print("The audio path is $audioPath");

    if (this.mounted) {
      var tempDir = await getTemporaryDirectory();
      var tempPath = tempDir.path + '/' + audioPath.replaceFirst('/', '_');
      File file = File(tempPath);
      var audioFile = await rootBundle.load('assets/' + audioPath);
      file
          .writeAsBytes(audioFile.buffer.asUint8List())
          .whenComplete(() => audioPlayer.play(tempPath));
    }
  }
}
