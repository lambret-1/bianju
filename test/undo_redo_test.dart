import 'package:bianju/core/undo_redo_stack.dart';
import 'package:bianju/models/character.dart';
import 'package:bianju/models/project.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP4 撤销/重做栈测试：覆盖文档 8.3「撤销历史在进程内维护，不无限增长」。
void main() {
  group('UndoRedoStack 基本行为', () {
    test('初始状态不可撤销也不可重做', () {
      final stack = UndoRedoStack<String>(initial: 'a');

      expect(stack.current, 'a');
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
      expect(stack.undo(), isNull);
      expect(stack.redo(), isNull);
    });

    test('push 后可撤销回到上一个状态', () {
      final stack = UndoRedoStack<String>(initial: 'a')..push('b');

      expect(stack.current, 'b');
      expect(stack.canUndo, isTrue);
      expect(stack.undo(), 'a');
      expect(stack.current, 'a');
    });

    test('撤销后可重做回到被撤销的状态', () {
      final stack = UndoRedoStack<String>(initial: 'a')
        ..push('b')
        ..undo();

      expect(stack.canRedo, isTrue);
      expect(stack.redo(), 'b');
      expect(stack.current, 'b');
      expect(stack.canRedo, isFalse);
    });

    test('撤销后 push 新状态会清空重做栈', () {
      final stack = UndoRedoStack<String>(initial: 'a')
        ..push('b')
        ..undo()
        ..push('c');

      expect(stack.current, 'c');
      expect(stack.canRedo, isFalse);
      expect(stack.redo(), isNull);
    });

    test('超过上限时丢弃最早的状态，撤销深度不无限增长', () {
      final stack = UndoRedoStack<String>(initial: 'a', limit: 3)
        ..push('b')
        ..push('c')
        ..push('d')
        ..push('e');

      expect(stack.current, 'e');
      expect(stack.undoDepth, 2);
      expect(stack.undo(), 'd');
      expect(stack.undo(), 'c');
      expect(stack.undo(), isNull);
    });

    test('replaceCurrent 更新当前状态但不产生历史记录', () {
      final stack = UndoRedoStack<String>(initial: 'a')
        ..push('b')
        ..replaceCurrent('b2');

      expect(stack.current, 'b2');
      expect(stack.undoDepth, 1);
      expect(stack.undo(), 'a');
    });

    test('clear 后只保留当前状态', () {
      final stack = UndoRedoStack<String>(initial: 'a')
        ..push('b')
        ..push('c')
        ..clear();

      expect(stack.current, 'c');
      expect(stack.canUndo, isFalse);
      expect(stack.canRedo, isFalse);
    });
  });

  group('UndoRedoStack 用于项目状态（文档 8.3）', () {
    test('分镜字段修改可撤销、可重做', () {
      final project = Project.create(title: '短片A');
      final stack = UndoRedoStack<Project>(initial: project);

      final edited = project.copyWith(
        shots: [project.shots[0].copyWith(dialogue: '走吧'), ...project.shots.skip(1)],
      );
      stack.push(edited);

      expect(stack.current.shots.first.dialogue, '走吧');

      final undone = stack.undo();
      expect(undone!.shots.first.dialogue, '');

      final redone = stack.redo();
      expect(redone!.shots.first.dialogue, '走吧');
    });

    test('角色增删可撤销', () {
      final project = Project.create(title: '短片A');
      final stack = UndoRedoStack<Project>(initial: project)..push(project);

      final withCharacter = project.copyWith(characters: [
        Character(name: '男主', id: 'c1', createdAt: DateTime(2026), updatedAt: DateTime(2026)),
      ]);
      stack.push(withCharacter);
      expect(stack.current.characters, hasLength(1));

      stack.undo();
      expect(stack.current.characters, isEmpty);
    });
  });
}
