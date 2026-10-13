import 'dart:async';

import '../core/constants.dart';
import '../models/project.dart';

/// 保存状态，文档 3.6 / 8.1：界面显示「正在保存 / 已保存 / 保存失败」
enum SaveState {
  idle('空闲'),
  pending('待保存'),
  saving('正在保存'),
  saved('已保存'),
  failed('保存失败');

  const SaveState(this.label);

  final String label;
}

/// 自动保存管理器，文档 8.1。
///
/// 编辑后 700ms 防抖落盘；防抖窗口内的多次编辑只触发一次写入。
/// 落盘动作由外部注入（[onFlush]），因此本类不直接依赖文件系统，
/// 便于单元测试，也便于同时写正式文件与草稿。
class AutoSaveManager {
  AutoSaveManager({
    required this.onFlush,
    this.debounce = const Duration(milliseconds: AppConstants.autoSaveDebounceMs),
  });

  /// 实际落盘动作，通常是「写正式文件 + 写草稿」
  final Future<void> Function(Project project) onFlush;

  /// 防抖窗口，默认 700ms（文档 8.1）
  final Duration debounce;

  Timer? _timer;
  Project? _pending;
  SaveState _state = SaveState.idle;
  bool _disposed = false;

  SaveState get state => _state;

  /// 是否有尚未落盘的变更
  bool get isDirty => _pending != null;

  /// 状态变化回调，供界面刷新保存状态指示
  void Function(SaveState state)? onStateChanged;

  /// 记录一次编辑并重置防抖计时
  void schedule(Project project) {
    if (_disposed) return;
    _pending = project;
    _setState(SaveState.pending);
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(flushNow()));
  }

  /// 立即落盘（离开页面前调用），并取消待执行的防抖任务
  Future<void> flushNow() async {
    _timer?.cancel();
    _timer = null;

    final project = _pending;
    if (project == null || _disposed) return;

    _pending = null;
    _setState(SaveState.saving);
    try {
      await onFlush(project);
      if (!_disposed) _setState(SaveState.saved);
    } on Object {
      if (_disposed) return;
      // 失败时把变更放回去，允许用户重试而不丢内容（文档 8.1）
      _pending = project;
      _setState(SaveState.failed);
    }
  }

  /// 放弃当前待保存的变更
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    if (_state == SaveState.pending) _setState(SaveState.idle);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _setState(SaveState next) {
    if (_state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }
}
