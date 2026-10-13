import 'dart:convert';

import 'package:bianju/core/constants.dart';
import 'package:bianju/models/character.dart';
import 'package:bianju/models/consistency_issue.dart';
import 'package:bianju/models/custom_options.dart';
import 'package:bianju/models/project.dart';
import 'package:bianju/models/shot_block.dart';
import 'package:bianju/models/template.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP1 数据模型层测试：覆盖文档第十六章数据模型、第十二章项目生命周期、
/// 第十六章 16.5 数据迁移所需的序列化契约。
void main() {
  group('Project.create 默认值（文档十五、十六章）', () {
    test('默认总时长 15 秒、默认 4 个分镜', () {
      final project = Project.create(title: '短片A');

      expect(project.title, '短片A');
      expect(project.totalDuration, AppConstants.defaultTotalDuration);
      expect(project.shots, hasLength(AppConstants.defaultShotCount));
    });

    test('分镜 orderIndex 从 0 起连续编号，时长平均分配且合计等于总时长', () {
      final project = Project.create(title: '短片A');

      expect(project.shots.map((s) => s.orderIndex).toList(), [0, 1, 2, 3]);
      expect(project.usedDuration, project.totalDuration);
      for (final shot in project.shots) {
        expect(shot.duration, greaterThanOrEqualTo(AppConstants.minShotDuration));
      }
    });

    test('默认语速 200 字/分钟，默认导出格式 Markdown，schemaVersion 为当前版本', () {
      final project = Project.create(title: '短片A');

      expect(project.defaultSpeechRate, AppConstants.defaultSpeechRate);
      expect(project.exportFormat, ExportFormat.markdown.name);
      expect(project.schemaVersion, AppConstants.currentSchemaVersion);
    });

    test('自定义分镜数与总时长时按平均值分配', () {
      final project = Project.create(title: 'B', totalDuration: 10, shotCount: 5);

      expect(project.shots, hasLength(5));
      expect(project.usedDuration, 10);
    });

    test('新建项目角色库为空，但自定义选项已带默认下拉值', () {
      final project = Project.create(title: '短片A');

      expect(project.characters, isEmpty);
      expect(project.templates, isEmpty);
      expect(project.customOptions.paces, contains('正常'));
      expect(project.customOptions.cameraMoves, contains('推近'));
      expect(project.customOptions.lightingMoods, contains('冷蓝光'));
      expect(project.customOptions.ambientSounds, contains('雨声'));
      expect(project.customOptions.bgms, contains('悲伤'));
    });
  });

  group('Character（文档 4.1 / 16.2）', () {
    test('建档时生成 id 与时间戳，语速缺省为 200', () {
      final character = Character.create(name: '男主');

      expect(character.id, isNotEmpty);
      expect(character.name, '男主');
      expect(character.speechRate, AppConstants.defaultSpeechRate);
      expect(character.gender, CharacterGender.unset.label);
      expect(character.createdAt, isNotNull);
    });

    test('JSON 往返保留全部字段', () {
      final character = Character.create(
        name: '男主',
        gender: CharacterGender.male.label,
        age: '28',
        appearance: '短发·瘦高，左脸有旧伤疤',
        costume: '深色风衣',
        personality: '沉默寡言',
        speechRate: 240,
        notes: '伤疤位置不可变',
      );

      final restored = Character.fromJson(jsonDecode(jsonEncode(character.toJson())));

      expect(jsonEncode(restored.toJson()), jsonEncode(character.toJson()));
      expect(restored.speechRate, 240);
      expect(restored.appearance, contains('左脸'));
    });

    test('copyWith 只改指定字段，其余保持不变', () {
      final character = Character.create(name: '男主', costume: '深色风衣');
      final renamed = character.copyWith(name: '阿明');

      expect(renamed.name, '阿明');
      expect(renamed.costume, '深色风衣');
      expect(renamed.id, character.id);
    });
  });

  group('ShotBlock（文档 16.3 / 5.2 / 17.1）', () {
    test('新建分镜默认为启用、未锁定、无内容', () {
      final shot = ShotBlock.create(orderIndex: 0, duration: 4);

      expect(shot.enabled, isTrue);
      expect(shot.durationLocked, isFalse);
      expect(shot.hasContent, isFalse);
      expect(shot.dialogue, '');
    });

    test('任一字段填写后 hasContent 为真', () {
      expect(ShotBlock.create(orderIndex: 0, duration: 4).copyWith(dialogue: '你真的要走吗？').hasContent, isTrue);
      expect(ShotBlock.create(orderIndex: 0, duration: 4).copyWith(pace: '正常').hasContent, isTrue);
      expect(ShotBlock.create(orderIndex: 0, duration: 4).copyWith(dialogue: '   ').hasContent, isFalse);
    });

    test('JSON 往返保留台词角色引用 id 与冗余显示名', () {
      final shot = ShotBlock.create(orderIndex: 1, duration: 4).copyWith(
        dialogueCharacterId: 'char-1',
        dialogueCharacterName: '男主',
        dialogue: '你真的要走吗？',
        cameraMove: '推近',
        lightingMood: '冷蓝光',
      );

      final restored = ShotBlock.fromJson(jsonDecode(jsonEncode(shot.toJson())));

      expect(restored.dialogueCharacterId, 'char-1');
      expect(restored.dialogueCharacterName, '男主');
      expect(jsonEncode(restored.toJson()), jsonEncode(shot.toJson()));
    });

    test('缺失可选字段时用默认值补齐（容错解析旧数据）', () {
      final restored = ShotBlock.fromJson(<String, dynamic>{
        'id': 'legacy-1',
        'duration': 3,
        'dialogue': '走吧',
      });

      expect(restored.id, 'legacy-1');
      expect(restored.enabled, isTrue);
      expect(restored.durationLocked, isFalse);
      expect(restored.orderIndex, 0);
      expect(restored.pace, '');
      expect(restored.dialogue, '走吧');
    });
  });

  group('Template / CustomOptions / ConsistencyIssue（文档 9.4 / 11 / 16.4）', () {
    test('Template 快照完整保留分镜字段且可 JSON 往返', () {
      final shot = ShotBlock.create(orderIndex: 0, duration: 4).copyWith(
        pace: '慢',
        cameraMove: '推近',
        ambientSound: '雨声',
      );
      final template = Template.create(name: '对话', scope: TemplateScope.project, snapshot: shot);

      final restored = Template.fromJson(jsonDecode(jsonEncode(template.toJson())));

      expect(restored.name, '对话');
      expect(restored.scope, TemplateScope.project.name);
      expect(restored.snapshot.cameraMove, '推近');
      expect(restored.snapshot.ambientSound, '雨声');
    });

    test('CustomOptions 往返保留六个列表的顺序', () {
      final options = CustomOptions.defaults().copyWith(paces: ['慢', '正常', '快', '急促']);

      final restored = CustomOptions.fromJson(jsonDecode(jsonEncode(options.toJson())));

      expect(restored.paces, ['慢', '正常', '快', '急促']);
      expect(restored.bgms, isNotEmpty);
    });

    test('ConsistencyIssue 记录类型、级别、涉及分镜与忽略/确认状态', () {
      const issue = ConsistencyIssue(
        type: ConsistencyIssueType.costume,
        level: IssueLevel.warning,
        shotOrders: [3],
        characterId: 'char-1',
        message: '服装不一致',
      );

      final restored = ConsistencyIssue.fromJson(jsonDecode(jsonEncode(issue.toJson())));

      expect(restored.type, ConsistencyIssueType.costume);
      expect(restored.level, IssueLevel.warning);
      expect(restored.shotOrders, [3]);
      expect(restored.ignored, isFalse);
      expect(restored.acknowledged, isFalse);
      expect(issue.copyWith(ignored: true).ignored, isTrue);
      // 序列化落盘用字符串，反序列化还原为枚举
      expect(issue.toJson()['type'], ConsistencyIssueType.costume.name);
      expect(issue.toJson()['level'], IssueLevel.warning.name);
    });
  });

  group('Project 聚合行为（文档 5.2 / 6.1 / 12）', () {
    Project buildProject() {
      final characters = [
        Character.create(name: '男主'),
        Character.create(name: '女主'),
        Character.create(name: '旁白'),
      ];
      final project = Project.create(title: '短片A');
      return project.copyWith(
        characters: characters,
        shots: [
          project.shots[0].copyWith(dialogueCharacterId: characters[0].id, dialogue: '走吧'),
          project.shots[1].copyWith(enabled: false),
          project.shots[2],
          project.shots[3],
        ],
      );
    }

    test('enabledShots 只含启用分镜，usedDuration 不计入禁用分镜', () {
      final project = buildProject();

      expect(project.enabledShots, hasLength(3));
      expect(project.usedDuration, project.totalDuration - project.shots[1].duration);
      expect(project.remainingDuration, project.shots[1].duration);
    });

    test('characterById 可按 id 取到角色，取不到返回 null', () {
      final project = buildProject();

      expect(project.characterById(project.characters.first.id)?.name, '男主');
      expect(project.characterById('不存在'), isNull);
    });

    test('referencedCharacterIds 反映分镜引用情况', () {
      final project = buildProject();

      expect(project.referencedCharacterIds, [project.characters.first.id]);
    });

    test('复制项目会重新生成 id 并连同角色库一起复制（文档 12）', () {
      final project = buildProject();
      final copy = project.duplicate();

      expect(copy.id, isNot(project.id));
      expect(copy.title, '${project.title} 副本');
      expect(copy.characters, hasLength(project.characters.length));
      expect(copy.characters.first.id, isNot(project.characters.first.id));
      // 分镜对新角色的引用同步指向副本角色，不跨项目串引用
      expect(copy.shots.first.dialogueCharacterId, copy.characters.first.id);
      expect(copy.shots.first.dialogue, '走吧');
    });

    test('Project JSON 往返保持等价', () {
      final project = buildProject();

      final restored = Project.fromJson(jsonDecode(jsonEncode(project.toJson())));

      expect(jsonEncode(restored.toJson()), jsonEncode(project.toJson()));
    });
  });
}
