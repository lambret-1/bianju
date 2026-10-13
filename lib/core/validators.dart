import '../models/consistency_issue.dart';
import '../models/project.dart';
import '../models/shot_block.dart';
import 'constants.dart';
import 'dialogue_duration_estimator.dart';
import 'time_utils.dart';

/// 校验项编码，与文档第十三章「统一校验中心」的表格逐条对应。
/// 每个编码自带默认级别：错误禁止导出，警告允许导出但提示风险，提示不影响导出。
enum ValidationCode {
  allShotsEmpty('所有启用分镜均为空', IssueLevel.error),
  shotTooShort('分镜时长小于 1 秒', IssueLevel.error),
  totalMismatch('总时长不匹配', IssueLevel.error),
  brokenCharacterReference('台词角色引用失效', IssueLevel.error),
  characterWithoutDialogue('有台词角色但无台词', IssueLevel.warning),
  ambientNoneWithNote('环境音选「无」却有补充说明', IssueLevel.warning),
  bgmNoneWithNote('背景音乐选「无」却有补充说明', IssueLevel.warning),
  cameraNoteWithoutMove('镜头运动为空但有镜头补充', IssueLevel.warning),
  dialogueExceedsShot('台词时长超出分镜时长', IssueLevel.warning),
  unusedCharacter('角色库中存在从未被引用的角色', IssueLevel.info),
  pendingConsistencyIssue('一致性冲突未处理', IssueLevel.info);

  const ValidationCode(this.label, this.level);

  final String label;
  final IssueLevel level;
}

/// 一条校验结果
class ValidationIssue {
  const ValidationIssue({
    required this.code,
    required this.message,
    this.shotNumber,
    this.characterId = '',
  });

  final ValidationCode code;
  final String message;

  /// 问题所在分镜编号（从 1 开始），供「一键定位」使用；项目级问题为 null
  final int? shotNumber;

  /// 问题涉及的角色 id，供「打开角色库」定位使用
  final String characterId;

  IssueLevel get level => code.level;

  /// 是否阻断导出
  bool get blocksExport => level == IssueLevel.error;
}

/// 校验汇总
class ValidationResult {
  const ValidationResult({required this.issues});

  final List<ValidationIssue> issues;

  List<ValidationCode> get codes =>
      issues.map((issue) => issue.code).toList(growable: false);

  List<ValidationIssue> get errors => _ofLevel(IssueLevel.error);
  List<ValidationIssue> get warnings => _ofLevel(IssueLevel.warning);
  List<ValidationIssue> get infos => _ofLevel(IssueLevel.info);

  int get errorCount => errors.length;
  int get warningCount => warnings.length;
  int get infoCount => infos.length;

  /// 只有不存在错误级问题时才允许导出（文档第十三章）
  bool get canExport => errors.isEmpty;

  bool get isEmpty => issues.isEmpty;

  /// 取某个编码的第一条问题，便于测试与界面定位
  ValidationIssue? issueOf(ValidationCode code) {
    for (final issue in issues) {
      if (issue.code == code) return issue;
    }
    return null;
  }

  List<ValidationIssue> _ofLevel(IssueLevel level) =>
      issues.where((issue) => issue.level == level).toList(growable: false);
}

/// 统一校验中心，文档第十三章。
///
/// 导出前必须通过校验。一致性冲突由 [ConsistencyService] 产出后传入，
/// 本类只负责把「未处理的冲突」折算为提示级校验项。
class Validators {
  Validators._();

  static ValidationResult validate(
    Project project, {
    List<ConsistencyIssue> consistencyIssues = const <ConsistencyIssue>[],
  }) {
    final issues = <ValidationIssue>[];
    final enabled = project.enabledShots;

    _checkShotsNotEmpty(enabled, issues);
    _checkShotDurations(enabled, issues);
    _checkTotalDuration(project, issues);
    _checkCharacterReferences(project, enabled, issues);
    _checkDialogueFields(project, enabled, issues);
    _checkOptionNotes(enabled, issues);
    _checkUnusedCharacters(project, issues);
    _checkPendingConsistency(consistencyIssues, issues);

    return ValidationResult(issues: List<ValidationIssue>.unmodifiable(issues));
  }

  /// 所有启用分镜是否全空 → 错误
  static void _checkShotsNotEmpty(List<ShotBlock> enabled, List<ValidationIssue> issues) {
    if (enabled.isEmpty || enabled.every((shot) => !shot.hasContent)) {
      issues.add(const ValidationIssue(
        code: ValidationCode.allShotsEmpty,
        message: '所有启用分镜均为空，暂无可导出内容',
      ));
    }
  }

  /// 分镜时长是否小于 1 秒 → 错误（只校验启用分镜）
  static void _checkShotDurations(List<ShotBlock> enabled, List<ValidationIssue> issues) {
    for (final shot in enabled) {
      if (shot.duration < AppConstants.minShotDuration) {
        issues.add(ValidationIssue(
          code: ValidationCode.shotTooShort,
          shotNumber: shot.displayNumber,
          message: '分镜 ${shot.displayNumber} 时长 ${TimeUtils.formatDuration(shot.duration)}，'
              '小于最小 ${TimeUtils.formatDuration(AppConstants.minShotDuration)}',
        ));
      }
    }
  }

