import '../models/consistency_issue.dart';
import '../models/project.dart';
import '../models/shot_block.dart';

/// 时段分类，用于「白天/夜晚是否冲突」判断
enum DayPart {
  day('白天'),
  dusk('黄昏'),
  night('夜晚');

  const DayPart(this.label);

  final String label;
}

/// 一致性检查服务，文档第十章。
///
/// 检查基准分两类（文档 10.1）：
/// - 以角色库为基准：角色称呼、服装、外貌特征（伤疤位置/发型）；
/// - 以分镜内容为基准：道具、光线、时间、环境音、背景音乐。
///
/// 实现方式说明：全部规则都是**启发式关键词匹配**，无法做到语义级理解，
/// 因此产出的级别最高只到「警告」，不阻断导出；界面提供忽略与确认入口
/// （文档 10.2），误报由创作者自行判定。只检查启用分镜（文档 5.2）。
class ConsistencyService {
  const ConsistencyService();

  /// 执行全部已开启维度的检查，返回冲突列表
  List<ConsistencyIssue> check(Project project) {
    final shots = project.enabledShots;
    if (shots.isEmpty) return const <ConsistencyIssue>[];

    final rules = project.consistencyRules;
    final issues = <ConsistencyIssue>[];
    if (rules.checkRole) issues.addAll(_checkRoleNaming(project, shots));
    if (rules.checkCostume) issues.addAll(_checkCostume(project, shots));
    if (rules.checkFeature) issues.addAll(_checkFeature(project, shots));
    if (rules.checkProp) issues.addAll(_checkProps(shots));
    if (rules.checkLight) issues.addAll(_checkLight(shots));
    if (rules.checkTime) issues.addAll(_checkTime(shots));
    if (rules.checkAmbient) issues.addAll(_checkAmbient(shots));
    if (rules.checkBgm) issues.addAll(_checkBgm(shots));
    return issues;
  }

  // ------------------------------------------------------- 以角色库为基准

  /// 角色称呼一致：同一 characterId 在不同分镜的显示名应统一（文档 4.4）
  List<ConsistencyIssue> _checkRoleNaming(Project project, List<ShotBlock> shots) {
    final byCharacter = <String, List<ShotBlock>>{};
    for (final shot in shots) {
      final id = shot.dialogueCharacterId.trim();
      if (id.isEmpty) continue;
      byCharacter.putIfAbsent(id, () => <ShotBlock>[]).add(shot);
    }

    final issues = <ConsistencyIssue>[];
    byCharacter.forEach((id, referenced) {
      final names = <String>{
        for (final shot in referenced)
          if (shot.dialogueCharacterName.trim().isNotEmpty) shot.dialogueCharacterName.trim(),
      };
      final libraryName = project.characterById(id)?.name.trim() ?? '';
      if (libraryName.isNotEmpty) names.add(libraryName);
      if (names.length <= 1) return;

      issues.add(ConsistencyIssue(
        type: ConsistencyIssueType.role,
        level: IssueLevel.warning,
        shotOrders: referenced.map((shot) => shot.displayNumber).toList(),
        characterId: id,
        message: '角色「${libraryName.isEmpty ? names.first : libraryName}」'
            '在不同分镜中称呼不一致：${names.join(' / ')}',
        suggestion: '统一使用角色库中的名称，避免「男主/他/阿明」混用。',
      ));
    });
    return issues;
  }

  /// 服装冲突：分镜描述里的服装与角色库「默认服装」矛盾（文档 4.4 / 10.2）
  List<ConsistencyIssue> _checkCostume(Project project, List<ShotBlock> shots) {
    final issues = <ConsistencyIssue>[];
    for (final character in project.characters) {
      final libraryCostume = character.costume.trim();
      if (libraryCostume.isEmpty) continue;
      final libraryGarments = _extractGarments(libraryCostume);
      if (libraryGarments.isEmpty) continue;

      for (final shot in shots) {
        if (shot.dialogueCharacterId != character.id) continue;
        final text = _descriptiveText(shot);
        if (text.isEmpty) continue;

        for (final phrase in _extractCostumePhrases(text)) {
          final garments = _extractGarments(phrase);
          if (garments.isEmpty) continue;
          if (garments.every(libraryGarments.contains)) continue;
          issues.add(ConsistencyIssue(
            type: ConsistencyIssueType.costume,
            level: IssueLevel.warning,
            shotOrders: [shot.displayNumber],
            characterId: character.id,
            message: '服装不一致：分镜 ${shot.displayNumber} 出现「$phrase」，'
                '与角色库默认服装「$libraryCostume」矛盾',
            suggestion: '确认是否为换装场景。',
          ));
          break; // 一个分镜只报一次，避免同一角色刷屏
        }
      }
    }
    return issues;
  }

