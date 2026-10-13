import '../models/shot_block.dart';
import 'constants.dart';

/// 时间与时间标记计算，文档第十五章「时间规则」、6.3「时长条实时提示」。
///
/// 时间标记由系统生成，分镜增删、排序、改时长后自动重排；
/// 禁用的分镜不占时间轴，标记为空。
class TimeUtils {
  TimeUtils._();

  /// 按 0.1 秒粒度四舍五入（远离零方向），消除浮点累加误差
  static double round1(double value) {
    if (!value.isFinite) return 0;
    return (value * 10).round() / 10;
  }

  /// 秒数格式化为 mm:ss，如 4 → `00:04`，65 → `01:05`
  static String formatClock(double seconds) {
    final safe = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
    final minutes = safe ~/ 60;
    final rest = safe % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }

  /// 时间标记区间，如 `00:04-00:08`；[spaced] 为 true 时输出 `00:04 - 00:08`（导出用，文档 17.5）
  static String formatRange(double startSeconds, double endSeconds, {bool spaced = false}) {
    final separator = spaced ? ' - ' : '-';
    return '${formatClock(startSeconds)}$separator${formatClock(endSeconds)}';
  }

  /// 时长显示，如 `4s` / `13.5s`
  static String formatDuration(double seconds) {
    final value = round1(seconds);
    if (value == value.roundToDouble()) return '${value.toInt()}s';
    return '${value.toStringAsFixed(1)}s';
  }

  /// 重排 orderIndex 与 timeMark：
  /// - orderIndex 按当前列表顺序连续编号（含禁用分镜，保证界面编号稳定）；
  /// - timeMark 只在启用分镜之间连续推进。
  static List<ShotBlock> assignTimeMarks(List<ShotBlock> shots) {
    final result = <ShotBlock>[];
    var cursor = 0.0;
    for (var i = 0; i < shots.length; i++) {
      final shot = shots[i];
      if (!shot.enabled) {
        result.add(shot.copyWith(orderIndex: i, timeMark: ''));
        continue;
      }
      final start = cursor;
      cursor = round1(cursor + shot.duration);
      result.add(shot.copyWith(orderIndex: i, timeMark: formatRange(start, cursor)));
    }
    return result;
  }

  /// 把时长限制在合法区间内（最小 1 秒，最大不超过总时长）
  static double clampShotDuration(double value, {double? total}) {
    var result = round1(value);
    if (result < AppConstants.minShotDuration) result = AppConstants.minShotDuration;
    if (total != null && result > total) result = total;
    return result;
  }
}
