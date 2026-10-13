import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';
import '../core/json_utils.dart';
import '../models/project.dart';
import 'schema_migrator.dart';
import 'storage_io.dart';

/// 项目列表条目，供首页「最近项目」显示（文档 3.2：标题、总时长、分镜数、已用时长、最后保存时间）
class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.fileName,
    required this.title,
    required this.totalDuration,
    required this.shotCount,
    required this.usedDuration,
    required this.updatedAt,
  });

  final String id;
  final String fileName;
  final String title;
  final double totalDuration;
  final int shotCount;
  final double usedDuration;
  final DateTime updatedAt;
}

/// 项目 JSON 读写，文档第十二章 / 第十九章。
///
/// 每个项目一个文件，文件名为项目 id；标题变化不影响定位。
/// 写入一律走原子写，读取一律走容错解析 + schema 迁移。
class ProjectStorage {
  ProjectStorage({required this.directory, this.migrator = const SchemaMigrator()});

  final Directory directory;
  final SchemaMigrator migrator;

  /// 某个项目的正式文件
  File fileFor(String projectId) => File(_projectPath(projectId));

  String _projectPath(String projectId) => StorageIo.join(
        directory.path,
        '$projectId.${AppConstants.projectFileExtension}',
      );

  Future<void> ensureReady() => StorageIo.ensureDirectory(directory);

  /// 保存项目（原子写）。不会修改 [project] 的任何字段，
  /// `updatedAt` 由调用方在产生变更时设置。
  Future<Project> save(Project project) async {
    await StorageIo.writeAtomic(fileFor(project.id), _encode(project.toJson()));
    return project;
  }

  /// 读取项目；文件损坏时保留原件并生成 `.corrupt` 备份，返回 null（文档 8.2）
  Future<Project?> load(String projectId) async {
    final file = fileFor(projectId);
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
      return null;
    }

    try {
      return Project.fromJson(migrator.migrate(decoded));
    } on Object {
      await StorageIo.backupCorrupt(file);
      return null;
    }
  }

  /// 列出全部项目摘要，按最后保存时间倒序（首页「最近项目」）
  Future<List<ProjectSummary>> listProjects() async {
    final summaries = <ProjectSummary>[];
    for (final file in _projectFiles()) {
      final summary = await _summarize(file);
      if (summary != null) summaries.add(summary);
    }
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// 按标题搜索项目（文档第十二章）
  Future<List<ProjectSummary>> searchProjects(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return listProjects();
    final all = await listProjects();
    return all.where((summary) => summary.title.contains(trimmed)).toList();
  }

  /// 删除项目文件（界面侧需二次确认，文档第十二章）
  Future<void> delete(String projectId) async {
    final file = fileFor(projectId);
    if (file.existsSync()) await file.delete();
  }

  /// 导出完整项目 JSON（含角色库），文档 17.3
  Future<String> exportBackup(Project project) async => _encode(project.toJson());

  /// 备份文件名：{项目标题}_备份_{日期}.json
  String suggestedBackupFileName(Project project, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final date = '${timestamp.year.toString().padLeft(4, '0')}'
        '${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}';
    return '${StorageIo.sanitizeFileName(project.title, fallback: Project.fallbackTitle)}_备份_$date'
        '.${AppConstants.projectFileExtension}';
  }

  /// 从 JSON 文本导入项目（文档第十二章）。
  /// 若 id 与已有项目冲突则分配新 id，绝不覆盖既有项目。
  Future<Project> importFromJsonString(String contents) async {
    final decoded = StorageIo.tryDecodeJson(contents);
    if (decoded == null) {
      throw const FormatException('导入失败：不是合法的 JSON 项目文件');
    }

    var project = Project.fromJson(migrator.migrate(decoded));
    if (fileFor(project.id).existsSync()) {
      project = project.copyWith(id: newProjectId());
    }
    await save(project);
    return project;
  }

  /// 从文件导入
  Future<Project> importFromFile(File file) async =>
      importFromJsonString(await file.readAsString());

  /// 生成一个新的项目 id
  String newProjectId() => newId();

  List<File> _projectFiles() {
    if (!directory.existsSync()) return const <File>[];
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.${AppConstants.projectFileExtension}'))
        .toList();
  }

  Future<ProjectSummary?> _summarize(File file) async {
    final project = await load(_idFromFileName(file));
    if (project == null) return null;
    return ProjectSummary(
      id: project.id,
      fileName: file.uri.pathSegments.last,
      title: project.title,
      totalDuration: project.totalDuration,
      shotCount: project.shotCount,
      usedDuration: project.usedDuration,
      updatedAt: project.updatedAt,
    );
  }

  String _idFromFileName(File file) {
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  String _encode(Map<String, dynamic> json) =>
      const JsonEncoder.withIndent('  ').convert(json);
}