  /// 外貌/伤疤：方向性特征与发型的左右、长短矛盾（文档 4.4）
  List<ConsistencyIssue> _checkFeature(Project project, List<ShotBlock> shots) {
    final issues = <ConsistencyIssue>[];
    for (final character in project.characters) {
      final appearance = character.appearance.trim();
      if (appearance.isEmpty) continue;
      final libraryDirections = _extractDirectionalFeatures(appearance);
      final libraryHairs = _extractHairs(appearance);

      for (final shot in shots) {
        if (shot.dialogueCharacterId != character.id) continue;
        final text = _descriptiveText(shot);
        if (text.isEmpty) continue;

        final shotDirections = _extractDirectionalFeatures(text);
        final conflictDirection = shotDirections.entries.any((entry) {
          final librarySide = libraryDirections[entry.key];
          return librarySide != null && librarySide != entry.value;
        });

        final shotHairs = _extractHairs(text);
        final conflictHair = libraryHairs.isNotEmpty &&
            shotHairs.isNotEmpty &&
            shotHairs.every((hair) => !libraryHairs.contains(hair));

        if (!conflictDirection && !conflictHair) continue;

        final reason = conflictDirection ? '左右方位矛盾' : '发型矛盾';
        issues.add(ConsistencyIssue(
          type: ConsistencyIssueType.feature,
          level: IssueLevel.warning,
          shotOrders: [shot.displayNumber],
          characterId: character.id,
          message: '外貌特征$reason：角色库记录「$appearance」，'
              '分镜 ${shot.displayNumber} 描述为「${_matchedField(shot)}」',
          suggestion: '核对角色库外貌字段，确认是否为剧情变化。',
        ));
      }
    }
    return issues;
  }

  // --------------------------------------------------- 以分镜内容为基准

  /// 道具：出现后消失又出现，中间未交代（文档 10.1）
  List<ConsistencyIssue> _checkProps(List<ShotBlock> shots) {
    final occurrences = <String, List<int>>{};
    for (final shot in shots) {
      for (final prop in _extractProps(_descriptiveText(shot))) {
        occurrences.putIfAbsent(prop, () => <int>[]).add(shot.displayNumber);
      }
    }

    final issues = <ConsistencyIssue>[];
    occurrences.forEach((prop, numbers) {
      if (numbers.length < 2) return;
      for (var i = 0; i < numbers.length - 1; i++) {
        final current = numbers[i];
        final next = numbers[i + 1];
        if (next - current <= 1) continue;
        issues.add(ConsistencyIssue(
          type: ConsistencyIssueType.prop,
          level: IssueLevel.info,
          shotOrders: [current, next],
          message: '道具「$prop」在分镜 $current 出现后消失，分镜 $next 又出现，中间未交代',
          suggestion: '确认道具是否需要在中间分镜保持可见，或补一句交代。',
        ));
        break;
      }
    });
    return issues;
  }

  /// 光线：相邻分镜光线氛围突变且未交代转场（文档 10.1）
  List<ConsistencyIssue> _checkLight(List<ShotBlock> shots) {
    final issues = <ConsistencyIssue>[];
    for (var i = 1; i < shots.length; i++) {
      final previous = shots[i - 1];
      final current = shots[i];
      final previousLight = previous.lightingMood.trim();
      final currentLight = current.lightingMood.trim();
      if (previousLight.isEmpty || currentLight.isEmpty) continue;
      if (previousLight == currentLight) continue;
      if (_hasTransition(previous) || _hasTransition(current)) continue;

      issues.add(ConsistencyIssue(
        type: ConsistencyIssueType.light,
        level: IssueLevel.info,
        shotOrders: [previous.displayNumber, current.displayNumber],
        message: '光线突变：分镜 ${previous.displayNumber}「$previousLight」→ '
            '分镜 ${current.displayNumber}「$currentLight」，未交代转场',
        suggestion: '若为同一场景，确认光线变化是否合理；若已换场，请在「背景变化」中写明。',
      ));
    }
    return issues;
  }

  /// 时间：白天/夜晚冲突（文档 10.1）
  List<ConsistencyIssue> _checkTime(List<ShotBlock> shots) {
    final detected = <ShotBlock, DayPart>{};
    for (final shot in shots) {
      final part = _detectDayPart(shot);
      if (part != null) detected[shot] = part;
    }
    if (detected.length < 2) return const <ConsistencyIssue>[];

    final issues = <ConsistencyIssue>[];
    for (var i = 1; i < shots.length; i++) {
      final previous = shots[i - 1];
      final current = shots[i];
      final previousPart = detected[previous];
      final currentPart = detected[current];
      if (previousPart == null || currentPart == null) continue;
      if (previousPart == currentPart) continue;

      final crossesDayNight = (previousPart == DayPart.day && currentPart == DayPart.night) ||
          (previousPart == DayPart.night && currentPart == DayPart.day);
      if (!crossesDayNight) continue;
      if (_hasTimeSkip(current) || _hasTimeSkip(previous)) continue;

      issues.add(ConsistencyIssue(
        type: ConsistencyIssueType.time,
        level: IssueLevel.warning,
        shotOrders: [previous.displayNumber, current.displayNumber],
        message: '时间冲突：分镜 ${previous.displayNumber} 为${previousPart.label}，'
            '分镜 ${current.displayNumber} 变为${currentPart.label}，未交代时间跳转',
        suggestion: '若确为跨时段，请在「背景变化」中写明（如「翌日」「数日后」）。',
      ));
    }
    return issues;
  }

