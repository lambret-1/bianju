import 'package:bianju/core/constants.dart';
import 'package:bianju/core/dialogue_duration_estimator.dart';
import 'package:bianju/core/duration_calculator.dart';
import 'package:bianju/core/time_utils.dart';
import 'package:bianju/models/shot_block.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP2 核心计算测试：覆盖文档第六章时长联动、第七章台词时长与语速校验、
/// 第十五章时间规则。所有期望值均来自文档给出的算例。
void main() {
  List<ShotBlock> shots(List<double> durations, {List<int> disabled = const []}) {
    return [
      for (var i = 0; i < durations.length; i++)
        ShotBlock.create(orderIndex: i, duration: durations[i])
            .copyWith(enabled: !disabled.contains(i)),
    ];
  }

  group('TimeUtils 时间标记（文档 15 / 6.3）', () {
    test('秒数格式化为 mm:ss', () {
      expect(TimeUtils.formatClock(0), '00:00');
      expect(TimeUtils.formatClock(4), '00:04');
      expect(TimeUtils.formatClock(15), '00:15');
      expect(TimeUtils.formatClock(65), '01:05');
    });

    test('时间标记区间用 mm:ss-mm:ss 表示', () {
      expect(TimeUtils.formatRange(0, 4), '00:00-00:04');
      expect(TimeUtils.formatRange(8, 15), '00:08-00:15');
    });

    test('导出用区间在两侧留空格（文档 17.5）', () {
      expect(TimeUtils.formatRange(0, 4, spaced: true), '00:00 - 00:04');
    });

    test('时长显示保留一位小数并去掉多余的 .0', () {
      expect(TimeUtils.formatDuration(4), '4s');
      expect(TimeUtils.formatDuration(13.5), '13.5s');
      expect(TimeUtils.formatDuration(1.25), '1.3s');
    });

    test('连续分镜的时间标记首尾相接', () {
      final marked = TimeUtils.assignTimeMarks(shots([4, 4, 4, 3]));

      expect(marked.map((s) => s.timeMark).toList(), [
        '00:00-00:04',
        '00:04-00:08',
        '00:08-00:12',
        '00:12-00:15',
      ]);
    });

    test('禁用分镜不占时间轴，标记为空，后续分镜继续相接', () {
      final marked = TimeUtils.assignTimeMarks(shots([4, 4, 7], disabled: [1]));

      // 启用分镜时长合计 11 秒（4 + 7），时间轴按启用分镜顺序连续推进
      expect(marked.map((s) => s.timeMark).toList(), [
        '00:00-00:04',
        '',
        '00:04-00:11',
      ]);
    });

    test('重排后 orderIndex 按当前顺序连续编号', () {
      final marked = TimeUtils.assignTimeMarks(shots([4, 4, 7], disabled: [1]));

      expect(marked.map((s) => s.orderIndex).toList(), [0, 1, 2]);
    });
  });

  group('DurationCalculator 基础统计（文档 6.1 / 6.3）', () {
    test('已用时长为启用分镜之和', () {
      expect(DurationCalculator.used(shots([4, 4, 4, 3])), 15);
      expect(DurationCalculator.used(shots([4, 4, 7], disabled: [1])), 11);
    });

    test('剩余时长 = 总时长 - 已用时长，可为负', () {
      expect(DurationCalculator.remaining(15, shots([4, 4, 4, 3])), 0);
      expect(DurationCalculator.remaining(15, shots([4, 4, 7], disabled: [1])), 4);
      expect(DurationCalculator.remaining(15, shots([10, 10])), -5);
    });

    test('台词预估总时长为各分镜预估之和', () {
      final list = shots([4, 4]).map((s) => s.copyWith(dialogue: '你真的要走吗？')).toList();

      expect(DurationCalculator.dialogueTotal(list), closeTo(4.2, 0.01));
    });
  });

  group('DurationCalculator 平均分配（文档 6.2）', () {
    test('总时长 15 秒平均分给 4 个分镜，余数落到最后一个', () {
      final result = DurationCalculator.distributeEvenly(shots([1, 1, 1, 1]), 15);

      expect(result.map((s) => s.duration).toList(), [3.8, 3.8, 3.8, 3.6]);
      expect(DurationCalculator.used(result), 15);
    });

    test('锁定的分镜不参与分配，其时长被保留', () {
      final list = [
        ShotBlock.create(orderIndex: 0, duration: 5).copyWith(durationLocked: true),
        ShotBlock.create(orderIndex: 1, duration: 2),
        ShotBlock.create(orderIndex: 2, duration: 2),
        ShotBlock.create(orderIndex: 3, duration: 2),
      ];

      final result = DurationCalculator.distributeEvenly(list, 15);

      expect(result.first.duration, 5);
      expect(result.map((s) => s.duration).toList(), [5, 3.3, 3.3, 3.4]);
      expect(DurationCalculator.used(result), 15);
    });

    test('禁用分镜不参与分配', () {
      final result = DurationCalculator.distributeEvenly(shots([4, 4, 7], disabled: [1]), 15);

      expect(result[1].enabled, isFalse);
      expect(result[1].duration, 4);
      expect(DurationCalculator.used(result), 15);
    });

    test('按比例重算保持原有比例', () {
      final result = DurationCalculator.distributeProportionally(shots([4, 4, 4, 3]), 7.5);

      expect(result.map((s) => s.duration).toList(), [2, 2, 2, 1.5]);
      expect(DurationCalculator.used(result), 7.5);
    });
  });

  group('DurationCalculator 单分镜调整（文档 6.2）', () {
    test('改某个分镜时长后自动调整最后一个启用分镜补齐总时长', () {
      final result = DurationCalculator.setShotDuration(shots([4, 4, 4, 3]), index: 0, value: 6, total: 15);

      expect(result.map((s) => s.duration).toList(), [6, 4, 4, 1]);
      expect(DurationCalculator.used(result), 15);
    });

    test('最后一个分镜自己就是调整对象时直接设值', () {
      final result = DurationCalculator.setShotDuration(shots([4, 4, 4, 3]), index: 3, value: 5, total: 15);

      expect(result.map((s) => s.duration).toList(), [4, 4, 2, 5]);
      expect(DurationCalculator.used(result), 15);
    });

    test('会导致最后一个分镜低于 1 秒的调整被拒绝，返回原列表', () {
      final list = shots([4, 4, 4, 3]);
      final result = DurationCalculator.setShotDuration(list, index: 0, value: 13, total: 15);

      expect(result, list);
      expect(DurationCalculator.used(result), 15);
    });

    test('锁定的最后一个分镜不会被自动改写，改为调整前一个未锁定分镜', () {
      final list = [
        ShotBlock.create(orderIndex: 0, duration: 4),
        ShotBlock.create(orderIndex: 1, duration: 4),
        ShotBlock.create(orderIndex: 2, duration: 4),
        ShotBlock.create(orderIndex: 3, duration: 3).copyWith(durationLocked: true),
      ];

      final result = DurationCalculator.setShotDuration(list, index: 0, value: 6, total: 15);

      expect(result.last.duration, 3);
      expect(DurationCalculator.used(result), 15);
      expect(result[0].duration, 6);
    });
  });

  group('DurationCalculator 增删与启停（文档 6.2）', () {
    test('新增分镜从最后一个未锁定分镜扣除时长', () {
      final result = DurationCalculator.addShot(shots([4, 4, 4, 3]), total: 15);

      expect(result, hasLength(5));
      expect(result.map((s) => s.duration).toList(), [4, 4, 4, 2, 1]);
      expect(DurationCalculator.used(result), 15);
    });

    test('剩余时长充足时新增分镜直接占用剩余时长', () {
      final result = DurationCalculator.addShot(shots([4, 4], disabled: []), total: 15);

      expect(result, hasLength(3));
      expect(result.last.duration, 7);
      expect(result[0].duration, 4);
    });

    test('删除分镜后剩余时长重新分配到最后一个未锁定分镜', () {
      final result = DurationCalculator.removeShot(shots([4, 4, 4, 3]), index: 1, total: 15);

      expect(result, hasLength(3));
      expect(result.map((s) => s.duration).toList(), [4, 4, 7]);
      expect(DurationCalculator.used(result), 15);
    });

    test('禁用分镜后其时长按比例分给其他启用分镜，总时长不变', () {
      final result = DurationCalculator.setEnabled(shots([4, 4, 4, 3]), index: 1, enabled: false, total: 15);

      expect(result[1].enabled, isFalse);
      expect(DurationCalculator.used(result), 15);
      expect(result[0].duration, 5.5);
      expect(result[3].duration, 4);
    });

    test('重新启用分镜时从其他分镜按比例回收 1 秒起步时长', () {
      final disabled = DurationCalculator.setEnabled(shots([4, 4, 4, 3]), index: 1, enabled: false, total: 15);
      final result = DurationCalculator.setEnabled(disabled, index: 1, enabled: true, total: 15);

      expect(result[1].enabled, isTrue);
      expect(result[1].duration, greaterThanOrEqualTo(AppConstants.minShotDuration));
      expect(DurationCalculator.used(result), 15);
    });
  });

  group('DialogueDurationEstimator（文档 4.5 / 7.1 / 7.2）', () {
    test('文档算例：7 字台词按 200 字/分估算为 2.1 秒', () {
      expect(DialogueDurationEstimator.charCount('你真的要走吗？'), 7);
      expect(DialogueDurationEstimator.estimate('你真的要走吗？'), 2.1);
    });

    test('文档算例：12 字台词在 240 语速下 3.0 秒、默认语速下 3.6 秒', () {
      const text = '我知道你一定会回来找我谈';

      expect(DialogueDurationEstimator.charCount(text), 12);
      expect(DialogueDurationEstimator.estimate(text, speechRate: 240), 3.0);
      expect(DialogueDurationEstimator.estimate(text), 3.6);
    });

    test('空台词与纯空白不产生预估时长', () {
      expect(DialogueDurationEstimator.estimate(''), 0);
      expect(DialogueDurationEstimator.estimate('   '), 0);
      expect(DialogueDurationEstimator.estimate('', speechRate: 240), 0);
    });

    test('英文按单词估算', () {
      expect(DialogueDurationEstimator.wordCount('Hello world'), 2);
      expect(DialogueDurationEstimator.estimate('Hello world'), 0.9);
    });

    test('中英混排分别计数后合并', () {
      // 3 个中文字符 + 2 个英文单词（now、baby）
      expect(DialogueDurationEstimator.units('走开吧 now baby'),
          closeTo(3 + 2 * AppConstants.englishWordWeight, 0.001));
    });

    test('语速非法时回落到项目默认语速', () {
      expect(DialogueDurationEstimator.estimate('你真的要走吗？', speechRate: 0), 2.1);
      // '你真的走吗？' 共 6 个字符，6 / 200 * 60 = 1.8 秒
      expect(DialogueDurationEstimator.estimate('你真的走吗？', speechRate: -10), 1.8);
    });

    test('台词时长状态判定：充足 / 偏紧 / 超出', () {
      expect(DialogueDurationEstimator.status(2.1, 4).kind, DialogueStatusKind.sufficient);
      expect(DialogueDurationEstimator.status(3.5, 4).kind, DialogueStatusKind.tight);
      expect(DialogueDurationEstimator.status(5.0, 4).kind, DialogueStatusKind.exceeded);
      expect(DialogueDurationEstimator.status(5.0, 4).overflowSeconds, closeTo(1.0, 0.001));
      expect(DialogueDurationEstimator.status(0, 4).kind, DialogueStatusKind.empty);
    });
  });
}
