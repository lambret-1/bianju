import '../models/shot_block.dart';
import 'constants.dart';
import 'time_utils.dart';

/// 台词时长估算结果的状态种类，文档 7.3「状态规则」
enum DialogueStatusKind {
  /// 台词为空，不计算预估时长
  empty,

  /// 台词时长 <= 分镜时长且未接近上限：绿色「时间充足」
  sufficient,

  /// 台词时长接近分镜时长：黄色「时间偏紧」
  tight,

  /// 台词时长 > 分镜时长：红色「超出 X.Xs」
  exceeded,
}

/// 台词时长与分镜时长的比对结果
class DialogueStatus {
  const DialogueStatus({
    required this.kind,
    required this.estimatedSeconds,
    required this.shotDuration,
    this.overflowSeconds = 0,
  });

  final DialogueStatusKind kind;
  final double estimatedSeconds;
  final double shotDuration;

  /// 超出分镜时长的秒数，仅在 [DialogueStatusKind.exceeded] 时大于 0
  final double overflowSeconds;

  /// 界面文案，文档 7.3
  String get label => switch (kind) {
        DialogueStatusKind.empty => '未计算',
        DialogueStatusKind.sufficient => '时间充足',
        DialogueStatusKind.tight => '时间偏紧',
        DialogueStatusKind.exceeded => '超出 ${TimeUtils.formatDuration(overflowSeconds)}',
      };

  bool get isExceeded => kind == DialogueStatusKind.exceeded;
  bool get isTight => kind == DialogueStatusKind.tight;
}

/// 台词字数统计与时长估算，文档第七章。
///
/// 规则：
/// - 中文（含全角标点）按字符计数；英文按单词计数，再按
///   [AppConstants.englishWordWeight] 折算成等效字符数；
/// - 预估时长 = 等效字符数 / 语速（字/分钟）× 60，保留 0.1 秒；
/// - 语速优先取所选角色的语速（文档 4.5），缺省回落项目默认语速 200。
class DialogueDurationEstimator {
  DialogueDurationEstimator._();

  static const int _cjkUnifiedStart = 0x4E00;
  static const int _cjkUnifiedEnd = 0x9FFF;

  /// 判断是否按中文字符计数（含中日韩标点与全角符号）
  static bool isCjkRune(int rune) {
    return (rune >= _cjkUnifiedStart && rune <= _cjkUnifiedEnd) ||
        (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展 A
        (rune >= 0x3000 && rune <= 0x303F) || // 中日韩符号与标点
        (rune >= 0xFF00 && rune <= 0xFFEF) || // 全角/半角形式
        (rune >= 0xF900 && rune <= 0xFAFF) || // 兼容表意文字
        (rune >= 0x2E80 && rune <= 0x2EFF); // 部首补充
  }

  static bool _isSpace(int rune) =>
      rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x3000;

  /// 统计中文字符数（含全角标点），文档 7.2 算例：「你真的要走吗？」为 7
  static int charCount(String text) => _scan(text).cjkChars;

  /// 统计英文单词数
  static int wordCount(String text) => _scan(text).latinWords;

  /// 折算成等效中文字符数
  static double units(String text) {
    final counted = _scan(text);
    return counted.cjkChars + counted.latinWords * AppConstants.englishWordWeight;
  }

  /// 预估台词时长（秒）。语速非法（<= 0）时回落默认 200 字/分钟。
  static double estimate(String text, {double speechRate = AppConstants.defaultSpeechRate}) {
    final rate = speechRate > 0 ? speechRate : AppConstants.defaultSpeechRate;
    return TimeUtils.round1(units(text) / rate * 60);
  }

  /// 按分镜所选角色的语速估算；未选角色或角色未设语速时用 [defaultSpeechRate]
  static double estimateForShot(
    ShotBlock shot, {
    double? characterSpeechRate,
    double defaultSpeechRate = AppConstants.defaultSpeechRate,
  }) {
    final rate = (characterSpeechRate != null && characterSpeechRate > 0)
        ? characterSpeechRate
        : defaultSpeechRate;
    return estimate(shot.dialogue, speechRate: rate);
  }

  /// 比对台词预估时长与分镜时长，文档 7.3
  static DialogueStatus status(double estimatedSeconds, double shotDuration) {
    if (estimatedSeconds <= 0) {
      return DialogueStatus(
        kind: DialogueStatusKind.empty,
        estimatedSeconds: 0,
        shotDuration: shotDuration,
      );
    }
    if (estimatedSeconds > shotDuration) {
      return DialogueStatus(
        kind: DialogueStatusKind.exceeded,
        estimatedSeconds: estimatedSeconds,
        shotDuration: shotDuration,
        overflowSeconds: TimeUtils.round1(estimatedSeconds - shotDuration),
      );
    }
    final tight = estimatedSeconds > shotDuration * AppConstants.tightDialogueRatio;
    return DialogueStatus(
      kind: tight ? DialogueStatusKind.tight : DialogueStatusKind.sufficient,
      estimatedSeconds: estimatedSeconds,
      shotDuration: shotDuration,
    );
  }

  static _CountedText _scan(String text) {
    var cjk = 0;
    var words = 0;
    var inWord = false;
    for (final rune in text.runes) {
      if (_isSpace(rune)) {
        if (inWord) {
          words++;
          inWord = false;
        }
        continue;
      }
      if (isCjkRune(rune)) {
        if (inWord) {
          words++;
          inWord = false;
        }
        cjk++;
        continue;
      }
      inWord = true;
    }
    if (inWord) words++;
    return _CountedText(cjkChars: cjk, latinWords: words);
  }
}

class _CountedText {
  const _CountedText({required this.cjkChars, required this.latinWords});

  final int cjkChars;
  final int latinWords;
}
