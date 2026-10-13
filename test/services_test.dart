import 'dart:convert';

import 'package:bianju/core/constants.dart';
import 'package:bianju/models/character.dart';
import 'package:bianju/models/custom_options.dart';
import 'package:bianju/models/project.dart';
import 'package:bianju/models/shot_block.dart';
import 'package:bianju/models/template.dart';
import 'package:bianju/services/character_service.dart';
import 'package:bianju/services/custom_options_service.dart';
import 'package:bianju/services/export_service.dart';
import 'package:bianju/services/template_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP6 服务层测试：覆盖文档第四章（角色库）、第九章（模板系统）、
/// 第十一章（自定义选项管理）、第十七章（导出规则）。
void main() {
  final fixedTime = DateTime(2026, 10, 13, 9, 0);

  Character lead({String id = 'c-lead', String name = '男主'}) => Character(
        id: id,
        name: name,
        appearance: '短发·瘦高',
        costume: '深色风衣',
        notes: '左脸有旧伤疤',
        speechRate: 200,
        createdAt: fixedTime,
        updatedAt: fixedTime,
      );

  Character female({String id = 'c-female', String name = '女主'}) => Character(
        id: id,
        name: name,
        appearance: '长发',
        costume: '红色围巾',
        speechRate: 180,
        createdAt: fixedTime,
        updatedAt: fixedTime,
      );

  /// 构造一个可复现的项目：固定 id 与时间戳，便于导出快照比对
  Project fixture() {
    final project = Project.create(title: '雨夜', createdAt: fixedTime);
    final shots = <ShotBlock>[
      project.shots[0].copyWith(
        id: 's1',
        duration: 4,
        pace: '正常',
        timeMark: '00:00 - 00:04',
        subjectAction: '男主站在窗前',
        actionStart: '抬头看窗外',
        actionDevelop: '手扶窗框',
        actionEnd: '转身离开',
        cameraMove: '推近',
        backgroundChange: '窗外雨势加大',
        lightingMood: '冷蓝光',
        keepConsistent: '风衣、伤疤位置不变',
        ambientSound: '雨声',
        bgm: '悲伤',
      ),
      project.shots[1].copyWith(
        id: 's2',
        duration: 4,
        pace: '正常',
        timeMark: '00:04 - 00:08',
        subjectAction: '男主回头看向女主',
        cameraMove: '推近',
        lightingMood: '暖黄光',
        dialogueCharacterId: 'c-female',
        dialogueCharacterName: '女主',
        dialogue: '你真的要走吗？',
        ambientSound: '室内安静',
        keepConsistent: '女主红色围巾不变',
      ),
      // 空分镜：导出时应被忽略（文档 17.1）
      project.shots[2].copyWith(id: 's3', duration: 4),
      // 禁用分镜：导出时应被忽略（文档 5.2）
      project.shots[3].copyWith(id: 's4', duration: 3, enabled: false, subjectAction: '被禁用的内容'),
    ];
    return project.copyWith(
      id: 'p-fixed',
      shots: shots,
      characters: [lead(), female()],
      updatedAt: fixedTime,
    );
  }

  group('CharacterService（文档 4.2 / 4.3）', () {
    const service = CharacterService();

    test('新增角色追加到角色库，不影响分镜', () {
      final project = fixture();
      final result = service.addCharacter(project, name: '旁白', speechRate: 160);

      expect(result.characters, hasLength(3));
      expect(result.characters.last.name, '旁白');
      expect(result.characters.last.speechRate, 160);
      expect(result.shots, project.shots);
    });

    test('角色改名后所有引用分镜的显示名同步更新', () {
      final project = fixture();
      final result = service.renameCharacter(project, id: 'c-female', newName: '苏雨');

      expect(result.characterById('c-female')!.name, '苏雨');
      expect(result.shots[1].dialogueCharacterName, '苏雨');
      // 引用关系不变
      expect(result.shots[1].dialogueCharacterId, 'c-female');
      // 未引用该角色的分镜不受影响
      expect(result.shots[0].dialogueCharacterName, '');
    });

    test('未被引用的角色可直接删除，无需二次确认', () {
      final project = fixture();
      final plan = service.planDelete(project, 'c-lead');

      expect(plan.needsConfirmation, isFalse);
      expect(plan.referencedShotNumbers, isEmpty);

      final result = service.deleteCharacter(project, 'c-lead');
      expect(result.characters, hasLength(1));
    });

    test('被引用的角色删除前给出分镜编号，需二次确认', () {
      final project = fixture();
      final plan = service.planDelete(project, 'c-female');

      expect(plan.needsConfirmation, isTrue);
      expect(plan.referencedShotNumbers, [2]);
    });

    test('删除策略「保留原台词文本」：降级为自定义兜底，不丢内容', () {
      final project = fixture();
      final result = service.deleteCharacter(
        project,
        'c-female',
        strategy: CharacterDeleteStrategy.keepAsCustomText,
      );

      expect(result.characters, hasLength(1));
      expect(result.shots[1].dialogueCharacterId, '');
      expect(result.shots[1].dialogueCharacterName, '女主');
      expect(result.shots[1].dialogue, '你真的要走吗？');
      // 降级后进入自定义兜底名单（文档第十一章）
      expect(result.customOptions.characters, contains('女主'));
    });

    test('删除策略「改为其他角色」：引用改指向新角色并同步显示名', () {
      final project = fixture();
      final result = service.deleteCharacter(
        project,
        'c-female',
        strategy: CharacterDeleteStrategy.reassign,
        reassignToId: 'c-lead',
      );

      expect(result.characters, hasLength(1));
      expect(result.shots[1].dialogueCharacterId, 'c-lead');
      expect(result.shots[1].dialogueCharacterName, '男主');
      expect(result.shots[1].dialogue, '你真的要走吗？');
    });

    test('删除策略「取消」：项目原样返回', () {
      final project = fixture();
      final result = service.deleteCharacter(
        project,
        'c-female',
        strategy: CharacterDeleteStrategy.cancel,
      );

      expect(result.characters, hasLength(2));
    });

    test('复制角色生成新 id 的副本', () {
      final project = fixture();
      final result = service.duplicateCharacter(project, 'c-lead');

      expect(result.characters, hasLength(3));
      expect(result.characters.last.id, isNot('c-lead'));
      expect(result.characters.last.name, contains('男主'));
    });

    test('改角色语速后台词预估总时长随之变化（文档 4.5）', () {
      final project = fixture();
      final before = project.dialogueEstimatedTotal;

      final result = service.updateCharacter(project, lead().copyWith(id: 'c-female', name: '女主', speechRate: 240));
      // 女主语速 180 → 240，同样 7 字台词预估变短
      expect(result.dialogueEstimatedTotal, lessThan(before));
    });
  });

  group('TemplateService（文档第九章）', () {
    const service = TemplateService();

    test('内置 6 个模板：对话、追逐、情绪特写、空镜转场、开场悬念、结尾反转', () {
      final names = TemplateService.builtInTemplates().map((t) => t.name).toList();

      expect(names, ['对话', '追逐', '情绪特写', '空镜转场', '开场悬念', '结尾反转']);
      expect(names, hasLength(6));
    });

    test('默认只填空字段，不清空已填内容（文档 9.2）', () {
      final project = fixture();
      final template = TemplateService.builtInTemplates().first;

      final result = service.applyTemplate(project, shotIndex: 0, template: template);

      // 分镜 1 原本已填「推近」，不被模板覆盖
      expect(result.shots[0].cameraMove, '推近');
      expect(result.shots[0].subjectAction, '男主站在窗前');
    });

    test('覆盖全部模式会替换已填字段', () {
      final project = fixture();
      final template = TemplateService.builtInTemplates().first;

      final result = service.applyTemplate(
        project,
        shotIndex: 0,
        template: template,
        mode: TemplateApplyMode.overwriteAll,
      );

      expect(result.shots[0].cameraMove, template.snapshot.cameraMove);
    });

    test('套用模板不污染角色库：不新增角色，台词角色留空由用户选角（文档 9.3）', () {
      final project = fixture();
      final template = TemplateService.builtInTemplates().first;

      final result = service.applyTemplate(project, shotIndex: 1, template: template);

      expect(result.characters, hasLength(project.characters.length));
      expect(result.shots[1].dialogueCharacterId, '');
      expect(result.shots[1].dialogueCharacterName, '');
    });

    test('套用模板只作用于启用分镜', () {
      final project = fixture();
      final template = TemplateService.builtInTemplates().first;

      final result = service.applyTemplate(project, shotIndex: 3, template: template);

      expect(result.shots[3].subjectAction, '被禁用的内容');
    });

    test('套用模板不改变分镜时长与启用状态', () {
      final project = fixture();
      final template = TemplateService.builtInTemplates().first;

      final result = service.applyTemplate(project, shotIndex: 0, template: template);

      expect(result.shots[0].duration, project.shots[0].duration);
      expect(result.usedDuration, project.usedDuration);
    });

    test('批量套用到全部空分镜', () {
      final project = fixture();
      final template = TemplateService.builtInTemplates()[2];

      final result = service.applyToAllEmptyShots(project, template: template);

      // 分镜 3 原本是空的，被套用；分镜 1、2 已有内容不动；分镜 4 被禁用不动
      expect(result.shots[2].hasContent, isTrue);
      expect(result.shots[0].subjectAction, '男主站在窗前');
      expect(result.shots[3].subjectAction, '被禁用的内容');
    });

    test('保存当前分镜为模板，快照不带原分镜 id', () {
      final project = fixture();

      final result = service.saveShotAsTemplate(project, shotIndex: 0, name: '窗边推近');

      expect(result.templates, hasLength(1));
      expect(result.templates.first.name, '窗边推近');
      expect(result.templates.first.scope, TemplateScope.project.name);
      expect(result.templates.first.snapshot.id, isNot('s1'));
      expect(result.templates.first.snapshot.cameraMove, '推近');
    });

    test('模板可重命名、删除、排序（文档 9.2）', () {
      var project = fixture();
      project = service.saveShotAsTemplate(project, shotIndex: 0, name: 'A');
      project = service.saveShotAsTemplate(project, shotIndex: 1, name: 'B');
      expect(project.templates.map((t) => t.name).toList(), ['A', 'B']);

      final renamed = service.renameTemplate(project, project.templates.first.id, 'A2');
      expect(renamed.templates.first.name, 'A2');

      final reordered = service.reorderTemplates(renamed, 0, 2);
      expect(reordered.templates.map((t) => t.name).toList(), ['B', 'A2']);

      final deleted = service.deleteTemplate(reordered, reordered.templates.first.id);
      expect(deleted.templates.map((t) => t.name).toList(), ['A2']);
    });

    test('可用模板 = 内置模板 + 项目自定义模板 + 全局模板', () {
      final project = fixture();
      final withTemplate = service.saveShotAsTemplate(project, shotIndex: 0, name: '自定义A');
      final global = Template.create(
        name: '全局B',
        scope: TemplateScope.global,
        snapshot: ShotBlock.create(orderIndex: 0, duration: 3, createdAt: fixedTime),
        createdAt: fixedTime,
      );

      final available = service.availableTemplates(withTemplate, globalTemplates: [global]);

      expect(available.map((t) => t.name), containsAll(<String>['对话', '自定义A', '全局B']));
    });
  });

  group('CustomOptionsService（文档第十一章）', () {
    const service = CustomOptionsService();

    test('新增选项；重复值忽略', () {
      final project = fixture();
      final added = service.addOption(project, OptionCategory.ambientSound, '地铁轰鸣');
      expect(added.customOptions.ambientSounds, contains('地铁轰鸣'));

      final again = service.addOption(added, OptionCategory.ambientSound, '地铁轰鸣');
      expect(again.customOptions.ambientSounds.where((v) => v == '地铁轰鸣'), hasLength(1));
    });

    test('重命名选项时同步已选用该值的分镜', () {
      final project = fixture();
      final result = service.renameOption(
        project,
        OptionCategory.ambientSound,
        from: '雨声',
        to: '暴雨',
      );

      expect(result.customOptions.ambientSounds, contains('暴雨'));
      expect(result.customOptions.ambientSounds, isNot(contains('雨声')));
      expect(result.shots[0].ambientSound, '暴雨');
    });

    test('删除选项后已选用该值的分镜字段被清空', () {
      final project = fixture();
      final result = service.removeOption(project, OptionCategory.bgm, '悲伤');

      expect(result.customOptions.bgms, isNot(contains('悲伤')));
      expect(result.shots[0].bgm, '');
    });

    test('台词角色类别的重命名不影响已绑定角色库的分镜（文档 11）', () {
      final base = fixture();
      final project = base.copyWith(
        customOptions: base.customOptions.copyWith(characters: ['女主']),
      );

      final result = service.renameOption(
        project,
        OptionCategory.character,
        from: '女主',
        to: '女二',
      );

      // 分镜 2 绑定的是角色库里有档案的「女主」，不应被兜底名单改名波及
      expect(result.shots[1].dialogueCharacterName, '女主');
      expect(result.shots[1].dialogueCharacterId, 'c-female');
      expect(result.customOptions.characters, contains('女二'));
    });

    test('排序选项', () {
      final project = fixture();
      final result = service.reorderOption(project, OptionCategory.pace, 0, 2);

      expect(result.customOptions.paces.first, isNot('慢'));
      expect(result.customOptions.paces, hasLength(project.customOptions.paces.length));
    });

    test('恢复某类别的默认选项库', () {
      final project = fixture();
      final changed = service.addOption(project, OptionCategory.pace, '极慢');
      final restored = service.resetToDefaults(changed, OptionCategory.pace);

      expect(restored.customOptions.paces, CustomOptions.defaultPaces);
    });
  });

  group('ExportService · Markdown（文档 17.1 / 17.2 / 17.5）', () {
    const service = ExportService();

    test('导出快照：角色表 + 有内容的启用分镜', () {
      final markdown = service.toMarkdown(fixture());

      expect(markdown, '''# 角色表

- 男主：短发·瘦高，深色风衣，左脸有旧伤疤，语速 200
- 女主：长发，红色围巾，语速 180

# 分镜 1

- 时长：4 秒
- 节奏：正常
- 时间标记：00:00 - 00:04
- 主体动作：男主站在窗前
- 动作流程：开始—抬头看窗外 -> 发展—手扶窗框 -> 结束—转身离开
- 镜头运动：推近
- 背景变化：窗外雨势加大
- 光线氛围：冷蓝光
- 保持特征：风衣、伤疤位置不变
- 环境音：雨声
- 背景音乐：悲伤

# 分镜 2

- 时长：4 秒
- 节奏：正常
- 时间标记：00:04 - 00:08
- 主体动作：男主回头看向女主
- 镜头运动：推近
- 光线氛围：暖黄光
- 保持特征：女主红色围巾不变
- 台词角色：女主
- 台词：你真的要走吗？
- 环境音：室内安静''');
    });

    test('空分镜与禁用分镜都不输出', () {
      final markdown = service.toMarkdown(fixture());

      expect(markdown, isNot(contains('分镜 3')));
      expect(markdown, isNot(contains('分镜 4')));
      expect(markdown, isNot(contains('被禁用的内容')));
    });

    test('不输出 null、「未填写」，也不产生空行', () {
      final markdown = service.toMarkdown(fixture());

      expect(markdown, isNot(contains('null')));
      expect(markdown, isNot(contains('未填写')));
      expect(markdown, isNot(contains('\n\n\n')));
      for (final line in markdown.split('\n')) {
        expect(line, isNot(matches(RegExp(r'^\s+-\s*$'))));
      }
    });

    test('环境音选「无」时不输出该行', () {
      final base = fixture();
      final project = base.copyWith(shots: [
        base.shots[0].copyWith(ambientSound: AppConstants.noneOption, ambientSoundNote: ''),
        // 其余分镜的环境音一并清空，确保整个导出里不出现「环境音」行
        ...base.shots.skip(1).map((shot) => shot.copyWith(ambientSound: '')),
      ]);

      final markdown = service.toMarkdown(project);
      expect(markdown, isNot(contains('环境音')));
      expect(markdown, isNot(contains(AppConstants.noneOption)));
    });

    test('选项带补充说明时拼接输出', () {
      final base = fixture();
      final project = base.copyWith(shots: [
        base.shots[0].copyWith(ambientSound: '雨声', ambientSoundNote: '由远及近'),
        ...base.shots.skip(1),
      ]);

      expect(service.toMarkdown(project), contains('环境音：雨声（由远及近）'));
    });

    test('动作流程只拼接已填写的部分', () {
      final base = fixture();
      final project = base.copyWith(shots: [
        base.shots[0].copyWith(actionStart: '抬头', actionDevelop: '', actionEnd: '转身'),
        ...base.shots.skip(1),
      ]);

      expect(service.toMarkdown(project), contains('动作流程：开始—抬头 -> 结束—转身'));
    });

    test('没有角色时不输出角色表段落', () {
      final project = fixture().copyWith(characters: []);

      expect(service.toMarkdown(project), isNot(contains('# 角色表')));
      expect(service.toMarkdown(project), contains('# 分镜 1'));
    });
  });

  group('ExportService · TXT / JSON / 文件名（文档 17.3 / 17.6）', () {
    const service = ExportService();

    test('TXT 不含 Markdown 记号', () {
      final text = service.toText(fixture());

      expect(text, isNot(contains('#')));
      expect(text, contains('分镜 1'));
      expect(text, contains('台词：你真的要走吗？'));
    });

    test('JSON 完整保留角色库与分镜的角色引用（文档 17.3）', () {
      final decoded = jsonDecode(service.toJson(fixture())) as Map<String, dynamic>;

      expect(decoded['characters'], hasLength(2));
      final shots = decoded['shots'] as List;
      expect(shots[1]['dialogueCharacterId'], 'c-female');
      expect(decoded['title'], '雨夜');
    });

    test('导出文件名规则：{标题}_{格式}_{日期}.{后缀}', () {
      final result = service.export(fixture(), format: ExportFormat.markdown, now: fixedTime);

      expect(result.fileName, '雨夜_Markdown_20261013.md');
      expect(result.content, isNotEmpty);
    });

    test('标题含非法文件名字符时被清洗', () {
      final project = fixture().copyWith(title: '雨夜/终版:定稿');

      expect(service.fileNameFor(project, ExportFormat.txt, now: fixedTime), isNot(contains('/')));
      expect(service.fileNameFor(project, ExportFormat.txt, now: fixedTime), isNot(contains(':')));
    });

    test('三种格式切换都能导出', () {
      for (final format in ExportFormat.values) {
        final result = service.export(fixture(), format: format, now: fixedTime);
        expect(result.format, format);
        expect(result.content, isNotEmpty);
        expect(result.fileName, endsWith('.${format.extension}'));
      }
    });

    test('所有可导出分镜为空时抛「暂无可导出内容」', () {
      final empty = Project.create(title: '空白');

      expect(
        () => service.export(empty),
        throwsA(isA<EmptyExportException>().having(
          (e) => e.message,
          'message',
          contains('暂无可导出内容'),
        )),
      );
    });
  });
}
