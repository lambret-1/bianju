import '../core/json_utils.dart';

/// 一致性检查维度，文档 10.1
enum ConsistencyIssueType {
  role('角色称呼'),
  costume('服装'),
  prop('道具'),
  feature('外貌特征'),
  light('光线'),
  time('时间'),
  ambient('环境音'),
  bgm('背景音乐');

  const ConsistencyIssueType(this.label);

  final String label;

  static ConsistencyIssueType fromName(String? value) {
    for (final type in ConsistencyIssueType.values) {
      if (type.name == value) return type;
    }
    return ConsistencyIssueType.role;
  }
}

/// 问题级别，文档第十三章：错误禁止导出，警告允许导出但提示风险，提示不影响导出
enum IssueLevel {
  error('错误'),
  warning('警告'),
  info('提示');

  const IssueLevel(this.label);

  final String label;

  static IssueLevel fromName(String? value) {
    for (final level in IssueLevel.values) {
      if (level.name == value) return level;
    }
    return IssueLevel.info;
  }
}

/// 一条一致性冲突，文档 10.2 / 16.4
class ConsistencyIssue {
  const ConsistencyIssue({
    required this.type,
    required this.level,
    this.shotOrders = const <int>[],
    this.characterId = '',
    required this.message,
    this.suggestion = '',
    this.ignored = false,
    this.acknowledged = false,
  });

  factory ConsistencyIssue.fromJson(Map<String, dynamic> json) {
    return ConsistencyIssue(
      type: ConsistencyIssueType.fromName(jsonStr(json, 'type')),
      level: IssueLevel.fromName(jsonStr(json, 'level')),
      shotOrders: List<int>.from(
        (json['shotOrders'] as List?)?.whereType<num>().map((e) => e.toInt()) ??
            const <int>[],
      ),
      characterId: jsonStr(json, 'characterId'),
      message: jsonStr(json, 'message'),
      suggestion: jsonStr(json, 'suggestion'),
      ignored: jsonBool(json, 'ignored'),
      acknowledged: jsonBool(json, 'acknowledged'),
    );
  }

  final ConsistencyIssueType type;
  final IssueLevel level;

  /// 冲突涉及的分镜编号（从 1 开始，便于界面「定位分镜 N」）
  final List<int> shotOrders;

  /// 冲突涉及的角色 id，可空
  final String characterId;
  final String message;

  /// 处理建议，如「确认是否为换装场景。」
  final String suggestion;

  /// 用户选择忽略后不再计入未处理冲突
  final bool ignored;

  /// 用户已确认（如确认是换装场景）
  final bool acknowledged;

  /// 是否仍属于「未处理」冲突（校验中心的提示项依据，文档第十三章）
  bool get isPending => !ignored && !acknowledged;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'level': level.name,
        'shotOrders': shotOrders,
        'characterId': characterId,
        'message': message,
        'suggestion': suggestion,
        'ignored': ignored,
        'acknowledged': acknowledged,
      };

  ConsistencyIssue copyWith({
    ConsistencyIssueType? type,
    IssueLevel? level,
    List<int>? shotOrders,
    String? characterId,
    String? message,
    String? suggestion,
    bool? ignored,
    bool? acknowledged,
  }) {
    return ConsistencyIssue(
      type: type ?? this.type,
      level: level ?? this.level,
      shotOrders: shotOrders ?? this.shotOrders,
      characterId: characterId ?? this.characterId,
      message: message ?? this.message,
      suggestion: suggestion ?? this.suggestion,
      ignored: ignored ?? this.ignored,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }
}

/// 一致性检查开关，文档 10.1 的八个维度均可单独关闭。
///
/// 说明：开发文档 16.1 的 `Project` 引用了 `ConsistencyRules` 但未给出定义，
/// 这里按 10.1 的检查维度补齐为八个开关，并与 `ConsistencyIssue` 同文件维护，
/// 以保持文档第十八章 models/ 六文件的目录结构不变。
class ConsistencyRules {
  const ConsistencyRules({
    this.checkRole = true,
    this.checkCostume = true,
    this.checkProp = true,
    this.checkFeature = true,
    this.checkLight = true,
    this.checkTime = true,
    this.checkAmbient = true,
    this.checkBgm = true,
  });

  factory ConsistencyRules.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return const ConsistencyRules();
    return ConsistencyRules(
      checkRole: jsonBool(json, 'checkRole', true),
      checkCostume: jsonBool(json, 'checkCostume', true),
      checkProp: jsonBool(json, 'checkProp', true),
      checkFeature: jsonBool(json, 'checkFeature', true),
      checkLight: jsonBool(json, 'checkLight', true),
      checkTime: jsonBool(json, 'checkTime', true),
      checkAmbient: jsonBool(json, 'checkAmbient', true),
      checkBgm: jsonBool(json, 'checkBgm', true),
    );
  }

  final bool checkRole;
  final bool checkCostume;
  final bool checkProp;
  final bool checkFeature;
  final bool checkLight;
  final bool checkTime;
  final bool checkAmbient;
  final bool checkBgm;

  /// 某维度是否启用
  bool isEnabled(ConsistencyIssueType type) => switch (type) {
        ConsistencyIssueType.role => checkRole,
        ConsistencyIssueType.costume => checkCostume,
        ConsistencyIssueType.prop => checkProp,
        ConsistencyIssueType.feature => checkFeature,
        ConsistencyIssueType.light => checkLight,
        ConsistencyIssueType.time => checkTime,
        ConsistencyIssueType.ambient => checkAmbient,
        ConsistencyIssueType.bgm => checkBgm,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'checkRole': checkRole,
        'checkCostume': checkCostume,
        'checkProp': checkProp,
        'checkFeature': checkFeature,
        'checkLight': checkLight,
        'checkTime': checkTime,
        'checkAmbient': checkAmbient,
        'checkBgm': checkBgm,
      };

  ConsistencyRules copyWith({
    bool? checkRole,
    bool? checkCostume,
    bool? checkProp,
    bool? checkFeature,
    bool? checkLight,
    bool? checkTime,
    bool? checkAmbient,
    bool? checkBgm,
  }) {
    return ConsistencyRules(
      checkRole: checkRole ?? this.checkRole,
      checkCostume: checkCostume ?? this.checkCostume,
      checkProp: checkProp ?? this.checkProp,
      checkFeature: checkFeature ?? this.checkFeature,
      checkLight: checkLight ?? this.checkLight,
      checkTime: checkTime ?? this.checkTime,
      checkAmbient: checkAmbient ?? this.checkAmbient,
      checkBgm: checkBgm ?? this.checkBgm,
    );
  }
}
