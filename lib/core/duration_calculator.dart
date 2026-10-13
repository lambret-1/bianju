import '../models/shot_block.dart';
import 'constants.dart';
import 'dialogue_duration_estimator.dart';
import 'time_utils.dart';

/// 总时长变化后的重算策略，文档 6.2「修改总时长 → 提示平均分配或按比例重算」
enum DurationStrategy {
  /// 平均分配：忽略原有时长，所有可调分镜均分
  evenly,

  /// 按比例重算：保持原有比例缩放
  proportionally,
}

/// 时长联动计算，文档第六章。
///
/// 不变量：所有**启用**分镜时长之和等于总时长；单分镜最小 1 秒，最大不超过总时长。
/// 「最后一个未锁定的启用分镜」承担四舍五入误差与自动补齐（下称吸收位）。
class DurationCalculator {
  DurationCalculator._();

  /// 已用时长 = 启用分镜时长之和（禁用分镜不计入）
  static double used(List<ShotBlock> shots) => TimeUtils.round1(_sumEnabled(shots));

  /// 剩余时长 = 总时长 - 已用时长，可为负（文档 6.3：为负标红）
  static double remaining(double total, List<ShotBlock> shots) =>
      TimeUtils.round1(total - used(shots));

  /// 总时长是否匹配；不匹配时导出按钮置灰（文档 6.3 / 十五）
  static bool isBalanced(double total, List<ShotBlock> shots) =>
      remaining(total, shots).abs() < AppConstants.durationGranularity / 2;

  /// 台词预估总时长；语速优先取角色，缺省用项目默认语速（文档 4.5）
  static double dialogueTotal(
    List<ShotBlock> shots, {
    double defaultSpeechRate = AppConstants.defaultSpeechRate,
    Map<String, double> speechRateByCharacterId = const <String, double>{},
  }) {
    var total = 0.0;
    for (final shot in shots) {
      if (!shot.enabled) continue;
      total += DialogueDurationEstimator.estimateForShot(
        shot,
        characterSpeechRate: speechRateByCharacterId[shot.dialogueCharacterId],
        defaultSpeechRate: defaultSpeechRate,
      );
    }
    return TimeUtils.round1(total);
  }

  /// 平均分配：锁定的分镜保留原时长，其余可调分镜均分剩余额度，余数落到吸收位
  static List<ShotBlock> distributeEvenly(List<ShotBlock> shots, double total) {
    final targets = _adjustableIndexes(shots);
    if (targets.isEmpty) return List<ShotBlock>.of(shots);

    final pool = TimeUtils.round1(total - _enabledLockedSum(shots));
    final floor = AppConstants.minShotDuration * targets.length;
    if (pool < floor) {
      // 额度不足以让每个分镜都达到 1 秒：全部给最小值，差额交由校验中心报错
      return _applyDurations(shots, {
        for (final index in targets) index: AppConstants.minShotDuration,
      });
    }

    final share = TimeUtils.round1(pool / targets.length);
    final values = <int, double>{};
    var assigned = 0.0;
    for (var k = 0; k < targets.length - 1; k++) {
      values[targets[k]] = share;
      assigned = TimeUtils.round1(assigned + share);
    }
    values[targets.last] = TimeUtils.round1(pool - assigned);
    return _applyDurations(shots, values);
  }

  /// 按比例重算：保持原有比例缩放，锁定分镜不动，吸收位消化四舍五入误差
  static List<ShotBlock> distributeProportionally(List<ShotBlock> shots, double total) {
    final targets = _adjustableIndexes(shots);
    if (targets.isEmpty) return List<ShotBlock>.of(shots);

    final pool = TimeUtils.round1(total - _enabledLockedSum(shots));
    final targetsSum =
        TimeUtils.round1(targets.fold<double>(0, (sum, i) => sum + shots[i].duration));
    if (targetsSum <= 0) return distributeEvenly(shots, total);

    final scale = pool / targetsSum;
    final values = <int, double>{};
    var assigned = 0.0;
    for (var k = 0; k < targets.length - 1; k++) {
      final index = targets[k];
      final value = _atLeastMin(TimeUtils.round1(shots[index].duration * scale));
      values[index] = value;
      assigned = TimeUtils.round1(assigned + value);
    }
    values[targets.last] = _atLeastMin(TimeUtils.round1(pool - assigned));
    return _applyDurations(shots, values);
  }

