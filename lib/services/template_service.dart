import '../core/dialogue_duration_estimator.dart';
import '../models/project.dart';
import '../models/shot_block.dart';
import '../models/template.dart';

/// 套用模板的覆盖规则，文档 9.2「默认只填空字段，避免清空已填内容」
enum TemplateApplyMode {
  /// 只填空字段（默认）
  fillEmptyOnly,

  /// 覆盖全部字段
  overwriteAll,
}

/// 模板服务，文档第九章。
///
/// 内置模板是只读的（固定 id 前缀 `builtin-`），项目级模板存在项目 JSON 内，
/// 全局级模板由存储层单独维护后通过 [availableTemplates] 合并展示。
class TemplateService {
  const TemplateService();

  static final DateTime _epoch = DateTime.utc(2026);

  static final List<Template> _builtIn = <Template>[
    _builtInTemplate(
      id: 'builtin-dialogue',
      name: '对话',
      pace: '正常',
      cameraMove: '固定',
      lightingMood: '自然光',
      ambientSound: '室内安静',
      bgm: '温馨',
    ),
    _builtInTemplate(
      id: 'builtin-chase',
      name: '追逐',
      pace: '急促',
      cameraMove: '跟拍',
      lightingMood: '高对比',
      ambientSound: '脚步声',
      bgm: '紧张',
    ),
    _builtInTemplate(
      id: 'builtin-emotion',
      name: '情绪特写',
      pace: '慢',
      cameraMove: '推近',
      lightingMood: '柔光',
      ambientSound: '室内安静',
      bgm: '悲伤',
    ),
    _builtInTemplate(
      id: 'builtin-transition',
      name: '空镜转场',
      pace: '慢',
      cameraMove: '横移',
      lightingMood: '自然光',
      ambientSound: '风声',
      bgm: '轻快',
    ),
    _builtInTemplate(
      id: 'builtin-opening',
      name: '开场悬念',
      pace: '慢',
      cameraMove: '拉远',
      lightingMood: '低照度',
      ambientSound: '钟表滴答',
      bgm: '悬疑',
    ),
    _builtInTemplate(
      id: 'builtin-twist',
      name: '结尾反转',
      pace: '快',
      cameraMove: '推近',
      lightingMood: '硬光',
      ambientSound: '城市喧嚣',
      bgm: '激昂',
    ),
  ];

  /// 内置模板（文档 9.1）：对话、追逐、情绪特写、空镜转场、开场悬念、结尾反转
  static List<Template> builtInTemplates() => List<Template>.unmodifiable(_builtIn);

  static Template _builtInTemplate({
    required String id,
    required String name,
    required String pace,
    required String cameraMove,
    required String lightingMood,
    required String ambientSound,
    required String bgm,
  }) {
    return Template(
      id: id,
      name: name,
      scope: TemplateScope.global.name,
      snapshot: ShotBlock(
        id: id,
        orderIndex: 0,
        duration: 3,
        pace: pace,
        cameraMove: cameraMove,
        lightingMood: lightingMood,
        ambientSound: ambientSound,
        bgm: bgm,
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      createdAt: _epoch,
      updatedAt: _epoch,
    );
  }

  /// 界面可选的模板：内置 + 项目自定义 + 全局自定义
  List<Template> availableTemplates(
    Project project, {
    List<Template> globalTemplates = const <Template>[],
  }) {
    return <Template>[
      ...builtInTemplates(),
      ...project.templates,
      ...globalTemplates.where((template) => !template.isBuiltIn),
    ];
  }

  /// 套用模板到指定分镜（文档 9.2 / 9.3）
  ///
  /// 只作用于启用分镜；不改动时长、启用状态、锁定与时间标记；
  /// 台词角色一律留空（占位角色不写入角色库，避免污染项目角色数据）。
  Project applyTemplate(
    Project project, {
    required int shotIndex,
    required Template template,
    TemplateApplyMode mode = TemplateApplyMode.fillEmptyOnly,
  }) {
    if (shotIndex < 0 || shotIndex >= project.shots.length) return project;
    final target = project.shots[shotIndex];
    if (!target.enabled) return project;

    final merged = mode == TemplateApplyMode.overwriteAll
        ? _overwrite(target, template.snapshot, project)
        : _fillEmpty(target, template.snapshot, project);

    final shots = List<ShotBlock>.of(project.shots);
    shots[shotIndex] = merged;
    return _touch(project.copyWith(shots: shots));
  }

  /// 套用模板到全部空分镜（文档 9.2）
  Project applyToAllEmptyShots(
    Project project, {
    required Template template,
    TemplateApplyMode mode = TemplateApplyMode.fillEmptyOnly,
  }) {
    var result = project;
    for (var i = 0; i < result.shots.length; i++) {
      final shot = result.shots[i];
      if (!shot.enabled || shot.hasContent) continue;
      result = applyTemplate(result, shotIndex: i, template: template, mode: mode);
    }
    return result;
  }

  /// 把当前分镜保存为自定义模板（文档 9.2）
  Project saveShotAsTemplate(
    Project project, {
    required int shotIndex,
    required String name,
    TemplateScope scope = TemplateScope.project,
  }) {
    if (shotIndex < 0 || shotIndex >= project.shots.length) return project;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return project;

    final source = project.shots[shotIndex];
    final template = Template.create(
      name: trimmed,
      scope: scope,
      snapshot: source.copyWith(dialogueCharacterId: '', dialogueCharacterName: ''),
    );
    return _touch(project.copyWith(templates: <Template>[...project.templates, template]));
  }

  Project deleteTemplate(Project project, String templateId) {
    return _touch(project.copyWith(
      templates: project.templates
          .where((template) => template.id != templateId)
          .toList(growable: false),
    ));
  }

  Project renameTemplate(Project project, String templateId, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return project;
    return _touch(project.copyWith(
      templates: <Template>[
        for (final template in project.templates)
          template.id == templateId ? template.copyWith(name: trimmed) : template,
      ],
    ));
  }

  Project reorderTemplates(Project project, int oldIndex, int newIndex) {
    final templates = List<Template>.of(project.templates);
    if (templates.isEmpty || oldIndex < 0 || oldIndex >= templates.length) return project;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, templates.length - 1);
    final moved = templates.removeAt(oldIndex);
    templates.insert(target, moved);
    return _touch(project.copyWith(templates: templates));
  }

