import 'constants.dart';

/// 撤销/重做栈，文档 8.3。
///
/// 采用快照式历史：每次 `push` 记录一个完整状态。进程内维护且有上限，
/// 超出上限时丢弃最早的状态，避免长编辑会话内存无限增长。
/// 泛型设计使其既能承载 `Project` 整体快照，也能承载更细粒度的局部状态。
class UndoRedoStack<T> {
  UndoRedoStack({required T initial, this.limit = AppConstants.undoStackLimit})
      : assert(limit >= 1, '撤销栈上限至少为 1'),
        _states = <T>[initial];

  /// 保留的状态总数上限（含当前状态）
  final int limit;

  final List<T> _states;
  int _cursor = 0;

  /// 当前状态
  T get current => _states[_cursor];

  bool get canUndo => _cursor > 0;

  bool get canRedo => _cursor < _states.length - 1;

  /// 可撤销的步数
  int get undoDepth => _cursor;

  /// 可重做的步数
  int get redoDepth => _states.length - 1 - _cursor;

  /// 记录一次新状态；会丢弃当前状态之后的重做分支
  void push(T state) {
    if (_cursor < _states.length - 1) {
      _states.removeRange(_cursor + 1, _states.length);
    }
    _states.add(state);
    _cursor = _states.length - 1;
    _trimToLimit();
  }

  /// 撤销一步，返回撤销后的当前状态；无可撤销时返回 null
  T? undo() {
    if (!canUndo) return null;
    _cursor--;
    return current;
  }

  /// 重做一步，返回重做后的当前状态；无可重做时返回 null
  T? redo() {
    if (!canRedo) return null;
    _cursor++;
    return current;
  }

  /// 就地替换当前状态且不产生新历史。
  /// 用于自动保存回填时间戳等「不算用户操作」的变更。
  void replaceCurrent(T state) {
    _states[_cursor] = state;
  }

  /// 清空历史，只保留当前状态（如切换项目时）
  void clear() {
    final keep = current;
    _states
      ..clear()
      ..add(keep);
    _cursor = 0;
  }

  void _trimToLimit() {
    final overflow = _states.length - limit;
    if (overflow <= 0) return;
    _states.removeRange(0, overflow);
    _cursor -= overflow;
  }
}
