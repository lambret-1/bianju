import '../models/custom_options.dart';
import '../models/project.dart';
import '../models/shot_block.dart';

/// 自定义选项管理，文档第十一章。
///
/// 可自定义：台词角色（仅无档案的临时角色名兜底）、环境音、背景音乐、
/// 镜头运动、光线氛围、节奏标签。支持新增、重命名、删除、排序；
/// 重命名与删除会同步已选用该值的分镜，避免出现「选项已删但分镜仍指向它」。
class CustomOptionsService {
  const CustomOptionsService();

  /// 新增选项；空值或重复值忽略
  Project addOption(Project project, OptionCategory category, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return project;
    final options = project.customOptions.optionsFor(category);
    if (options.contains(trimmed)) return project;
    return _writeOptions(project, category, <String>[...options, trimmed]);
  }

  /// 重命名选项，并同步已选用该值的分镜
  Project renameOption(
    Project project,
    OptionCategory category, {
    required String from,
    required String to,
  }) {
    final source = from.trim();
    final target = to.trim();
    if (source.isEmpty || target.isEmpty || source == target) return project;

    final options = project.customOptions.optionsFor(category);
    final index = options.indexOf(source);
    if (index < 0) return project;
    if (options.contains(target)) return project;

    final next = List<String>.of(options)..[index] = target;
    final shots = <ShotBlock>[
      for (final shot in project.shots)
        _fieldOf(shot, category) == source ? _withField(shot, category, target) : shot,
    ];
    return _touch(project.copyWith(
      shots: shots,
      customOptions: project.customOptions.withOptions(category, next),
    ));
  }

  /// 删除选项；已选用该值的分镜字段清空（导出时该字段自然不输出）
  Project removeOption(Project project, OptionCategory category, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return project;
    final options = project.customOptions.optionsFor(category);
    if (!options.contains(trimmed)) return project;

    final next = options.where((option) => option != trimmed).toList(growable: false);
    final shots = <ShotBlock>[
      for (final shot in project.shots)
        _fieldOf(shot, category) == trimmed ? _withField(shot, category, '') : shot,
    ];
    return _touch(project.copyWith(
      shots: shots,
      customOptions: project.customOptions.withOptions(category, next),
    ));
  }

  /// 排序选项（拖拽语义与 ReorderableListView 一致）
  Project reorderOption(Project project, OptionCategory category, int oldIndex, int newIndex) {
    final options = List<String>.of(project.customOptions.optionsFor(category));
    if (options.isEmpty || oldIndex < 0 || oldIndex >= options.length) return project;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, options.length - 1);
    final moved = options.removeAt(oldIndex);
    options.insert(target, moved);
    return _writeOptions(project, category, options);
  }

  /// 恢复某类别的默认选项库
  Project resetToDefaults(Project project, OptionCategory category) {
    return _writeOptions(project, category, _defaultsFor(category));
  }

  List<String> _defaultsFor(OptionCategory category) => switch (category) {
        OptionCategory.pace => List<String>.of(CustomOptions.defaultPaces),
        OptionCategory.cameraMove => List<String>.of(CustomOptions.defaultCameraMoves),
        OptionCategory.lightingMood => List<String>.of(CustomOptions.defaultLightingMoods),
        OptionCategory.ambientSound => List<String>.of(CustomOptions.defaultAmbientSounds),
        OptionCategory.bgm => List<String>.of(CustomOptions.defaultBgms),
        // 台词角色的结构化设定归角色库，这里只是临时角色名兜底，默认为空
        OptionCategory.character => const <String>[],
      };

  Project _writeOptions(Project project, OptionCategory category, List<String> values) {
    return _touch(project.copyWith(
      customOptions: project.customOptions.withOptions(category, values),
    ));
  }

  /// 读取分镜上与该类别对应的字段值
  String _fieldOf(ShotBlock shot, OptionCategory category) => switch (category) {
        OptionCategory.pace => shot.pace,
        OptionCategory.cameraMove => shot.cameraMove,
        OptionCategory.lightingMood => shot.lightingMood,
        OptionCategory.ambientSound => shot.ambientSound,
        OptionCategory.bgm => shot.bgm,
        OptionCategory.character => shot.dialogueCharacterName,
      };

  /// 写回分镜上与该类别对应的字段。
  /// 台词角色只处理「无档案的自定义兜底名」，绑定了角色库的分镜不受影响。
  ShotBlock _withField(ShotBlock shot, OptionCategory category, String value) {
    switch (category) {
      case OptionCategory.pace:
        return shot.copyWith(pace: value);
      case OptionCategory.cameraMove:
        return shot.copyWith(cameraMove: value);
      case OptionCategory.lightingMood:
        return shot.copyWith(lightingMood: value);
      case OptionCategory.ambientSound:
        return shot.copyWith(ambientSound: value);
      case OptionCategory.bgm:
        return shot.copyWith(bgm: value);
      case OptionCategory.character:
        if (shot.referencesCharacter) return shot;
        return shot.copyWith(dialogueCharacterName: value);
    }
  }

  Project _touch(Project project) => project.copyWith(updatedAt: DateTime.now());
}
