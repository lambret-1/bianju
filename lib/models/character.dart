import '../core/constants.dart';
import '../core/json_utils.dart';

/// 角色性别选项，文档 4.1
enum CharacterGender {
  male('男'),
  female('女'),
  other('其他'),
  unset('未设定');

  const CharacterGender(this.label);

  final String label;

  static CharacterGender fromLabel(String? label) {
    for (final gender in CharacterGender.values) {
      if (gender.label == label) return gender;
    }
    return CharacterGender.unset;
  }
}

/// 角色库中的角色，文档 4.1 / 16.2。
///
/// 角色是项目级一等公民：一次建档、全局引用、改一处同步所有分镜，
/// 并作为一致性检查（服装/外貌/称呼）与台词语速估算的基准。
class Character {
  const Character({
    required this.id,
    required this.name,
    this.gender = defaultGender,
    this.age = '',
    this.appearance = '',
    this.costume = '',
    this.personality = '',
    this.speechRate = AppConstants.defaultSpeechRate,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// 性别未设定时的默认标签
  static const String defaultGender = '未设定';

  factory Character.create({
    required String name,
    String gender = defaultGender,
    String age = '',
    String appearance = '',
    String costume = '',
    String personality = '',
    double speechRate = AppConstants.defaultSpeechRate,
    String notes = '',
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return Character(
      id: newId(),
      name: name.trim(),
      gender: gender,
      age: age.trim(),
      appearance: appearance.trim(),
      costume: costume.trim(),
      personality: personality.trim(),
      speechRate: speechRate > 0 ? speechRate : AppConstants.defaultSpeechRate,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Character.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Character(
      id: jsonStr(json, 'id', newId()),
      name: jsonStr(json, 'name'),
      gender: jsonStr(json, 'gender', defaultGender),
      age: jsonStr(json, 'age'),
      appearance: jsonStr(json, 'appearance'),
      costume: jsonStr(json, 'costume'),
      personality: jsonStr(json, 'personality'),
      speechRate: jsonDouble(json, 'speechRate', AppConstants.defaultSpeechRate),
      notes: jsonStr(json, 'notes'),
      createdAt: jsonDate(json, 'createdAt', now),
      updatedAt: jsonDate(json, 'updatedAt', now),
    );
  }

  final String id;
  final String name;
  final String gender;

  /// 年龄段或具体年龄，供创作参考
  final String age;

  /// 外貌特征：身高、体型、发型、显著特征（一致性检查基准）
  final String appearance;

  /// 默认服装（一致性检查基准）
  final String costume;
  final String personality;

  /// 台词语速（字/分钟），用于台词时长估算
  final double speechRate;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 显示名，空名时回落为「未命名角色」，避免下拉出现空白项
  String get displayName => name.trim().isEmpty ? '未命名角色' : name.trim();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'gender': gender,
        'age': age,
        'appearance': appearance,
        'costume': costume,
        'personality': personality,
        'speechRate': speechRate,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Character copyWith({
    String? id,
    String? name,
    String? gender,
    String? age,
    String? appearance,
    String? costume,
    String? personality,
    double? speechRate,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Character(
      id: id ?? this.id,
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      appearance: appearance ?? this.appearance,
      costume: costume ?? this.costume,
      personality: personality ?? this.personality,
      speechRate: speechRate ?? this.speechRate,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 生成一个新 id 的副本（复制角色 / 复制项目时使用，文档 4.2）
  Character duplicate({String? name, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return copyWith(
      id: newId(),
      name: name ?? this.name,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}
