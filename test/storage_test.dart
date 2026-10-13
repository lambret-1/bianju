import 'dart:convert';
import 'dart:io';

import 'package:bianju/core/constants.dart';
import 'package:bianju/models/character.dart';
import 'package:bianju/models/project.dart';
import 'package:bianju/storage/auto_save_manager.dart';
import 'package:bianju/storage/draft_recovery.dart';
import 'package:bianju/storage/project_storage.dart';
import 'package:bianju/storage/schema_migrator.dart';
import 'package:flutter_test/flutter_test.dart';

/// WP5 存储层测试：覆盖文档第八章（自动保存、草稿恢复、损坏备份）、
/// 第十二章（项目生命周期、导入导出）与 16.5（数据迁移）。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bianju_storage_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Project sampleProject({String title = '短片A'}) {
    final project = Project.create(title: title);
    return project.copyWith(
      shots: [
        project.shots[0].copyWith(subjectAction: '男主站在窗前', dialogue: '走吧'),
        ...project.shots.skip(1),
      ],
    );
  }

  group('ProjectStorage 读写（文档第十二章）', () {
    test('保存后能读回等价项目', () async {
      final storage = ProjectStorage(directory: tempDir);
      final project = sampleProject();

      await storage.save(project);
      final loaded = await storage.load(project.id);

      expect(loaded, isNotNull);
      expect(jsonEncode(loaded!.toJson()), jsonEncode(project.toJson()));
    });

    test('保存是原子的：不残留临时文件', () async {
      final storage = ProjectStorage(directory: tempDir);

      await storage.save(sampleProject());

      final leftovers = tempDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('目录不存在时自动创建', () async {
      final nested = Directory('${tempDir.path}${Platform.pathSeparator}nested${Platform.pathSeparator}projects');
      final storage = ProjectStorage(directory: nested);

      await storage.save(sampleProject());

      expect(nested.existsSync(), isTrue);
    });

    test('项目列表返回摘要并按更新时间倒序', () async {
      final storage = ProjectStorage(directory: tempDir);
      final older = sampleProject(title: '旧短片')
          .copyWith(updatedAt: DateTime(2026, 1, 1));
      final newer = sampleProject(title: '新短片')
          .copyWith(updatedAt: DateTime(2026, 5, 1));

      await storage.save(older);
      await storage.save(newer);
      final summaries = await storage.listProjects();

      expect(summaries, hasLength(2));
      expect(summaries.first.title, '新短片');
      expect(summaries.last.title, '旧短片');
      expect(summaries.first.shotCount, AppConstants.defaultShotCount);
      expect(summaries.first.totalDuration, AppConstants.defaultTotalDuration);
      expect(summaries.first.usedDuration, greaterThan(0));
    });

    test('按标题搜索项目（文档第十二章「搜索项目」）', () async {
      final storage = ProjectStorage(directory: tempDir);
      await storage.save(sampleProject(title: '雨夜追车'));
      await storage.save(sampleProject(title: '清晨对话'));

      final hits = await storage.searchProjects('雨夜');

      expect(hits, hasLength(1));
      expect(hits.first.title, '雨夜追车');
    });

    test('删除项目后文件消失', () async {
      final storage = ProjectStorage(directory: tempDir);
      final project = sampleProject();
      await storage.save(project);

      await storage.delete(project.id);

      expect(await storage.load(project.id), isNull);
      expect(await storage.listProjects(), isEmpty);
    });

    test('导出备份包含完整角色库与分镜引用关系（文档 17.3）', () async {
      final storage = ProjectStorage(directory: tempDir);
      final project = sampleProject();
      final withCharacter = project.copyWith(characters: [
        Character(name: '男主', id: 'c-1', createdAt: DateTime(2026), updatedAt: DateTime(2026)),
      ]).copyWith(shots: [
        project.shots[0].copyWith(dialogueCharacterId: 'c-1', dialogueCharacterName: '男主'),
        ...project.shots.skip(1),
      ]);

      final backup = await storage.exportBackup(withCharacter);
      final decoded = jsonDecode(backup) as Map<String, dynamic>;

      expect(decoded['characters'], hasLength(1));
      expect((decoded['shots'] as List).first['dialogueCharacterId'], 'c-1');
    });

    test('导入 JSON 时若 id 已存在则分配新 id，不覆盖原项目', () async {
      final storage = ProjectStorage(directory: tempDir);
      final project = sampleProject();
      await storage.save(project);

      final imported = await storage.importFromJsonString(jsonEncode(project.toJson()));

      expect(imported.id, isNot(project.id));
      expect(imported.title, project.title);
      expect(await storage.listProjects(), hasLength(2));
      // 原项目未被覆盖
      expect((await storage.load(project.id))!.id, project.id);
    });

    test('导入 v1 旧数据时自动迁移（文档 16.5）', () async {
      final storage = ProjectStorage(directory: tempDir);
      final legacy = <String, dynamic>{
        'id': 'legacy-project',
        'title': '旧版短片',
        'totalDuration': 15,
        'schemaVersion': 1,
        'shots': [
          <String, dynamic>{'id': 's1', 'duration': 4, 'dialogueCharacter': '男主', 'dialogue': '走吧'},
        ],
      };

      final imported = await storage.importFromJsonString(jsonEncode(legacy));

      expect(imported.schemaVersion, AppConstants.currentSchemaVersion);
      expect(imported.characters.map((c) => c.name), contains('男主'));
      expect(imported.shots.first.dialogueCharacterId, imported.characters.first.id);
    });
  });

  group('损坏文件处理（文档 8.2）', () {
    test('JSON 损坏时保留原文件为 .corrupt 备份并返回 null', () async {
      final storage = ProjectStorage(directory: tempDir);
      final project = sampleProject();
      await storage.save(project);
      storage.fileFor(project.id).writeAsStringSync('{"title": "被截断的');

      final loaded = await storage.load(project.id);

      expect(loaded, isNull);
      final corrupt = File('${storage.fileFor(project.id).path}${AppConstants.corruptFileSuffix}');
      expect(corrupt.existsSync(), isTrue);
      expect(corrupt.readAsStringSync(), contains('被截断的'));
    });
  });

  group('DraftRecovery 草稿（文档 8.1 / 8.2）', () {
    test('草稿可写入、读回、清除', () async {
      final drafts = DraftRecovery(directory: tempDir);
      final project = sampleProject();

      await drafts.writeDraft(project);
      final restored = await drafts.readDraft(project.id);
      expect(restored, isNotNull);
      expect(restored!.title, project.title);
      expect(await drafts.hasDraft(project.id), isTrue);

      await drafts.clearDraft(project.id);
      expect(await drafts.hasDraft(project.id), isFalse);
      expect(await drafts.readDraft(project.id), isNull);
    });

    test('草稿损坏时同样生成 .corrupt 备份且不抛异常', () async {
      final drafts = DraftRecovery(directory: tempDir);
      final project = sampleProject();
      await drafts.writeDraft(project);
      drafts.draftFileFor(project.id).writeAsStringSync('不是 JSON');

      final restored = await drafts.readDraft(project.id);

      expect(restored, isNull);
      expect(
        File('${drafts.draftFileFor(project.id).path}${AppConstants.corruptFileSuffix}')
            .existsSync(),
        isTrue,
      );
    });
  });

  group('AutoSaveManager 防抖（文档 8.1）', () {
    test('连续编辑只在防抖窗口结束后落盘一次', () async {
      var flushCount = 0;
      final manager = AutoSaveManager(
        debounce: const Duration(milliseconds: 30),
        onFlush: (project) async => flushCount++,
      );

      manager.schedule(sampleProject());
      manager.schedule(sampleProject());
      manager.schedule(sampleProject());
      expect(flushCount, 0);
      expect(manager.state, SaveState.pending);

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(flushCount, 1);
      expect(manager.state, SaveState.saved);
      manager.dispose();
    });

    test('flushNow 立即落盘并取消待执行的防抖任务', () async {
      var flushCount = 0;
      final manager = AutoSaveManager(
        debounce: const Duration(milliseconds: 200),
        onFlush: (project) async => flushCount++,
      );

      manager.schedule(sampleProject());
      await manager.flushNow();
      expect(flushCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(flushCount, 1);
      manager.dispose();
    });

    test('落盘抛错时状态变为失败（文档 8.1「保存失败，请重试」）', () async {
      final manager = AutoSaveManager(
        debounce: const Duration(milliseconds: 20),
        onFlush: (project) async => throw const FileSystemException('磁盘写入失败'),
      );

      manager.schedule(sampleProject());
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(manager.state, SaveState.failed);
      manager.dispose();
    });

    test('dispose 后不再落盘', () async {
      var flushCount = 0;
      final manager = AutoSaveManager(
        debounce: const Duration(milliseconds: 30),
        onFlush: (project) async => flushCount++,
      );

      manager.schedule(sampleProject());
      manager.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(flushCount, 0);
    });
  });

  group('SchemaMigrator 数据迁移（文档 16.5）', () {
    const migrator = SchemaMigrator();

    Map<String, dynamic> legacyJson({String dialogueCharacter = '男主', List<Map<String, dynamic>> characters = const []}) {
      return <String, dynamic>{
        'id': 'p1',
        'title': '旧版',
        'totalDuration': 15,
        'schemaVersion': 1,
        'characters': characters,
        'shots': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 's1',
            'duration': 4,
            'dialogueCharacter': dialogueCharacter,
            'dialogue': '走吧',
          },
        ],
      };
    }

    test('v1 台词角色按名匹配已有档案并回填 id', () {
      final migrated = migrator.migrate(legacyJson(
        characters: [
          <String, dynamic>{'id': 'c-1', 'name': '男主'},
        ],
      ));

      expect(migrated['schemaVersion'], AppConstants.currentSchemaVersion);
      final shot = (migrated['shots'] as List).first as Map<String, dynamic>;
      expect(shot['dialogueCharacterId'], 'c-1');
      expect(shot['dialogueCharacterName'], '男主');
      expect(shot.containsKey('dialogueCharacter'), isFalse);
    });

    test('v1 台词角色匹配不到档案时自动补建角色', () {
      final migrated = migrator.migrate(legacyJson());

      final characters = migrated['characters'] as List;
      expect(characters, hasLength(1));
      final created = characters.first as Map<String, dynamic>;
      expect(created['name'], '男主');
      final shot = (migrated['shots'] as List).first as Map<String, dynamic>;
      expect(shot['dialogueCharacterId'], created['id']);
    });

    test('v1 台词角色为空时保留为自定义兜底，不补建档案', () {
      final migrated = migrator.migrate(legacyJson(dialogueCharacter: ''));

      expect(migrated['characters'], isEmpty);
      final shot = (migrated['shots'] as List).first as Map<String, dynamic>;
      expect(shot['dialogueCharacterId'], '');
    });

    test('当前版本数据原样通过，不产生迁移记录', () {
      final current = sampleProject().toJson();

      final result = migrator.migrateWithReport(current);

      expect(result.appliedMigrations, isEmpty);
      expect(jsonEncode(result.json), jsonEncode(current));
    });

    test('高于当前版本的数据不降级，只记录跳过', () {
      final future = sampleProject().toJson()..['schemaVersion'] = 99;

      final result = migrator.migrateWithReport(future);

      expect(result.json['schemaVersion'], 99);
      expect(result.skippedFromFutureVersion, isTrue);
    });

    test('迁移结果可被 Project.fromJson 正常解析', () {
      final migrated = migrator.migrate(legacyJson());

      final project = Project.fromJson(migrated);

      expect(project.title, '旧版');
      expect(project.characters.first.name, '男主');
      expect(project.shots.first.dialogueCharacterId, isNotEmpty);
    });
  });
}
