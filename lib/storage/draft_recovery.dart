import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';
import '../models/project.dart';
import 'schema_migrator.dart';
import 'storage_io.dart';

/// 草稿恢复与损坏文件处理，文档 8.2。
///
/// 草稿与正式项目文件分开存放（后缀 `.draft`），异常退出后重新进入项目时
/// 可由界面提示「检测到未保存的草稿，是否恢复」。
class DraftRecovery {
  DraftRecovery({required this.directory, this.migrator = const SchemaMigrator()});

  final Directory directory;
  final SchemaMigrator migrator;

  /// 某个项目的草稿文件
  File draftFileFor(String projectId) => File(_draftPath(projectId));

  String _draftPath(String projectId) => StorageIo.join(
        directory.path,
        '$projectId.${AppConstants.projectFileExtension}${AppConstants.draftFileSuffix}',
      );

  Future<bool> hasDraft(String projectId) async => draftFileFor(projectId).existsSync();

  /// 写入草稿（原子写）
  Future<void> writeDraft(Project project) async {
    final file = draftFileFor(project.id);
    await StorageIo.writeAtomic(file, _encode(project));
  }

  /// 读取草稿；文件损坏时生成 `.corrupt` 备份、清掉坏草稿并返回 null
  Future<Project?> readDraft(String projectId) async {
    final file = draftFileFor(projectId);
    if (!file.existsSync()) return null;

    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException {
      return null;
    }

    final decoded = StorageIo.tryDecodeJson(contents);
    if (decoded == null) {
      await StorageIo.backupCorrupt(file);
      await _deleteQuietly(file);
      return null;
    }

    try {
      return Project.fromJson(migrator.migrate(decoded));
    } on Object {
      await StorageIo.backupCorrupt(file);
      await _deleteQuietly(file);
      return null;
    }
  }

  /// 清除草稿（正式保存成功后调用）
  Future<void> clearDraft(String projectId) async {
    await _deleteQuietly(draftFileFor(projectId));
  }

  /// 把草稿提升为正式内容前的一致性检查：草稿是否比正式文件更新
  Future<bool> isNewerThan(String projectId, DateTime savedAt) async {
    final file = draftFileFor(projectId);
    if (!file.existsSync()) return false;
    final modified = await file.lastModified();
    return modified.isAfter(savedAt);
  }

  String _encode(Project project) => const JsonEncoder.withIndent('  ').convert(project.toJson());

  Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // 删除失败不影响主流程
    }
  }
}
