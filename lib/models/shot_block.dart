import '../core/constants.dart';
import '../core/json_utils.dart';

/// 单个分镜，文档 3.5 / 5 / 14.1 / 16.3。
///
/// 字段分三类（文档 14.1）：
/// - 自动生成：[orderIndex]、[timeMark]
/// - 数值输入：[duration]（滑块 + 数字输入 + [durationLocked] 锁定）
/// - 快捷选择 / 自由填写：其余字段
class ShotBlock {
  const ShotBlock({
    required this.id,
    required this.orderIndex,
    this.enabled = true,
    required this.duration,
    this.durationLocked = false,
    this.pace = '',
    this.timeMark = '',
    this.subjectAction = '',
    this.actionStart = '',
    this.actionDevelop = '',
    this.actionEnd = '',
    this.cameraMove = '',
    this.cameraMoveNote = '',
    this.backgroundChange = '',
    this.lightingMood = '',
    this.keepConsistent = '',
    this.dialogueCharacterId = '',
    this.dialogueCharacterName = '',
    this.dialogue = '',
    this.dialogueEstimatedDuration = 0,
    this.ambientSound = '',
    this.ambientSoundNote = '',
    this.bgm = '',
    this.bgmNote = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory ShotBlock.create({
    required int orderIndex,
    required double duration,
    bool enabled = true,
    bool durationLocked = false,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return ShotBlock(
      id: newId(),
      orderIndex: orderIndex,
      enabled: enabled,
      duration: duration,
      durationLocked: durationLocked,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory ShotBlock.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ShotBlock(
      id: jsonStr(json, 'id', newId()),
      orderIndex: jsonInt(json, 'orderIndex'),
      enabled: jsonBool(json, 'enabled', true),
      duration: jsonDouble(json, 'duration', AppConstants.minShotDuration),
      durationLocked: jsonBool(json, 'durationLocked'),
      pace: jsonStr(json, 'pace'),
      timeMark: jsonStr(json, 'timeMark'),
      subjectAction: jsonStr(json, 'subjectAction'),
      actionStart: jsonStr(json, 'actionStart'),
      actionDevelop: jsonStr(json, 'actionDevelop'),
      actionEnd: jsonStr(json, 'actionEnd'),
      cameraMove: jsonStr(json, 'cameraMove'),
      cameraMoveNote: jsonStr(json, 'cameraMoveNote'),
      backgroundChange: jsonStr(json, 'backgroundChange'),
      lightingMood: jsonStr(json, 'lightingMood'),
      keepConsistent: jsonStr(json, 'keepConsistent'),
      dialogueCharacterId: jsonStr(json, 'dialogueCharacterId'),
      dialogueCharacterName: jsonStr(json, 'dialogueCharacterName'),
      dialogue: jsonStr(json, 'dialogue'),
      dialogueEstimatedDuration: jsonDouble(json, 'dialogueEstimatedDuration'),
      ambientSound: jsonStr(json, 'ambientSound'),
      ambientSoundNote: jsonStr(json, 'ambientSoundNote'),
      bgm: jsonStr(json, 'bgm'),
      bgmNote: jsonStr(json, 'bgmNote'),
      createdAt: jsonDate(json, 'createdAt', now),
      updatedAt: jsonDate(json, 'updatedAt', now),
    );
  }

  final String id;
  final int orderIndex;

  /// 启用：参与时长计算、导出、一致性检查；禁用：保留内容但不参与（文档 5.2）
  final bool enabled;
  final double duration;

  /// 锁定后不参与自动分配（文档 6.2）
  final bool durationLocked;
  final String pace;

  /// 系统生成的时间标记，如 `00:04-00:08`；禁用分镜为空
  final String timeMark;
  final String subjectAction;
  final String actionStart;
  final String actionDevelop;
  final String actionEnd;
  final String cameraMove;
  final String cameraMoveNote;
  final String backgroundChange;
  final String lightingMood;
  final String keepConsistent;

  /// 引用角色库 Character.id；为空表示未选角或使用自定义兜底
  final String dialogueCharacterId;

  /// 冗余显示名，来自角色库或自定义兜底（文档 16.3）
  final String dialogueCharacterName;
  final String dialogue;

  /// 最近一次估算的台词时长（秒），随角色语速变化重算
  final double dialogueEstimatedDuration;
  final String ambientSound;
  final String ambientSoundNote;
  final String bgm;
  final String bgmNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 界面上显示的序号（从 1 开始）
  int get displayNumber => orderIndex + 1;

  /// 是否引用了角色库中的角色
  bool get referencesCharacter => dialogueCharacterId.trim().isNotEmpty;

  /// 是否只用了自定义兜底角色名（无档案）
  bool get usesCustomCharacterName =>
      dialogueCharacterName.trim().isNotEmpty && dialogueCharacterId.trim().isEmpty;

  /// 所有可填写内容字段；导出与「空分镜」判定都以它为准（文档 5.2 / 17.1）
  List<String> get contentFields => <String>[
        pace,
        subjectAction,
        actionStart,
        actionDevelop,
        actionEnd,
        cameraMove,
        cameraMoveNote,
        backgroundChange,
        lightingMood,
        keepConsistent,
        dialogueCharacterName,
        dialogue,
        ambientSound,
        ambientSoundNote,
        bgm,
        bgmNote,
      ];

  /// 是否填写过任何内容；全空分镜导出时自动忽略（文档 5.2）
  bool get hasContent => contentFields.any((value) => value.trim().isNotEmpty);

  /// 动作流程拼接：只拼接已填写的部分（文档 17.4）
  String get actionFlow {
    final parts = <String>[
      if (actionStart.trim().isNotEmpty) '开始—${actionStart.trim()}',
      if (actionDevelop.trim().isNotEmpty) '发展—${actionDevelop.trim()}',
      if (actionEnd.trim().isNotEmpty) '结束—${actionEnd.trim()}',
    ];
    return parts.join(' -> ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'orderIndex': orderIndex,
        'enabled': enabled,
        'duration': duration,
        'durationLocked': durationLocked,
        'pace': pace,
        'timeMark': timeMark,
        'subjectAction': subjectAction,
        'actionStart': actionStart,
        'actionDevelop': actionDevelop,
        'actionEnd': actionEnd,
        'cameraMove': cameraMove,
        'cameraMoveNote': cameraMoveNote,
        'backgroundChange': backgroundChange,
        'lightingMood': lightingMood,
        'keepConsistent': keepConsistent,
        'dialogueCharacterId': dialogueCharacterId,
        'dialogueCharacterName': dialogueCharacterName,
        'dialogue': dialogue,
        'dialogueEstimatedDuration': dialogueEstimatedDuration,
        'ambientSound': ambientSound,
        'ambientSoundNote': ambientSoundNote,
        'bgm': bgm,
        'bgmNote': bgmNote,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  ShotBlock copyWith({
    String? id,
    int? orderIndex,
    bool? enabled,
    double? duration,
    bool? durationLocked,
    String? pace,
    String? timeMark,
    String? subjectAction,
    String? actionStart,
    String? actionDevelop,
    String? actionEnd,
    String? cameraMove,
    String? cameraMoveNote,
    String? backgroundChange,
    String? lightingMood,
    String? keepConsistent,
    String? dialogueCharacterId,
    String? dialogueCharacterName,
    String? dialogue,
    double? dialogueEstimatedDuration,
    String? ambientSound,
    String? ambientSoundNote,
    String? bgm,
    String? bgmNote,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ShotBlock(
      id: id ?? this.id,
      orderIndex: orderIndex ?? this.orderIndex,
      enabled: enabled ?? this.enabled,
      duration: duration ?? this.duration,
      durationLocked: durationLocked ?? this.durationLocked,
      pace: pace ?? this.pace,
      timeMark: timeMark ?? this.timeMark,
      subjectAction: subjectAction ?? this.subjectAction,
      actionStart: actionStart ?? this.actionStart,
      actionDevelop: actionDevelop ?? this.actionDevelop,
      actionEnd: actionEnd ?? this.actionEnd,
      cameraMove: cameraMove ?? this.cameraMove,
      cameraMoveNote: cameraMoveNote ?? this.cameraMoveNote,
      backgroundChange: backgroundChange ?? this.backgroundChange,
      lightingMood: lightingMood ?? this.lightingMood,
      keepConsistent: keepConsistent ?? this.keepConsistent,
      dialogueCharacterId: dialogueCharacterId ?? this.dialogueCharacterId,
      dialogueCharacterName: dialogueCharacterName ?? this.dialogueCharacterName,
      dialogue: dialogue ?? this.dialogue,
      dialogueEstimatedDuration:
          dialogueEstimatedDuration ?? this.dialogueEstimatedDuration,
      ambientSound: ambientSound ?? this.ambientSound,
      ambientSoundNote: ambientSoundNote ?? this.ambientSoundNote,
      bgm: bgm ?? this.bgm,
      bgmNote: bgmNote ?? this.bgmNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 复制分镜：保留全部内容字段，生成新 id 并清空自动生成的时间标记（文档 5.1）
  ShotBlock duplicate({int? orderIndex, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return copyWith(
      id: newId(),
      orderIndex: orderIndex ?? this.orderIndex,
      timeMark: '',
      durationLocked: false,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  /// 把角色引用降级为自定义文本：保留台词与显示名，清掉 characterId（文档 4.3）
  ShotBlock downgradeCharacterReference() => copyWith(dialogueCharacterId: '');

  /// 同步角色库改名：只更新冗余显示名，引用 id 不变（文档 4.3）
  ShotBlock syncCharacterName(String newName) =>
      copyWith(dialogueCharacterName: newName);
}
