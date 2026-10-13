/// 全局常量与枚举。
///
/// 数值口径来自仓库根目录 `README.md` 开发文档：
/// - 第六章 6.1 基本约束（总时长 15 秒、分镜 4 个、单分镜最小 1 秒）
/// - 第七章 7.1 语速规则（默认 200 字/分钟）
/// - 第八章 8.1 自动保存（700ms 防抖）
/// - 第十六章 16.5 数据迁移（schemaVersion）
library;

class AppConstants {
  AppConstants._();

  /// 默认总时长（秒）
  static const double defaultTotalDuration = 15.0;

  /// 默认分镜数量
  static const int defaultShotCount = 4;

  /// 单个分镜最小时长（秒）
  static const double minShotDuration = 1.0;

  /// 总时长可调范围（秒），文档 3.3：建议 5–60 秒
  static const double minTotalDuration = 5.0;
  static const double maxTotalDuration = 60.0;

  /// 默认中文语速（字/分钟），约 3.3 字/秒
  static const double defaultSpeechRate = 200.0;

  /// 当前数据结构版本；1 = 台词角色为纯文本，2 = 台词角色引用角色库
  static const int currentSchemaVersion = 2;

  /// 自动保存防抖时长（毫秒）
  static const int autoSaveDebounceMs = 700;

  /// 撤销栈上限，文档 8.3：撤销历史在进程内维护，不无限增长
  static const int undoStackLimit = 50;

  /// 台词预估时长达到分镜时长的该比例即判定为「时间偏紧」
  static const double tightDialogueRatio = 0.8;

  /// 英文单词折算成中文字符数的权重。
  /// 文档 7.1 只规定「中文按字符估算，英文按单词估算」，未给折算系数；
  /// 取 1.5 相当于英文约 133 词/分钟，接近正常口播语速。
  static const double englishWordWeight = 1.5;

  /// 时长计算与显示的最小粒度（秒）
  static const double durationGranularity = 0.1;

  /// 复制项目时的标题后缀，文档第十二章「复制项目 → 生成副本」
  static const String duplicateSuffix = ' 副本';

  /// 下拉选项中表示「不使用」的值，文档 17.2：选「无」不输出
  static const String noneOption = '无';

  /// 项目文件后缀
  static const String projectFileExtension = 'json';

  /// JSON 损坏时保留原文件并生成的备份后缀，文档 8.2
  static const String corruptFileSuffix = '.corrupt';

  /// 草稿文件后缀
  static const String draftFileSuffix = '.draft';
}

/// 导出格式，文档 3.7 / 17.6
enum ExportFormat {
  markdown('Markdown', 'md'),
  txt('TXT', 'txt'),
  json('JSON', 'json');

  const ExportFormat(this.label, this.extension);

  final String label;
  final String extension;

  static ExportFormat fromName(String? value) {
    for (final format in ExportFormat.values) {
      if (format.name == value || format.label == value) return format;
    }
    return ExportFormat.markdown;
  }
}