  /// 环境音：场景变化后环境音是否仍合理（文档 10.1）
  List<ConsistencyIssue> _checkAmbient(List<ShotBlock> shots) {
    final issues = <ConsistencyIssue>[];
    for (var i = 1; i < shots.length; i++) {
      final previous = shots[i - 1];
      final current = shots[i];
      final ambient = current.ambientSound.trim();
      if (ambient.isEmpty || ambient == _none) continue;
      if (ambient != previous.ambientSound.trim()) continue;
      if (!_hasSceneChange(current)) continue;

      issues.add(ConsistencyIssue(
        type: ConsistencyIssueType.ambient,
        level: IssueLevel.info,
        shotOrders: [previous.displayNumber, current.displayNumber],
        message: '分镜 ${current.displayNumber} 场景已变化，但环境音仍沿用「$ambient」',
        suggestion: '确认新场景下该环境音是否仍合理。',
      ));
    }
    return issues;
  }

  /// 背景音乐：情绪是否与画面冲突（文档 10.1）
  List<ConsistencyIssue> _checkBgm(List<ShotBlock> shots) {
    final issues = <ConsistencyIssue>[];
    for (final shot in shots) {
      final bgm = shot.bgm.trim();
      final light = shot.lightingMood.trim();
      if (bgm.isEmpty || light.isEmpty) continue;

      final sadOnWarm = _negativeBgm.contains(bgm) && _warmLight.contains(light);
      final brightOnCold = _positiveBgm.contains(bgm) && _coldLight.contains(light);
      if (!sadOnWarm && !brightOnCold) continue;

      issues.add(ConsistencyIssue(
        type: ConsistencyIssueType.bgm,
        level: IssueLevel.info,
        shotOrders: [shot.displayNumber],
        message: '背景音乐「$bgm」与画面光线氛围「$light」情绪可能冲突',
        suggestion: '若为刻意的反差处理，可直接忽略本条提示。',
      ));
    }
    return issues;
  }

  // ------------------------------------------------------------- 词表与工具

  static const String _none = '无';

  /// 服装词表：颜色修饰 + 服装主体，长词优先
  static final RegExp _costumeRegExp = RegExp(
    r'(白色|黑色|红色|蓝色|绿色|黄色|灰色|深色|浅色|米色|紫色|橙色|粉色|棕色|银色|金色|花色)?'
    r'(连衣裙|风衣|大衣|外套|夹克|衬衫|卫衣|毛衣|西装|制服|校服|旗袍|裙子|长裙|短裤|长裤|牛仔裤|'
    r'围巾|披肩|披风|帽子|手套|靴子|皮鞋|运动鞋|背心|T恤|裙|裤)',
  );

  /// 方向性外貌特征，如「左脸」「右眼」
  static final RegExp _directionRegExp = RegExp(r'(左|右)(脸|眼|眉|耳|手|臂|腿|脚|嘴角)');

  static const List<String> _hairStyles = <String>[
    '长发', '短发', '寸头', '光头', '马尾', '卷发', '直发', '丸子头', '中分', '平头',
  ];

  /// 道具词表，长词优先匹配，避免「雨伞」被拆成「伞」
  static const List<String> _propVocabulary = <String>[
    '行李箱', '手提箱', '日记本', '打火机', '雨伞', '药瓶', '怀表', '手表', '手机',
    '信封', '钥匙', '照片', '戒指', '项链', '眼镜', '杯子', '花束', '报纸', '面具',
    '绳索', '拐杖', '背包', '书本', '刀', '枪', '伞', '花', '烟',
  ];

  /// 转场/换场关键词：出现即视为已交代，不再报光线突变
  static const List<String> _transitionKeywords = <String>[
    '转场', '切到', '切换到', '换到', '来到', '进入', '离开', '翌日', '次日',
    '第二天', '隔天', '后来', '同时', '回忆', '闪回',
  ];

  /// 时间跳转关键词：出现即视为已交代跨时段
  static const List<String> _timeSkipKeywords = <String>[
    '翌日', '次日', '第二天', '隔天', '几天后', '数日后', '多年后', '后来', '回忆', '闪回',
  ];