  /// 按策略应用新的总时长
  static List<ShotBlock> applyTotalDuration(
    List<ShotBlock> shots,
    double total, {
    DurationStrategy strategy = DurationStrategy.proportionally,
  }) {
    return strategy == DurationStrategy.evenly
        ? distributeEvenly(shots, total)
        : distributeProportionally(shots, total);
  }

  /// 修改某个分镜时长后自动调整吸收位补齐总时长（文档 6.2）。
  /// 若补齐会让吸收位低于 1 秒，则拒绝本次修改并返回原列表。
  static List<ShotBlock> setShotDuration(
    List<ShotBlock> shots, {
    required int index,
    required double value,
    required double total,
  }) {
    if (index < 0 || index >= shots.length) return List<ShotBlock>.of(shots);
    final target = shots[index];
    // 锁定分镜与禁用分镜不参与时长调整（文档 6.2）
    if (!target.enabled || target.durationLocked) return List<ShotBlock>.of(shots);

    final requested = TimeUtils.clampShotDuration(value, total: total);
    final next = List<ShotBlock>.of(shots);
    next[index] = target.copyWith(duration: requested);

    final absorber = _absorberIndex(next, exclude: index);
    if (absorber == null) return next;

    final othersSum = TimeUtils.round1(_sumEnabledExcept(next, absorber));
    final absorberValue = TimeUtils.round1(total - othersSum);
    if (absorberValue < AppConstants.minShotDuration) return List<ShotBlock>.of(shots);

    next[absorber] = next[absorber].copyWith(duration: absorberValue);
    return next;
  }

  /// 新增分镜：优先占用剩余时长，剩余不足时从吸收位腾出 1 秒（文档 6.2）
  static List<ShotBlock> addShot(List<ShotBlock> shots, {required double total}) {
    final min = AppConstants.minShotDuration;
    final free = remaining(total, shots);
    if (free >= min) {
      return <ShotBlock>[
        ...shots,
        ShotBlock.create(orderIndex: shots.length, duration: TimeUtils.round1(free)),
      ];
    }

    final absorber = _absorberIndex(shots);
    if (absorber == null) {
      return <ShotBlock>[...shots, ShotBlock.create(orderIndex: shots.length, duration: min)];
    }

    final need = TimeUtils.round1(min - (free > 0 ? free : 0));
    final donorValue = TimeUtils.round1(shots[absorber].duration - need);
    if (donorValue < min) {
      // 腾不出时长：仍然新增（保证操作可用），差额由校验中心提示
      return <ShotBlock>[...shots, ShotBlock.create(orderIndex: shots.length, duration: min)];
    }

    final next = List<ShotBlock>.of(shots);
    next[absorber] = next[absorber].copyWith(duration: donorValue);
    next.add(ShotBlock.create(orderIndex: next.length, duration: min));
    return next;
  }

  /// 删除分镜后剩余时长重新分配（文档 6.2）
  static List<ShotBlock> removeShot(
    List<ShotBlock> shots, {
    required int index,
    required double total,
  }) {
    if (index < 0 || index >= shots.length) return List<ShotBlock>.of(shots);
    final next = List<ShotBlock>.of(shots)..removeAt(index);
    if (next.isEmpty) return next;
    return rebalance(next, total);
  }

  /// 复制分镜：复制全部字段作为新分镜插入，随后按比例回收时长（文档 5.1 / 5.2）
  static List<ShotBlock> duplicateShot(
    List<ShotBlock> shots, {
    required int index,
    required double total,
  }) {
    if (index < 0 || index >= shots.length) return List<ShotBlock>.of(shots);
    final next = List<ShotBlock>.of(shots)..insert(index + 1, shots[index].duplicate());
    return rebalance(next, total);
  }

