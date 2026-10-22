import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nur/data/db/app_db.dart';
import 'package:nur/features/context/intel_settings.dart';
import 'package:nur/features/skills/builtin_skills.dart';
import 'package:nur/features/skills/skill_parser.dart';
import 'package:nur/features/skills/skills_repo.dart';

void main() {
  test('every built-in skill parses, and the names the app uses are there', () {
    final parsed = [for (final md in builtinSkills) parseSkillMd(md)];
    final names = parsed.map((s) => s.name).toList();
    expect(names.toSet(), hasLength(builtinSkills.length));
    expect(names, containsAll(['nas-admin', 'arabic-writer', 'docker-helper', 'nas-health-check', 'docker-app-manager',
      'home-media', 'web-research', 'arabic-conversation', 'voice-persona', 'troubleshooting']));
    for (final s in parsed.where((s) => s.body.contains('## Quick card'))) {
      final card = skillQuickCard(s.body);
      expect(card, isNotEmpty, reason: s.name);
      expect(card.split(' ').length, lessThanOrEqualTo(75), reason: s.name);
    }
    expect(skillQuickCard('# No card\nJust text.'), '');
  });

  test('the skill texts match the setup guide', () {
    final all = builtinSkills.join('\n');
    expect(all, contains('/DATA/HDD1'));
    expect(all, contains(':8096'));
    expect(all, isNot(contains('/mnt/hdd')));
    expect(all, isNot(contains('8097')));
  });

  test('seeding runs once, keeps the user switches and can be restored', () async {
    final db = AppDb(NativeDatabase.memory());
    final repo = SkillsRepo(db);
    await repo.ensureBuiltins();
    final first = await db.select(db.skills).get();
    expect(first, hasLength(builtinSkills.length));
    expect(await db.getSetting(IntelKeys.skillsSeeded), 'true');

    final media = first.firstWhere((s) => s.name == 'home-media');
    await repo.setEnabled(media.id, false);
    await repo.delete(first.firstWhere((s) => s.name == 'voice-persona'));
    await repo.ensureBuiltins();
    expect(await db.select(db.skills).get(), hasLength(builtinSkills.length - 1), reason: 'an install that already seeded is left alone');

    await repo.restoreBuiltins();
    final restored = await db.select(db.skills).get();
    expect(restored, hasLength(builtinSkills.length));
    expect(restored.firstWhere((s) => s.name == 'home-media').enabled, isFalse, reason: 'restoring keeps the switch');
    await db.close();
  });
}
