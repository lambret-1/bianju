import '../core/constants.dart';
import '../models/character.dart';
import '../models/project.dart';
import '../models/shot_block.dart';

/// 删除仍被引用的角色时的处理方式，文档 4.3
enum CharacterDeleteStrategy {
  /// 保留原台词文本：把引用降级为自定义文本，不丢内容
  keepAsCustomText,

  /// 改为其他角色
  reassign,

  /// 取消删除
  cancel,
}

/// 删除角色的前置检查结果，供界面决定是否弹二次确认
class CharacterDeletePlan {
  const CharacterDeletePlan({
    required this.characterId,
    required this.characterName,
    required this.referencedShotNumbers,
  });

  final String characterId;
  final String characterName;

  /// 引用该角色的分镜编号（从 1 开始）
  final List<int> referencedShotNumbers;

  /// 仍被引用时需要二次确认（文档 4.3）
  bool get needsConfirmation => referencedShotNumbers.isNotEmpty;

  bool get canDeleteDirectly => !needsConfirmation;
}

/// 角色库服务，文档第四章。
///
/// 所有方法都是纯函数式：接收 [Project] 返回新的 [Project]，
/// 便于撤销/重做栈按快照记录，也避免跨页共享可变状态。
class CharacterService {
  const CharacterService();

  /// 新增角色（文档 4.2）
  Project addCharacter(
    Project project, {
    required String name,
    String gender = Character.defaultGender,
    String age = '',
    String appearance = '',
    String costume = '',
    String personality = '',
    double speechRate = AppConstants.defaultSpeechRate,
    String notes = '',
  }) {
    if (name.trim().isEmpty) return project;
    final character = Character.create(
      name: name,
      gender: gender,
      age: age,
      appearance: appearance,
      costume: costume,
      personality: personality,
      speechRate: speechRate,
      notes: notes,
    );
    return _touch(project.copyWith(characters: <Character>[...project.characters, character]));
  }

  /// 更新角色；改名会同步到所有引用该角色的分镜显示名（文档 4.3）
  Project updateCharacter(Project project, Character updated) {
    if (project.characterById(updated.id) == null) return project;

    final characters = <Character>[
      for (final character in project.characters)
        character.id == updated.id ? updated : character,
    ];
    final shots = <ShotBlock>[
      for (final shot in project.shots)
        shot.dialogueCharacterId == updated.id
            ? shot.syncCharacterName(updated.name.trim())
            : shot,
    ];
    return _touch(project.copyWith(characters: characters, shots: shots));
  }

  /// 角色改名（文档 4.3：所有引用该 characterId 的分镜显示名同步更新）
  Project renameCharacter(Project project, {required String id, required String newName}) {
    final existing = project.characterById(id);
    if (existing == null) return project;
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == existing.name) return project;
    return updateCharacter(project, existing.copyWith(name: trimmed, updatedAt: DateTime.now()));
  }

  /// 删除前的检查：列出引用该角色的分镜编号（文档 4.2「被引用：分镜 1 / 2 / 4」）
  CharacterDeletePlan planDelete(Project project, String id) {
    final character = project.characterById(id);
    return CharacterDeletePlan(
      characterId: id,
      characterName: character?.name ?? '',
      referencedShotNumbers: project.shotNumbersReferencing(id),
    );
  }

  /// 删除角色。未被引用可直接删除；仍被引用时按 [strategy] 处理（文档 4.3）
  Project deleteCharacter(
    Project project,
    String id, {
    CharacterDeleteStrategy strategy = CharacterDeleteStrategy.keepAsCustomText,
    String? reassignToId,
  }) {
    if (strategy == CharacterDeleteStrategy.cancel) return project;
    final target = project.characterById(id);
    if (target == null) return project;

    final characters =
        project.characters.where((character) => character.id != id).toList(growable: false);
    var shots = project.shots;
    var customOptions = project.customOptions;

    switch (strategy) {
      case CharacterDeleteStrategy.keepAsCustomText:
        // 引用降级为自定义文本：保留显示名与台词内容，只清掉 characterId
        shots = <ShotBlock>[
          for (final shot in project.shots)
            shot.dialogueCharacterId == id ? shot.downgradeCharacterReference() : shot,
        ];
        final fallbackName = target.name.trim();
        if (fallbackName.isNotEmpty && !customOptions.characters.contains(fallbackName)) {
          customOptions = customOptions.copyWith(
            characters: <String>[...customOptions.characters, fallbackName],
          );
        }

      case CharacterDeleteStrategy.reassign:
        final replacement = project.characterById(reassignToId);
        shots = <ShotBlock>[
          for (final shot in project.shots)
            if (shot.dialogueCharacterId != id)
              shot
            else if (replacement == null)
              shot.downgradeCharacterReference()
            else
              shot.copyWith(
                dialogueCharacterId: replacement.id,
                dialogueCharacterName: replacement.name,
              ),
        ];

      case CharacterDeleteStrategy.cancel:
        return project;
    }

    return _touch(project.copyWith(
      characters: characters,
      shots: shots,
      customOptions: customOptions,
    ));
  }

  /// 复制角色（生成副本，文档 4.2）
  Project duplicateCharacter(Project project, String id) {
    final target = project.characterById(id);
    if (target == null) return project;
    final copy = target.duplicate(name: '${target.name}${AppConstants.duplicateSuffix}');
    return _touch(project.copyWith(characters: <Character>[...project.characters, copy]));
  }

  /// 角色排序（拖拽语义与 ReorderableListView 一致）
  Project reorderCharacters(Project project, int oldIndex, int newIndex) {
    final characters = List<Character>.of(project.characters);
    if (characters.isEmpty || oldIndex < 0 || oldIndex >= characters.length) return project;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, characters.length - 1);
    final moved = characters.removeAt(oldIndex);
    characters.insert(target, moved);
    return _touch(project.copyWith(characters: characters));
  }

  /// 某角色被哪些分镜引用（文档 4.2「点击可定位」）
  List<int> referencedShotNumbers(Project project, String id) =>
      project.shotNumbersReferencing(id);

  Project _touch(Project project) => project.copyWith(updatedAt: DateTime.now());
}
