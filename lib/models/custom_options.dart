import '../core/json_utils.dart';

/// 自定义下拉选项库，文档第十一章 / 14.2。
///
/// 分项目级与全局默认级：项目级存在项目 JSON 内，全局级单独存一份默认值文件，
/// 新建项目时以全局值作为初始值。台词角色只保留「无档案的临时角色名」兜底，
/// 有档案的角色归角色库管理。
class CustomOptions {
  const CustomOptions({
    this.characters = const <String>[],
    this.ambientSounds = defaultAmbientSounds,
    this.bgms = defaultBgms,
    this.cameraMoves = defaultCameraMoves,
    this.lightingMoods = defaultLightingMoods,
    this.paces = defaultPaces,
  });

  factory CustomOptions.defaults() => const CustomOptions();

  factory CustomOptions.fromJson(Map<String, dynamic> json) {
    return CustomOptions(
      characters: jsonStrList(json, 'characters'),
      ambientSounds: _orDefault(jsonStrList(json, 'ambientSounds'), defaultAmbientSounds),
      bgms: _orDefault(jsonStrList(json, 'bgms'), defaultBgms),
      cameraMoves: _orDefault(jsonStrList(json, 'cameraMoves'), defaultCameraMoves),
      lightingMoods: _orDefault(jsonStrList(json, 'lightingMoods'), defaultLightingMoods),
      paces: _orDefault(jsonStrList(json, 'paces'), defaultPaces),
    );
  }

  // ------------------------------------------------------------- 默认选项库

  /// 节奏（文档 14.2）
  static const List<String> defaultPaces = <String>['慢', '正常', '快', '急促'];

  /// 镜头运动（文档 14.2）
  static const List<String> defaultCameraMoves = <String>[
    '固定', '推近', '拉远', '上摇', '下摇', '左摇', '右摇',
    '横移', '跟拍', '俯拍', '仰拍', '环绕',
  ];

  /// 光线氛围（文档 14.2）
  static const List<String> defaultLightingMoods = <String>[
    '自然光', '暖黄光', '冷蓝光', '逆光', '侧光', '顶光',
    '低照度', '高对比', '柔光', '硬光', '霓虹光', '烛光',
  ];

  /// 环境音（文档 14.2）
  static const List<String> defaultAmbientSounds = <String>[
    '无', '雨声', '风声', '雷声', '海浪', '鸟鸣', '车流', '脚步声',
    '钟表滴答', '城市喧嚣', '室内安静', '键盘敲击', '电话铃声', '自定义',
  ];

  /// 背景音乐（文档 14.2）
  static const List<String> defaultBgms = <String>[
    '无', '紧张', '悲伤', '温馨', '激昂', '悬疑', '轻快',
    '浪漫', '压抑', '史诗', '自定义',
  ];

  /// 建档角色时的初始角色建议（文档 14.2）
  static const List<String> suggestedCharacterNames = <String>[
    '男主', '女主', '男配', '女配', '旁白', '群演',
  ];

  /// 无档案的临时角色名（自定义兜底）
  final List<String> characters;
  final List<String> ambientSounds;
  final List<String> bgms;
  final List<String> cameraMoves;
  final List<String> lightingMoods;
  final List<String> paces;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'characters': characters,
        'ambientSounds': ambientSounds,
        'bgms': bgms,
        'cameraMoves': cameraMoves,
        'lightingMoods': lightingMoods,
        'paces': paces,
      };

  CustomOptions copyWith({
    List<String>? characters,
    List<String>? ambientSounds,
    List<String>? bgms,
    List<String>? cameraMoves,
    List<String>? lightingMoods,
    List<String>? paces,
  }) {
    return CustomOptions(
      characters: characters ?? this.characters,
      ambientSounds: ambientSounds ?? this.ambientSounds,
      bgms: bgms ?? this.bgms,
      cameraMoves: cameraMoves ?? this.cameraMoves,
      lightingMoods: lightingMoods ?? this.lightingMoods,
      paces: paces ?? this.paces,
    );
  }

  /// 按选项类别取列表，供界面统一渲染下拉
  List<String> optionsFor(OptionCategory category) => switch (category) {
        OptionCategory.character => characters,
        OptionCategory.ambientSound => ambientSounds,
        OptionCategory.bgm => bgms,
        OptionCategory.cameraMove => cameraMoves,
        OptionCategory.lightingMood => lightingMoods,
        OptionCategory.pace => paces,
      };

  /// 按选项类别写回列表（自定义选项管理：新增/重命名/删除/排序）
  CustomOptions withOptions(OptionCategory category, List<String> values) =>
      switch (category) {
        OptionCategory.character => copyWith(characters: values),
        OptionCategory.ambientSound => copyWith(ambientSounds: values),
        OptionCategory.bgm => copyWith(bgms: values),
        OptionCategory.cameraMove => copyWith(cameraMoves: values),
        OptionCategory.lightingMood => copyWith(lightingMoods: values),
        OptionCategory.pace => copyWith(paces: values),
      };

  static List<String> _orDefault(List<String> values, List<String> fallback) =>
      values.isEmpty ? List<String>.of(fallback) : values;
}

/// 可自定义的选项类别，文档第十一章
enum OptionCategory {
  character('台词角色'),
  ambientSound('环境音'),
  bgm('背景音乐'),
  cameraMove('镜头运动'),
  lightingMood('光线氛围'),
  pace('节奏');

  const OptionCategory(this.label);

  final String label;
}
