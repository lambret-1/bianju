/// JSON 解析容错工具。
///
/// 项目文件可能被旧版本写出、被手工编辑过、或在导入时缺字段，
/// 解析一律回落到默认值而不是抛异常；真正损坏的文件由 `draft_recovery`
/// 负责保留原件并生成 `.corrupt` 备份（文档 8.2）。
library;

import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// 生成新的实体 id
String newId() => _uuid.v4();

String jsonStr(Map<String, dynamic> json, String key, [String fallback = '']) {
  final value = json[key];
  if (value is String) return value;
  if (value == null) return fallback;
  return value.toString();
}

double jsonDouble(Map<String, dynamic> json, String key, [double fallback = 0]) {
  final value = json[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

int jsonInt(Map<String, dynamic> json, String key, [int fallback = 0]) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

bool jsonBool(Map<String, dynamic> json, String key, [bool fallback = false]) {
  final value = json[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

DateTime jsonDate(Map<String, dynamic> json, String key, DateTime fallback) {
  final value = json[key];
  if (value is String) return DateTime.tryParse(value) ?? fallback;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return fallback;
}

List<String> jsonStrList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is List) return value.whereType<String>().toList();
  return <String>[];
}

Map<String, dynamic> jsonMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> jsonMapList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) return <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}