  /// 场景变化关键词，用于环境音合理性判断
  static const List<String> _sceneChangeKeywords = <String>[
    '切到', '切换到', '转场', '换到', '来到', '进入', '走出', '搬到',
  ];

  /// 时段关键词
  static const Map<String, DayPart> _timeKeywords = <String, DayPart>{
    '清晨': DayPart.day,
    '早晨': DayPart.day,
    '上午': DayPart.day,
    '正午': DayPart.day,
    '中午': DayPart.day,
    '下午': DayPart.day,
    '白天': DayPart.day,
    '日出': DayPart.day,
    '黄昏': DayPart.dusk,
    '傍晚': DayPart.dusk,
    '日落': DayPart.dusk,
    '夜晚': DayPart.night,
    '夜里': DayPart.night,
    '夜间': DayPart.night,
    '深夜': DayPart.night,
    '凌晨': DayPart.night,
  };

  static const Set<String> _negativeBgm = <String>{'悲伤', '压抑', '紧张', '悬疑'};
  static const Set<String> _positiveBgm = <String>{'温馨', '浪漫', '轻快', '激昂'};
  static const Set<String> _warmLight = <String>{'暖黄光', '柔光', '烛光', '自然光'};
  static const Set<String> _coldLight = <String>{'冷蓝光', '低照度', '硬光', '霓虹光', '逆光'};

  /// 参与一致性判断的描述性字段
  String _descriptiveText(ShotBlock shot) => <String>[
        shot.subjectAction,
        shot.actionStart,
        shot.actionDevelop,
        shot.actionEnd,
        shot.backgroundChange,
        shot.keepConsistent,
      ].where((value) => value.trim().isNotEmpty).join(' ');

  /// 命中冲突的那个字段原文，用于提示信息定位
  String _matchedField(ShotBlock shot) {
    for (final value in <String>[shot.keepConsistent, shot.backgroundChange, shot.subjectAction]) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return _descriptiveText(shot);
  }

  Set<String> _extractGarments(String text) => <String>{
        for (final match in _costumeRegExp.allMatches(text))
          if ((match.group(2) ?? '').isNotEmpty) match.group(2)!,
      };

  List<String> _extractCostumePhrases(String text) => <String>[
        for (final match in _costumeRegExp.allMatches(text))
          if (match.group(0)!.trim().isNotEmpty) match.group(0)!,
      ];

  /// 部位 → 方位（左/右）
  Map<String, String> _extractDirectionalFeatures(String text) => <String, String>{
        for (final match in _directionRegExp.allMatches(text)) match.group(2)!: match.group(1)!,
      };

  Set<String> _extractHairs(String text) => <String>{
        for (final hair in _hairStyles)
          if (text.contains(hair)) hair,
      };

  /// 道具抽取：长词优先并标记已占用区间，避免「雨伞」被重复计为「伞」
  Set<String> _extractProps(String text) {
    final found = <String>{};
    if (text.trim().isEmpty) return found;
    final consumed = List<bool>.filled(text.length, false);

    final vocabulary = List<String>.of(_propVocabulary)
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final prop in vocabulary) {
      var from = 0;
      while (true) {
        final index = text.indexOf(prop, from);
        if (index < 0) break;
        final end = index + prop.length;
        var overlapped = false;
        for (var i = index; i < end && i < consumed.length; i++) {
          if (consumed[i]) {
            overlapped = true;
            break;
          }
        }
        if (!overlapped) {
          found.add(prop);
          for (var i = index; i < end && i < consumed.length; i++) {
            consumed[i] = true;
          }
        }
        from = end;
      }
    }
    return found;
  }

  bool _hasTransition(ShotBlock shot) =>
      _containsAny(shot.backgroundChange, _transitionKeywords);

  bool _hasSceneChange(ShotBlock shot) =>
      _containsAny(shot.backgroundChange, _sceneChangeKeywords);

  bool _hasTimeSkip(ShotBlock shot) => _containsAny(
        '${shot.backgroundChange} ${shot.subjectAction}',
        _timeSkipKeywords,
      );

  bool _containsAny(String text, List<String> keywords) {
    if (text.trim().isEmpty) return false;
    return keywords.any(text.contains);
  }

  /// 取分镜文本中最早出现的时段关键词
  DayPart? _detectDayPart(ShotBlock shot) {
    final text = '${shot.backgroundChange} ${shot.subjectAction} ${shot.lightingMood}';
    var bestIndex = -1;
    DayPart? best;
    _timeKeywords.forEach((keyword, part) {
      final index = text.indexOf(keyword);
      if (index < 0) return;
      if (bestIndex < 0 || index < bestIndex) {
        bestIndex = index;
        best = part;
      }
    });
    return best;
  }
}