  /// 启用/禁用分镜后按比重算，使启用分镜合计仍等于总时长（文档 6.2）
  static List<ShotBlock> setEnabled(
    List<ShotBlock> shots, {
    required int index,
    required bool enabled,
    required double total,
  }) {
    if (index < 0 || index >= shots.length) return List<ShotBlock>.of(shots);
    final next = List<ShotBlock>.of(shots);
    next[index] = next[index].copyWith(enabled: enabled);
    return distributeProportionally(next, total);
  }

  /// 拖拽排序：兼容 ReorderableListView 的 oldIndex/newIndex 语义，并重排编号与时间标记
  static List<ShotBlock> reorder(List<ShotBlock> shots, int oldIndex, int newIndex) {
    if (shots.isEmpty || oldIndex < 0 || oldIndex >= shots.length) {
      return List<ShotBlock>.of(shots);
    }
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, shots.length - 1);

    final next = List<ShotBlock>.of(shots);
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    return TimeUtils.assignTimeMarks(next);
  }

  /// 上移/下移一格
  static List<ShotBlock> move(List<ShotBlock> shots, int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= shots.length) return List<ShotBlock>.of(shots);
    if (target < 0 || target >= shots.length) return List<ShotBlock>.of(shots);
    return reorder(shots, index, delta > 0 ? index + 2 : target);
  }

  /// 把差额补给吸收位；吸收位会低于 1 秒时改为按比重算
  static List<ShotBlock> rebalance(List<ShotBlock> shots, double total) {
    final absorber = _absorberIndex(shots);
    if (absorber == null) return List<ShotBlock>.of(shots);

    final othersSum = TimeUtils.round1(_sumEnabledExcept(shots, absorber));
    final value = TimeUtils.round1(total - othersSum);
    if (value < AppConstants.minShotDuration) {
      return distributeProportionally(shots, total);
    }

    final next = List<ShotBlock>.of(shots);
    next[absorber] = next[absorber].copyWith(duration: value);
    return next;
  }

  // ---------------------------------------------------------------- 内部工具

  static double _sumEnabled(List<ShotBlock> shots) {
    var sum = 0.0;
    for (final shot in shots) {
      if (shot.enabled) sum += shot.duration;
    }
    return sum;
  }

  static double _sumEnabledExcept(List<ShotBlock> shots, int excludeIndex) {
    var sum = 0.0;
    for (var i = 0; i < shots.length; i++) {
      if (i == excludeIndex) continue;
      if (shots[i].enabled) sum += shots[i].duration;
    }
    return sum;
  }

  static double _enabledLockedSum(List<ShotBlock> shots) {
    var sum = 0.0;
    for (final shot in shots) {
      if (shot.enabled && shot.durationLocked) sum += shot.duration;
    }
    return TimeUtils.round1(sum);
  }

  /// 可参与自动分配的下标：启用且未锁定（文档 6.2「锁定分镜时长 → 不参与自动分配」）
  static List<int> _adjustableIndexes(List<ShotBlock> shots) {
    return <int>[
      for (var i = 0; i < shots.length; i++)
        if (shots[i].enabled && !shots[i].durationLocked) i,
    ];
  }

  /// 吸收位：优先取最后一个「启用且未锁定」的分镜，可排除指定下标
  static int? _absorberIndex(List<ShotBlock> shots, {int? exclude}) {
    for (var i = shots.length - 1; i >= 0; i--) {
      if (i == exclude) continue;
      if (shots[i].enabled && !shots[i].durationLocked) return i;
    }
    for (var i = 0; i < shots.length; i++) {
      if (i == exclude) continue;
      if (shots[i].enabled && !shots[i].durationLocked) return i;
    }
    return null;
  }

  static List<ShotBlock> _applyDurations(List<ShotBlock> shots, Map<int, double> values) {
    final next = List<ShotBlock>.of(shots);
    values.forEach((index, value) {
      if (index < 0 || index >= next.length) return;
      next[index] = next[index].copyWith(duration: TimeUtils.round1(value));
    });
    return next;
  }

  static double _atLeastMin(double value) =>
      value < AppConstants.minShotDuration ? AppConstants.minShotDuration : value;
}
