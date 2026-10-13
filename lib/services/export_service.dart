import 'dart:convert';

import '../core/constants.dart';
import '../core/time_utils.dart';
import '../models/character.dart';
import '../models/project.dart';
import '../models/shot_block.dart';
import '../storage/storage_io.dart';

/// 没有可导出内容时抛出（文档 17.1）
class EmptyExportException implements Exception {
  const EmptyExportException([this.message = '暂无可导出内容']);

  final String message;

  @override
  String toString() => message;
}

/// 一次导出的结果
class ExportResult {
  const ExportResult({
    required this.format,
    required this.content,
    required this.fileName,
  });

  final ExportFormat format;
  final String content;

  /// 文件名：{项目标题}_{格式}_{日期}.{后缀}（文档 17.6）
  final String fileName;
}

/// 导出用的分镜与其时间标记
class _ExportShot {
  const _ExportShot({required this.shot, required this.timeMark});

  final ShotBlock shot;
  final String timeMark;
}

/// 导出服务，文档第十七章。
///
/// 核心约束（文档 17.1 / 17.2）：
/// - 只输出「启用且有内容」的分镜；
/// - 字段级严格「有内容才输出」：空字段不输出 null、不输出「未填写」、不输出空行；
/// - 环境音/背景音乐选「无」或空值不输出，有补充说明则拼在选项名后面；
/// - JSON 完整保留角色库与 dialogueCharacterId，保证导入后引用关系不丢。
class ExportService {
  const ExportService();

  /// 按格式导出；[format] 为空时用项目设置的导出格式
  ExportResult export(Project project, {ExportFormat? format, DateTime? now}) {
    final resolved = format ?? project.exportFormatValue;
    if (project.exportableShots.isEmpty) throw const EmptyExportException();

    final content = switch (resolved) {
      ExportFormat.markdown => toMarkdown(project),
      ExportFormat.txt => toText(project),
      ExportFormat.json => toJson(project),
    };
    return ExportResult(
      format: resolved,
      content: content,
      fileName: fileNameFor(project, resolved, now: now),
    );
  }

  /// 文件名规则（文档 17.6）
  String fileNameFor(Project project, ExportFormat format, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final date = '${timestamp.year.toString().padLeft(4, '0')}'
        '${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}';
    final title = StorageIo.sanitizeFileName(project.title, fallback: Project.fallbackTitle);
    return '${title}_${format.label}_$date.${format.extension}';
  }

  /// Markdown 导出（文档 17.5 示例格式）
  String toMarkdown(Project project, {bool includeCharacterTable = true}) {
    final sections = <String>[];
    final characterLines = includeCharacterTable ? _characterLines(project) : const <String>[];
    if (characterLines.isNotEmpty) {
      sections.add(<String>[
        '# 角色表',
        '',
        ...characterLines.map((line) => '- $line'),
      ].join('\n'));
    }

    for (final entry in _exportableShots(project)) {
      sections.add(<String>[
        '# 分镜 ${entry.shot.displayNumber}',
        '',
        ..._fieldLines(entry).map((line) => '- $line'),
      ].join('\n'));
    }
    return sections.join('\n\n');
  }

  /// 纯文本导出：与 Markdown 同结构，去掉标题记号与列表符号
  String toText(Project project) {
    final sections = <String>[];
    final characterLines = _characterLines(project);
    if (characterLines.isNotEmpty) {
      sections.add(<String>['角色表', '', ...characterLines].join('\n'));
    }
    for (final entry in _exportableShots(project)) {
      sections.add(<String>[
        '分镜 ${entry.shot.displayNumber}',
        '',
        ..._fieldLines(entry),
      ].join('\n'));
    }
    return sections.join('\n\n');
  }

  /// JSON 导出：完整项目数据，可直接导入恢复（文档 17.3）
  String toJson(Project project) =>
      const JsonEncoder.withIndent('  ').convert(project.toJson());

  // ------------------------------------------------------------------ 内部

  /// 角色表行（文档 17.3）：姓名 + 外貌/服装/性格/备注 + 语速
  List<String> _characterLines(Project project) {
    return <String>[
      for (final character in project.characters)
        '${character.displayName}：${_characterDetail(character)}',
    ];
  }

  String _characterDetail(Character character) {
    final parts = <String>[
      for (final value in <String>[
        character.appearance,
        character.costume,
        character.personality,
        character.notes,
      ])
        if (value.trim().isNotEmpty) value.trim(),
    ];
    parts.add('语速 ${_formatNumber(character.speechRate)}');
    return parts.join('，');
  }

  /// 只保留启用且有内容的分镜，并按启用分镜顺序重算时间标记（文档 15 / 17.1）
  List<_ExportShot> _exportableShots(Project project) {
    final result = <_ExportShot>[];
    var cursor = 0.0;
    for (final shot in project.shots) {
      if (!shot.enabled) continue;
      final start = cursor;
      cursor = TimeUtils.round1(cursor + shot.duration);
      if (!shot.hasContent) continue;
      result.add(_ExportShot(
        shot: shot,
        timeMark: TimeUtils.formatRange(start, cursor, spaced: true),
      ));
    }
    return result;
  }

  /// 单个分镜的字段行，顺序固定；空字段一律跳过
  List<String> _fieldLines(_ExportShot entry) {
    final shot = entry.shot;
    final lines = <String>[];

    void add(String label, String value) {
      if (value.trim().isEmpty) return;
      lines.add('$label：${value.trim()}');
    }

    if (shot.duration > 0) lines.add('时长：${_formatNumber(shot.duration)} 秒');
    add('节奏', shot.pace);
    if (entry.timeMark.isNotEmpty) lines.add('时间标记：${entry.timeMark}');
    add('主体动作', shot.subjectAction);
    add('动作流程', shot.actionFlow);
    add('镜头运动', shot.cameraMove);
    add('镜头补充', shot.cameraMoveNote);
    add('背景变化', shot.backgroundChange);
    add('光线氛围', shot.lightingMood);
    add('保持特征', shot.keepConsistent);

    // 台词：只有填了台词才输出；同时选了角色则一并输出角色名（文档 17.2）
    final dialogue = shot.dialogue.trim();
    if (dialogue.isNotEmpty) {
      add('台词角色', shot.dialogueCharacterName);
      lines.add('台词：$dialogue');
    }

    add('环境音', _optionWithNote(shot.ambientSound, shot.ambientSoundNote));
    add('背景音乐', _optionWithNote(shot.bgm, shot.bgmNote));
    return lines;
  }

  /// 选项 + 补充说明；选「无」或空值时返回空串（文档 17.2）
  String _optionWithNote(String value, String note) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == AppConstants.noneOption) return '';
    final extra = note.trim();
    return extra.isEmpty ? trimmed : '$trimmed（$extra）';
  }

  String _formatNumber(double value) {
    final rounded = TimeUtils.round1(value);
    if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
    return rounded.toStringAsFixed(1);
  }
}
