import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';

/// 存储层共用的文件读写工具。
///
/// 说明：开发文档第十八章的目录树未列出本文件，它承载三处存储模块都要用的
/// 底层动作（原子写、损坏备份、容错解析），抽出来避免在四个存储文件里重复实现。
class StorageIo {
  StorageIo._();

  /// 跨平台路径拼接
  static String join(String directory, String fileName) =>
      '$directory${Platform.pathSeparator}$fileName';

  static Future<void> ensureDirectory(Directory directory) async {
    if (!directory.existsSync()) await directory.create(recursive: true);
  }

  /// 原子写：先写 `.tmp` 再 rename，避免写一半时崩溃损坏原文件
  static Future<void> writeAtomic(File target, String contents) async {
    await ensureDirectory(target.parent);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    await temporary.rename(target.path);
  }

  /// 保留原文件并生成 `.corrupt` 备份（文档 8.2）
  static Future<File> backupCorrupt(File source) async {
    final backup = File('${source.path}${AppConstants.corruptFileSuffix}');
    await source.copy(backup.path);
    return backup;
  }

  /// 容错解析 JSON；失败返回 null，由调用方决定后续处理
  static Map<String, dynamic>? tryDecodeJson(String contents) {
    try {
      final decoded = jsonDecode(contents);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } on FormatException {
      return null;
    }
  }

  /// 文件名清洗：去掉路径分隔符等不适合做文件名的字符
  static String sanitizeFileName(String raw, {String fallback = '未命名'}) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? fallback : cleaned;
  }
}
