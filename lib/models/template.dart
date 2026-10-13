import '../core/json_utils.dart';
import 'shot_block.dart';

/// 模板作用域，文档 9.2「模板范围：项目级 / 全局级」
enum TemplateScope {
  project('项目级'),
  global('全局级');

  const TemplateScope(this.label);

  final String label;

  static TemplateScope fromName(String? value) {
    for (final scope in TemplateScope.values) {
      if (scope.name == value) return scope;
    }
    return TemplateScope.project;
  }
}

/// 分镜模板，文档 9.4 / 16.4。
///
/// 模板保存的是一个分镜快照；台词角色以「占位角色」形式存储在
/// `snapshot.dialogueCharacterName`，套用模板时不写入角色库（文档 9.3）。
class Template {
  const Template({
    required this.id,
    required this.name,
    required this.scope,
    required this.snapshot,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Template.create({
    required String name,
    required TemplateScope scope,
    required ShotBlock snapshot,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return Template(
      id: newId(),
      name: name.trim(),
      scope: scope.name,
      // 模板快照与具体分镜解耦：换 id、清时间标记、解除时长锁定
      snapshot: snapshot.duplicate(now: now),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Template.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Template(
      id: jsonStr(json, 'id', newId()),
      name: jsonStr(json, 'name'),
      scope: jsonStr(json, 'scope', TemplateScope.project.name),
      snapshot: ShotBlock.fromJson(jsonMap(json, 'snapshot')),
      createdAt: jsonDate(json, 'createdAt', now),
      updatedAt: jsonDate(json, 'updatedAt', now),
    );
  }

  final String id;
  final String name;

  /// project / global
  final String scope;
  final ShotBlock snapshot;
  final DateTime createdAt;
  final DateTime updatedAt;

  TemplateScope get scopeValue => TemplateScope.fromName(scope);

  bool get isGlobal => scopeValue == TemplateScope.global;

  /// 模板已填写的字段数，供「预览模板」显示
  int get filledFieldCount => snapshot.contentFields.where((v) => v.trim().isNotEmpty).length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'scope': scope,
        'snapshot': snapshot.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Template copyWith({
    String? id,
    String? name,
    String? scope,
    ShotBlock? snapshot,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Template(
      id: id ?? this.id,
      name: name ?? this.name,
      scope: scope ?? this.scope,
      snapshot: snapshot ?? this.snapshot,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
