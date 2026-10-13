import 'package:bianju/core/constants.dart';
import 'package:bianju/core/validators.dart';
import 'package:bianju/models/character.dart';
import 'package:bianju/models/consistency_issue.dart';
import 'package:bianju/models/project.dart';
import 'package:bianju/models/shot_block.dart';
import 'package:bianju/services/consistency_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP3 规则引擎测试：覆盖文档第十三章「统一校验中心」的 11 条校验项，
/// 以及第十章「一致性检查」的 8 个维度。
void main() {
  /// 构造一个总时长 15 秒、4 个分镜的项目，便于逐条规则单独触发
  Project buildProject({
    List<Character> characters = const <Character>[],
    List<ShotBlock> Function(List<ShotBlock> defaults)? mutateShots,
    ConsistencyRules rules = const ConsistencyRules(),
  }) {
    final project = Project.create(title: '测试短片').copyWith(
      characters: characters,
      consistencyRules: rules,
    );
    final shots = mutateShots == null ? project.shots : mutateShots(project.shots);
    return project.copyWith(shots: shots);
  }

  Character maleLead({String costume = '深色风衣', String appearance = ''}) =>
      Character.create(name: '男主', costume: costume, appearance: appearance);

  group('校验中心 · 错误级（文档 13：错误禁止导出）', () {
    test('所有启用分镜全空时报错', () {
      final result = Validators.validate(buildProject());

      expect(result.codes, contains(ValidationCode.allShotsEmpty));
      expect(result.canExport, isFalse);
    });

    test('任一分镜填写内容后不再报「全空」', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [shots[0].copyWith(subjectAction: '男主站在窗前'), ...shots.skip(1)],
      ));

      expect(result.codes, isNot(contains(ValidationCode.allShotsEmpty)));
    });

    test('分镜时长小于 1 秒报错并定位到分镜编号', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '男主站在窗前', duration: 0.5),
          ...shots.skip(1),
        ],
      ));

      final issue = result.issueOf(ValidationCode.shotTooShort);
      expect(issue, isNotNull);
      expect(issue!.level, IssueLevel.error);
      expect(issue.shotNumber, 1);
    });

    test('启用分镜时长之和与总时长不匹配时报错', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '男主站在窗前', duration: 2),
          ...shots.skip(1),
        ],
      ));

      expect(result.codes, contains(ValidationCode.totalMismatch));
      expect(result.canExport, isFalse);
    });

    test('台词角色引用了已失效的角色时报错', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主站在窗前',
            dialogueCharacterId: '已删除的角色 id',
            dialogueCharacterName: '男主',
            dialogue: '走吧',
          ),
          ...shots.skip(1),
        ],
      ));

      final issue = result.issueOf(ValidationCode.brokenCharacterReference);
      expect(issue, isNotNull);
      expect(issue!.level, IssueLevel.error);
      expect(issue.shotNumber, 1);
    });

    test('禁用的分镜不参与校验', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '男主站在窗前'),
          shots[1].copyWith(enabled: false, duration: 0.2),
          ...shots.skip(2),
        ],
      ));

      expect(result.codes, isNot(contains(ValidationCode.shotTooShort)));
    });
  });

  group('校验中心 · 警告级（文档 13：允许导出但提示风险）', () {
    test('有台词角色但无台词 → 警告', () {
      final character = maleLead();
      final result = Validators.validate(buildProject(
        characters: [character],
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主站在窗前',
            dialogueCharacterId: character.id,
            dialogueCharacterName: character.name,
          ),
          ...shots.skip(1),
        ],
      ));

      final issue = result.issueOf(ValidationCode.characterWithoutDialogue);
      expect(issue, isNotNull);
      expect(issue!.level, IssueLevel.warning);
      expect(result.canExport, isTrue);
    });

    test('环境音选「无」却有补充说明 → 警告', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主站在窗前',
            ambientSound: AppConstants.noneOption,
            ambientSoundNote: '远处有车流',
          ),
          ...shots.skip(1),
        ],
      ));

      expect(result.issueOf(ValidationCode.ambientNoneWithNote)?.level, IssueLevel.warning);
    });

    test('背景音乐选「无」却有补充说明 → 警告', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主站在窗前',
            bgm: AppConstants.noneOption,
            bgmNote: '只留环境声',
          ),
          ...shots.skip(1),
        ],
      ));

      expect(result.issueOf(ValidationCode.bgmNoneWithNote)?.level, IssueLevel.warning);
    });

    test('镜头运动为空但有镜头补充 → 警告', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主站在窗前',
            cameraMoveNote: '缓慢推进到面部',
          ),
          ...shots.skip(1),
        ],
      ));

      expect(result.issueOf(ValidationCode.cameraNoteWithoutMove)?.level, IssueLevel.warning);
    });

    test('台词时长超出分镜时长 → 警告', () {
      final result = Validators.validate(buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主开口',
            duration: 1,
            dialogue: '我知道你一定会回来找我谈这件事情',
          ),
          shots[1].copyWith(duration: 14),
          ...shots.skip(2),
        ],
      ));

      final issue = result.issueOf(ValidationCode.dialogueExceedsShot);
      expect(issue, isNotNull);
      expect(issue!.level, IssueLevel.warning);
      expect(issue.message, contains('超出'));
    });
  });

  group('校验中心 · 提示级（文档 13：不影响导出）', () {
    test('角色库中存在从未被引用的角色 → 提示', () {
      final result = Validators.validate(buildProject(
        characters: [maleLead(), Character.create(name: '旁白')],
        mutateShots: (shots) => [shots[0].copyWith(subjectAction: '男主站在窗前'), ...shots.skip(1)],
      ));

      final issue = result.issueOf(ValidationCode.unusedCharacter);
      expect(issue, isNotNull);
      expect(issue!.level, IssueLevel.info);
      expect(result.canExport, isTrue);
    });

    test('一致性冲突未处理 → 提示；已忽略或已确认的不计', () {
      const pending = ConsistencyIssue(
        type: ConsistencyIssueType.costume,
        level: IssueLevel.warning,
        shotOrders: [3],
        message: '服装不一致',
      );

      final withPending = Validators.validate(
        buildProject(mutateShots: (shots) => [shots[0].copyWith(subjectAction: 'x'), ...shots.skip(1)]),
        consistencyIssues: [pending],
      );
      final withIgnored = Validators.validate(
        buildProject(mutateShots: (shots) => [shots[0].copyWith(subjectAction: 'x'), ...shots.skip(1)]),
        consistencyIssues: [pending.copyWith(ignored: true)],
      );

      expect(withPending.codes, contains(ValidationCode.pendingConsistencyIssue));
      expect(withIgnored.codes, isNot(contains(ValidationCode.pendingConsistencyIssue)));
    });
  });

  group('一致性检查 · 以角色库为基准（文档 4.4 / 10.1）', () {
    const service = ConsistencyService();

    test('服装与角色库默认服装矛盾时报冲突，并给出定位与建议', () {
      final character = maleLead(costume: '深色风衣');
      final project = buildProject(
        characters: [character],
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主推门而入',
            dialogueCharacterId: character.id,
            dialogueCharacterName: character.name,
            keepConsistent: '白色衬衫',
          ),
          ...shots.skip(1),
        ],
      );

      final issues = service.check(project);
      final costumeIssue = issues.firstWhere((i) => i.type == ConsistencyIssueType.costume);

      expect(costumeIssue.shotOrders, [1]);
      expect(costumeIssue.characterId, character.id);
      expect(costumeIssue.message, contains('白色衬衫'));
      expect(costumeIssue.message, contains('深色风衣'));
      expect(costumeIssue.suggestion, isNotEmpty);
    });

    test('服装与角色库一致时不报冲突', () {
      final character = maleLead(costume: '深色风衣');
      final project = buildProject(
        characters: [character],
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主推门而入',
            dialogueCharacterId: character.id,
            keepConsistent: '深色风衣不变',
          ),
          ...shots.skip(1),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.costume), isEmpty);
    });

    test('同一角色在不同分镜称呼不一致时报冲突', () {
      final character = maleLead();
      final project = buildProject(
        characters: [character],
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '开场',
            dialogueCharacterId: character.id,
            dialogueCharacterName: '男主',
            dialogue: '走吧',
          ),
          shots[1].copyWith(
            subjectAction: '中段',
            dialogueCharacterId: character.id,
            dialogueCharacterName: '阿明',
            dialogue: '等等',
          ),
          ...shots.skip(2),
        ],
      );

      final issues = service.check(project).where((i) => i.type == ConsistencyIssueType.role).toList();

      expect(issues, isNotEmpty);
      expect(issues.first.shotOrders, containsAll(<int>[1, 2]));
    });

    test('外貌特征左右矛盾时报冲突（伤疤位置）', () {
      final character = maleLead(appearance: '短发·瘦高，左脸有旧伤疤');
      final project = buildProject(
        characters: [character],
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '特写',
            dialogueCharacterId: character.id,
            keepConsistent: '右脸的伤疤清晰可见',
          ),
          ...shots.skip(1),
        ],
      );

      final issues = service.check(project).where((i) => i.type == ConsistencyIssueType.feature).toList();

      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('伤疤'));
    });

    test('关闭服装维度开关后不再检测服装冲突（文档 10.1 可配置）', () {
      final character = maleLead(costume: '深色风衣');
      final project = buildProject(
        characters: [character],
        rules: const ConsistencyRules(checkCostume: false),
        mutateShots: (shots) => [
          shots[0].copyWith(
            subjectAction: '男主推门而入',
            dialogueCharacterId: character.id,
            keepConsistent: '白色衬衫',
          ),
          ...shots.skip(1),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.costume), isEmpty);
    });
  });

  group('一致性检查 · 以分镜内容为基准（文档 10.1）', () {
    const service = ConsistencyService();

    test('相邻分镜光线突变且未交代转场 → 提示', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '室内对话', lightingMood: '冷蓝光'),
          shots[1].copyWith(subjectAction: '继续对话', lightingMood: '暖黄光'),
          ...shots.skip(2),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.light), isNotEmpty);
    });

    test('已交代转场时不报光线突变', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '室内对话', lightingMood: '冷蓝光'),
          shots[1].copyWith(
            subjectAction: '继续对话',
            lightingMood: '暖黄光',
            backgroundChange: '转场到次日清晨的厨房',
          ),
          ...shots.skip(2),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.light), isEmpty);
    });

    test('白天与夜晚交替且未交代时间跳转 → 冲突', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '街道行走', backgroundChange: '正午的街道'),
          shots[1].copyWith(subjectAction: '街道行走', backgroundChange: '深夜的街道'),
          ...shots.skip(2),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.time), isNotEmpty);
    });

    test('交代了「翌日」等时间跳转时不报时间冲突', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '街道行走', backgroundChange: '正午的街道'),
          shots[1].copyWith(subjectAction: '街道行走', backgroundChange: '翌日深夜的街道'),
          ...shots.skip(2),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.time), isEmpty);
    });

    test('场景已变化但环境音沿用上一个分镜 → 提示', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '窗边', ambientSound: '雨声'),
          shots[1].copyWith(
            subjectAction: '走出大楼',
            backgroundChange: '切到地下车库',
            ambientSound: '雨声',
          ),
          ...shots.skip(2),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.ambient), isNotEmpty);
    });

    test('背景音乐情绪与画面光线氛围相反 → 提示', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '婚礼现场', lightingMood: '暖黄光', bgm: '悲伤'),
          ...shots.skip(1),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.bgm), isNotEmpty);
    });

    test('道具中途消失又出现且未交代 → 提示', () {
      final project = buildProject(
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '收起雨伞走进门'),
          shots[1].copyWith(subjectAction: '坐下喝水'),
          shots[2].copyWith(subjectAction: '举起雨伞离开'),
          shots[3],
        ],
      );

      final issues = service.check(project).where((i) => i.type == ConsistencyIssueType.prop).toList();

      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('雨伞'));
    });

    test('禁用的分镜不参与一致性检查（文档 5.2）', () {
      final character = maleLead(costume: '深色风衣');
      final project = buildProject(
        characters: [character],
        mutateShots: (shots) => [
          shots[0].copyWith(subjectAction: '开场'),
          shots[1].copyWith(
            enabled: false,
            subjectAction: '中段',
            dialogueCharacterId: character.id,
            keepConsistent: '白色衬衫',
          ),
          ...shots.skip(2),
        ],
      );

      expect(service.check(project).where((i) => i.type == ConsistencyIssueType.costume), isEmpty);
    });
  });
}
