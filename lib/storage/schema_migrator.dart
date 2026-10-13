import '../core/constants.dart';
import '../core/json_utils.dart';

/// 一次迁移的结果
class MigrationResult {
  const MigrationResult({
    required this.json,
    required this.appliedMigrations,
    this.skippedFromFutureVersion = false,
  });

  /// 迁移后的 JSON
  final Map<String, dynamic> json;

  /// 实际执行过的迁移步骤说明，供界面提示「数据已升级」
  final List<String> appliedMigrations;

  /// 数据版本高于当前程序版本时为 true：不降级、不改写，只提示用户升级应用
  final bool skippedFromFutureVersion;

  bool get migrated => appliedMigrations.isNotEmpty;
}

/// 数据结构迁移，文档 16.5。
///
/// 版本约定：
/// - v1：分镜的台词角色是纯文本字段 `dialogueCharacter`，项目可能没有角色库；
/// - v2（当前）：台词角色拆成 `dialogueCharacterId`（引用角色库）+
///   `dialogueCharacterName`（冗余显示名，兼容自定义兜底）。
///
/// v1 → v2 的处理策略：
/// 1. 旧的 `dialogueCharacter` 文本转存为 `dialogueCharacterName`，不丢内容；
/// 2. 按名称匹配角色库已有档案，命中则回填 `dialogueCharacterId`；
/// 3. 未命中且有名字，则**自动补建**角色档案再回填（文档「尝试按名称匹配自动补建
///    Character 档案」）——这样能最大限度保住引用关系；
/// 4. 名字为空时保留为自定义兜底（id 置空），不补建空档案。
class SchemaMigrator {
  const SchemaMigrator();

  /// 当前程序支持的数据版本
  static const int currentVersion = AppConstants.currentSchemaVersion;

  /// 数据版本缺失时按最早的 v1 处理
  static const int oldestVersion = 1;

  /// 逐级升级并返回迁移后的 JSON
  Map<String, dynamic> migrate(Map<String, dynamic> source) =>
      migrateWithReport(source).json;

  /// 逐级升级并返回迁移报告
  MigrationResult migrateWithReport(Map<String, dynamic> source) {
    final json = Map<String, dynamic>.from(source);
    final applied = <String>[];
    final version = jsonInt(json, 'schemaVersion', oldestVersion);

    if (version > currentVersion) {
      // 来自更新版本的应用：原样保留，避免降级破坏数据
      return MigrationResult(
        json: json,
        appliedMigrations: applied,
        skippedFromFutureVersion: true,
      );
    }

    if (version < 2) {
      applied.addAll(_migrateV1ToV2(json));
    }
    // 后续版本升级在此按 if (version < 3) { ... } 逐级追加

    json['schemaVersion'] = currentVersion;
    return MigrationResult(json: json, appliedMigrations: applied);
  }

  List<String> _migrateV1ToV2(Map<String, dynamic> json) {
    final characters = jsonMapList(json, 'characters');
    final shots = jsonMapList(json, 'shots');
    final nowIso = DateTime.now().toIso8601String();
    var createdCount = 0;
    var linkedCount = 0;

    for (final shot in shots) {
      // 已是新结构的分镜不重复处理
      if (shot.containsKey('dialogueCharacterId')) continue;
      if (!shot.containsKey('dialogueCharacter')) continue;

      final legacyName = jsonStr(shot, 'dialogueCharacter').trim();
      shot.remove('dialogueCharacter');
      shot['dialogueCharacterName'] = legacyName;

      if (legacyName.isEmpty) {
        shot['dialogueCharacterId'] = '';
        continue;
      }

      Map<String, dynamic>? matched;
      for (final character in characters) {
        if (jsonStr(character, 'name').trim() == legacyName) {
          matched = character;
          break;
        }
      }

      if (matched == null) {
        matched = <String, dynamic>{
          'id': newId(),
          'name': legacyName,
          'gender': '未设定',
          'age': '',
          'appearance': '',
          'costume': '',
          'personality': '',
          'speechRate': AppConstants.defaultSpeechRate,
          'notes': '由旧版本数据自动补建',
          'createdAt': nowIso,
          'updatedAt': nowIso,
        };
        characters.add(matched);
        createdCount++;
      } else {
        linkedCount++;
      }
      shot['dialogueCharacterId'] = jsonStr(matched, 'id');
    }

    json['characters'] = characters;
    json['shots'] = shots;

    final notes = <String>[];
    if (linkedCount > 0) notes.add('v1→v2：$linkedCount 处台词角色按名匹配到角色库档案');
    if (createdCount > 0) notes.add('v1→v2：自动补建 $createdCount 个角色档案');
    if (notes.isEmpty && shots.isNotEmpty) {
      notes.add('v1→v2：台词角色字段已转为引用结构');
    }
    return notes;
  }
}