  // ------------------------------------------------------------------ 内部

  ShotBlock _fillEmpty(ShotBlock target, ShotBlock snapshot, Project project) {
    String pick(String current, String incoming) =>
        current.trim().isEmpty ? incoming : current;

    return _finalize(
      target.copyWith(
        pace: pick(target.pace, snapshot.pace),
        subjectAction: pick(target.subjectAction, snapshot.subjectAction),
        actionStart: pick(target.actionStart, snapshot.actionStart),
        actionDevelop: pick(target.actionDevelop, snapshot.actionDevelop),
        actionEnd: pick(target.actionEnd, snapshot.actionEnd),
        cameraMove: pick(target.cameraMove, snapshot.cameraMove),
        cameraMoveNote: pick(target.cameraMoveNote, snapshot.cameraMoveNote),
        backgroundChange: pick(target.backgroundChange, snapshot.backgroundChange),
        lightingMood: pick(target.lightingMood, snapshot.lightingMood),
        keepConsistent: pick(target.keepConsistent, snapshot.keepConsistent),
        dialogue: pick(target.dialogue, snapshot.dialogue),
        ambientSound: pick(target.ambientSound, snapshot.ambientSound),
        ambientSoundNote: pick(target.ambientSoundNote, snapshot.ambientSoundNote),
        bgm: pick(target.bgm, snapshot.bgm),
        bgmNote: pick(target.bgmNote, snapshot.bgmNote),
      ),
      project,
    );
  }

  ShotBlock _overwrite(ShotBlock target, ShotBlock snapshot, Project project) {
    return _finalize(
      target.copyWith(
        pace: snapshot.pace,
        subjectAction: snapshot.subjectAction,
        actionStart: snapshot.actionStart,
        actionDevelop: snapshot.actionDevelop,
        actionEnd: snapshot.actionEnd,
        cameraMove: snapshot.cameraMove,
        cameraMoveNote: snapshot.cameraMoveNote,
        backgroundChange: snapshot.backgroundChange,
        lightingMood: snapshot.lightingMood,
        keepConsistent: snapshot.keepConsistent,
        dialogue: snapshot.dialogue,
        ambientSound: snapshot.ambientSound,
        ambientSoundNote: snapshot.ambientSoundNote,
        bgm: snapshot.bgm,
        bgmNote: snapshot.bgmNote,
      ),
      project,
    );
  }

  /// 套用模板后的统一收尾：清空台词角色引用（文档 9.3），并按项目默认语速重算台词预估
  ShotBlock _finalize(ShotBlock shot, Project project) {
    return shot.copyWith(
      dialogueCharacterId: '',
      dialogueCharacterName: '',
      dialogueEstimatedDuration: DialogueDurationEstimator.estimate(
        shot.dialogue,
        speechRate: project.defaultSpeechRate,
      ),
    );
  }

  Project _touch(Project project) => project.copyWith(updatedAt: DateTime.now());
}

/// 模板来源判断
extension TemplateSource on Template {
  /// 是否为内置模板（固定 id 前缀，只读）
  bool get isBuiltIn => id.startsWith('builtin-');
}