  /// 总时长是否匹配 → 错误
  static void _checkTotalDuration(Project project, List<ValidationIssue> issues) {
    if (project.isDurationBalanced) return;
    issues.add(ValidationIssue(
      code: ValidationCode.totalMismatch,
      message: '启用分镜合计 ${TimeUtils.formatDuration(project.usedDuration)}，'
          '与总时长 ${TimeUtils.formatDuration(project.totalDuration)} 不匹配',
    ));
  }

  /// 台词角色引用了已删除/失效的角色 → 错误
  static void _checkCharacterReferences(
    Project project,
    List<ShotBlock> enabled,
    List<ValidationIssue> issues,
  ) {
    for (final shot in enabled) {
      final id = shot.dialogueCharacterId.trim();
      if (id.isEmpty) continue;
      if (project.characterById(id) != null) continue;
      issues.add(ValidationIssue(
        code: ValidationCode.brokenCharacterReference,
        shotNumber: shot.displayNumber,
        characterId: id,
        message: '分镜 ${shot.displayNumber} 的台词角色「${shot.dialogueCharacterName}」'
            '在角色库中已不存在',
      ));
    }
  }

  /// 有台词角色但无台词 → 警告；台词时长超出分镜时长 → 警告
  static void _checkDialogueFields(
    Project project,
    List<ShotBlock> enabled,
    List<ValidationIssue> issues,
  ) {
    for (final shot in enabled) {
      final hasCharacter = shot.dialogueCharacterId.trim().isNotEmpty ||
          shot.dialogueCharacterName.trim().isNotEmpty;
      final dialogue = shot.dialogue.trim();

      if (hasCharacter && dialogue.isEmpty) {
        issues.add(ValidationIssue(
          code: ValidationCode.characterWithoutDialogue,
          shotNumber: shot.displayNumber,
          characterId: shot.dialogueCharacterId,
          message: '分镜 ${shot.displayNumber} 选了台词角色'
              '「${shot.dialogueCharacterName}」但没有台词内容',
        ));
        continue;
      }
      if (dialogue.isEmpty) continue;

      final character = project.characterById(shot.dialogueCharacterId);
      final estimated = DialogueDurationEstimator.estimateForShot(
        shot,
        characterSpeechRate: character?.speechRate,
        defaultSpeechRate: project.defaultSpeechRate,
      );
      final status = DialogueDurationEstimator.status(estimated, shot.duration);
      if (status.isExceeded) {
        issues.add(ValidationIssue(
          code: ValidationCode.dialogueExceedsShot,
          shotNumber: shot.displayNumber,
          characterId: shot.dialogueCharacterId,
          message: '分镜 ${shot.displayNumber} 台词预估 '
              '${TimeUtils.formatDuration(estimated)}，超出分镜时长 '
              '${TimeUtils.formatDuration(status.overflowSeconds)}',
        ));
      }
    }
  }

  /// 环境音/背景音乐选「无」却有补充说明、镜头运动为空但有镜头补充 → 警告
  static void _checkOptionNotes(List<ShotBlock> enabled, List<ValidationIssue> issues) {
    for (final shot in enabled) {
      final number = shot.displayNumber;
      if (shot.ambientSound.trim() == AppConstants.noneOption &&
          shot.ambientSoundNote.trim().isNotEmpty) {
        issues.add(ValidationIssue(
          code: ValidationCode.ambientNoneWithNote,
          shotNumber: number,
          message: '分镜 $number 环境音选了「${AppConstants.noneOption}」却填写了补充说明',
        ));
      }
      if (shot.bgm.trim() == AppConstants.noneOption && shot.bgmNote.trim().isNotEmpty) {
        issues.add(ValidationIssue(
          code: ValidationCode.bgmNoneWithNote,
          shotNumber: number,
          message: '分镜 $number 背景音乐选了「${AppConstants.noneOption}」却填写了补充说明',
        ));
      }
      if (shot.cameraMove.trim().isEmpty && shot.cameraMoveNote.trim().isNotEmpty) {
        issues.add(ValidationIssue(
          code: ValidationCode.cameraNoteWithoutMove,
          shotNumber: number,
          message: '分镜 $number 未选择镜头运动却填写了镜头补充说明',
        ));
      }
    }
  }

  /// 角色库中存在从未被引用的角色 → 提示
  static void _checkUnusedCharacters(Project project, List<ValidationIssue> issues) {
    for (final character in project.unreferencedCharacters) {
      issues.add(ValidationIssue(
        code: ValidationCode.unusedCharacter,
        characterId: character.id,
        message: '角色「${character.displayName}」建档后从未被任何分镜引用',
      ));
    }
  }

  /// 一致性冲突未处理 → 提示（已忽略或已确认的不计）
  static void _checkPendingConsistency(
    List<ConsistencyIssue> consistencyIssues,
    List<ValidationIssue> issues,
  ) {
    for (final issue in consistencyIssues) {
      if (!issue.isPending) continue;
      issues.add(ValidationIssue(
        code: ValidationCode.pendingConsistencyIssue,
        shotNumber: issue.shotOrders.isEmpty ? null : issue.shotOrders.first,
        characterId: issue.characterId,
        message: '${issue.type.label}一致性冲突未处理：${issue.message}',
      ));
    }
  }
}
