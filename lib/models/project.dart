import '../core/constants.dart';
import '../core/duration_calculator.dart';
import '../core/json_utils.dart';
import '../core/time_utils.dart';
import 'character.dart';
import 'consistency_issue.dart';
import 'custom_options.dart';
import 'shot_block.dart';
import 'template.dart';

/// 项目（一部短片），文档 16.1。
///
/// 项目是本地存储与导出的最小单位：包含分镜列表、角色库、模板、
/// 自定义选项与一致性检查开关。
class Project {
  const Project({
    required this.id,
    required this.title,
    required this.totalDuration,
    this.defaultSpeechRate = AppConstants.defaultSpeechRate,
    this.exportFormat = defaultExportFormatName,
    this.schemaVersion = AppConstants.currentSchemaVersion,
    required this.createdAt,
    required this.updatedAt,
    required this.shots,
    this.characters = const <Character>[],
    this.templates = const <Template>[],
    this.customOptions = const CustomOptions(),
    this.consistencyRules = const ConsistencyRules(),
  });

  /// 默认导出格式名（Markdown）
  static const String defaultExportFormatName = 'markdown';

  /// 标题为空时的回落显示名
  static const String fallbackTitle = '未命名短片';

  factory Project.create({
    required String title,
    double totalDuration = AppConstants.defaultTotalDuration,
    int shotCount = AppConstants.defaultShotCount,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    final total = totalDuration
        .clamp(AppConstants.minTotalDuration, AppConstants.maxTotalDuration)
        .toDouble();
    final count = shotCount < 0 ? 0 : shotCount;

    final placeholders = <ShotBlock>[
      for (var i = 0; i < count; i++)
        ShotBlock.create(
          orderIndex: i,
          duration: AppConstants.minShotDuration,
          createdAt: now,
        ),
    ];
    final shots = TimeUtils.assignTimeMarks(
      DurationCalculator.distributeEvenly(placeholders, total),
    );

    return Project(
      id: newId(),
      title: title.trim().isEmpty ? fallbackTitle : title.trim(),
      totalDuration: TimeUtils.round1(total),
      createdAt: now,
      updatedAt: now,
      shots: shots,
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final title = jsonStr(json, 'title').trim();
    return Project(
      id: jsonStr(json, 'id', newId()),
      title: title.isEmpty ? fallbackTitle : title,
      totalDuration: jsonDouble(json, 'totalDuration', AppConstants.defaultTotalDuration),
      defaultSpeechRate: jsonDouble(json, 'defaultSpeechRate', AppConstants.defaultSpeechRate),
      exportFormat: jsonStr(json, 'exportFormat', defaultExportFormatName),
      schemaVersion: jsonInt(json, 'schemaVersion', AppConstants.currentSchemaVersion),
      createdAt: jsonDate(json, 'createdAt', now),
      updatedAt: jsonDate(json, 'updatedAt', now),
      shots: jsonMapList(json, 'shots').map(ShotBlock.fromJson).toList(),
      characters: jsonMapList(json, 'characters').map(Character.fromJson).toList(),
      templates: jsonMapList(json, 'templates').map(Template.fromJson).toList(),
      customOptions: CustomOptions.fromJson(jsonMap(json, 'customOptions')),
      consistencyRules: ConsistencyRules.fromJson(jsonMap(json, 'consistencyRules')),
    );
  }

  final String id;
  final String title;

  /// 总时长（秒），默认 15
  final double totalDuration;

  /// 项目默认语速（字/分钟），角色未设语速时回落使用
  final double defaultSpeechRate;
  final String exportFormat;
  final int schemaVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ShotBlock> shots;

  /// 角色库（项目级）
  final List<Character> characters;
  final List<Template> templates;
  final CustomOptions customOptions;
  final ConsistencyRules consistencyRules;

  ExportFormat get exportFormatValue => ExportFormat.fromName(exportFormat);

  int get shotCount => shots.length;

  /// 启用的分镜（参与时长计算、导出与一致性检查）
  List<ShotBlock> get enabledShots =>
      shots.where((shot) => shot.enabled).toList(growable: false);

  /// 有内容且启用的分镜，导出时只输出这些（文档 17.1）
  List<ShotBlock> get exportableShots =>
      shots.where((shot) => shot.enabled && shot.hasContent).toList(growable: false);

  double get usedDuration => DurationCalculator.used(shots);

  double get remainingDuration => DurationCalculator.remaining(totalDuration, shots);

  bool get isDurationBalanced => DurationCalculator.isBalanced(totalDuration, shots);

  /// 台词预估总时长（按各分镜所选角色的语速）
  double get dialogueEstimatedTotal => DurationCalculator.dialogueTotal(
        shots,
        defaultSpeechRate: defaultSpeechRate,
        speechRateByCharacterId: speechRateByCharacterId,
      );

  /// 角色 id → 语速，供台词估算与校验使用
  Map<String, double> get speechRateByCharacterId => <String, double>{
        for (final character in characters) character.id: character.speechRate,
      };

  Character? characterById(String? id) {
    if (id == null || id.trim().isEmpty) return null;
    for (final character in characters) {
      if (character.id == id) return character;
    }
    return null;
  }

  /// 被分镜引用到的角色 id（按引用出现顺序去重）
  List<String> get referencedCharacterIds {
    final ids = <String>[];
    for (final shot in shots) {
      final id = shot.dialogueCharacterId.trim();
      if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  /// 从未被引用的角色（校验中心的提示项，文档第十三章）
  List<Character> get unreferencedCharacters {
    final referenced = referencedCharacterIds.toSet();
    return characters.where((c) => !referenced.contains(c.id)).toList(growable: false);
  }

  /// 引用了已失效角色 id 的分镜（校验中心的错误项）
  List<ShotBlock> get shotsWithBrokenCharacterReference {
    final known = characters.map((c) => c.id).toSet();
    return shots
        .where((shot) =>
            shot.dialogueCharacterId.trim().isNotEmpty &&
            !known.contains(shot.dialogueCharacterId))
        .toList(growable: false);
  }

  /// 某个角色被哪些分镜引用（文档 4.2「被引用：分镜 1 / 2 / 4」）
  List<int> shotNumbersReferencing(String characterId) => <int>[
        for (final shot in shots)
          if (shot.dialogueCharacterId == characterId) shot.displayNumber,
      ];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'totalDuration': totalDuration,
        'defaultSpeechRate': defaultSpeechRate,
        'exportFormat': exportFormat,
        'schemaVersion': schemaVersion,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'shots': shots.map((shot) => shot.toJson()).toList(),
        'characters': characters.map((character) => character.toJson()).toList(),
        'templates': templates.map((template) => template.toJson()).toList(),
        'customOptions': customOptions.toJson(),
        'consistencyRules': consistencyRules.toJson(),
      };

  Project copyWith({
    String? id,
    String? title,
    double? totalDuration,
    double? defaultSpeechRate,
    String? exportFormat,
    int? schemaVersion,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ShotBlock>? shots,
    List<Character>? characters,
    List<Template>? templates,
    CustomOptions? customOptions,
    ConsistencyRules? consistencyRules,
  }) {
    return Project(
      id: id ?? this.id,
      title: title ?? this.title,
      totalDuration: totalDuration ?? this.totalDuration,
      defaultSpeechRate: defaultSpeechRate ?? this.defaultSpeechRate,
      exportFormat: exportFormat ?? this.exportFormat,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shots: shots ?? this.shots,
      characters: characters ?? this.characters,
      templates: templates ?? this.templates,
      customOptions: customOptions ?? this.customOptions,
      consistencyRules: consistencyRules ?? this.consistencyRules,
    );
  }

  /// 重排时间轴（分镜增删、排序、改时长后调用），文档第十五章
  Project withRebuiltTimeline({DateTime? updatedAt}) => copyWith(
        shots: TimeUtils.assignTimeMarks(shots),
        updatedAt: updatedAt ?? DateTime.now(),
      );

  /// 复制项目：生成副本，角色库与模板一并复制，且不跨项目串引用（文档第十二章）
  Project duplicate({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final idMap = <String, String>{};
    final copiedCharacters = <Character>[];
    for (final character in characters) {
      final copy = character.duplicate(now: timestamp);
      idMap[character.id] = copy.id;
      copiedCharacters.add(copy);
    }

    final copiedShots = <ShotBlock>[
      for (final shot in shots)
        shot.copyWith(
          id: newId(),
          dialogueCharacterId: idMap[shot.dialogueCharacterId] ?? '',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
    ];

    final copiedTemplates = <Template>[
      for (final template in templates)
        template.copyWith(
          id: newId(),
          snapshot: template.snapshot.copyWith(
            id: newId(),
            dialogueCharacterId: idMap[template.snapshot.dialogueCharacterId] ?? '',
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
    ];

    return Project(
      id: newId(),
      title: '$title${AppConstants.duplicateSuffix}',
      totalDuration: totalDuration,
      defaultSpeechRate: defaultSpeechRate,
      exportFormat: exportFormat,
      schemaVersion: schemaVersion,
      createdAt: timestamp,
      updatedAt: timestamp,
      shots: TimeUtils.assignTimeMarks(copiedShots),
      characters: copiedCharacters,
      templates: copiedTemplates,
      customOptions: customOptions,
      consistencyRules: consistencyRules,
    );
  }
}
