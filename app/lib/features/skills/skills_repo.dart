// Installed skills: install (URL / zip / paste), built-in seeding, enable/disable, progressive loading.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../data/db/app_db.dart' hide LlmModel, NasDevice;
import '../context/intel_settings.dart';
import 'builtin_skills.dart';
import 'skill_parser.dart';

class SkillsRepo {
  SkillsRepo(this._db);
  final AppDb _db;
  static const _uuid = Uuid();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 60),
    followRedirects: true,
    maxRedirects: 5,
  ));
  Future<void>? _seeding;

  Stream<List<Skill>> watchAll() => (_db.select(_db.skills)..orderBy([(s) => OrderingTerm.asc(s.name)])).watch();

  Future<List<Skill>> enabledSkills() async {
    await ensureBuiltins();
    return (_db.select(_db.skills)
          ..where((s) => s.enabled.equals(true))
          ..orderBy([(s) => OrderingTerm.asc(s.name)]))
        .get();
  }

  /// Seeds the built-in skills once (and again after "restore built-ins").
  Future<void> ensureBuiltins({bool force = false}) => _seeding ??= () async {
        try {
          if (!force && await _db.getSetting(IntelKeys.skillsSeeded) == 'true') return;
          for (final md in builtinSkills) {
            final p = parseSkillMd(md);
            await _upsert(p, source: 'builtin');
          }
          await _db.setSetting(IntelKeys.skillsSeeded, 'true');
        } finally {
          _seeding = null;
        }
      }();

  Future<Skill> _upsert(ParsedSkill p, {required String source, String? dir}) async {
    final existing = await (_db.select(_db.skills)..where((s) => s.name.equals(p.name))).getSingleOrNull();
    final id = existing?.id ?? _uuid.v4();
    await _db.into(_db.skills).insertOnConflictUpdate(SkillsCompanion.insert(
          id: id,
          name: p.name,
          description: p.description,
          body: p.body,
          source: Value(source),
          dir: Value(dir ?? existing?.dir),
          enabled: Value(existing?.enabled ?? true),
          installedAt: Value(DateTime.now()),
        ));
    return (await (_db.select(_db.skills)..where((s) => s.id.equals(id))).getSingle());
  }

  Future<Skill> installFromText(String text, {String source = 'local'}) async => _upsert(parseSkillMd(text), source: source);

  static String _rawUrl(String url) {
    // A GitHub "blob" page link is turned into the raw file link.
    final m = RegExp(r'^https?://github\.com/([^/]+)/([^/]+)/blob/(.+)$').firstMatch(url.trim());
    if (m != null) return 'https://raw.githubusercontent.com/${m[1]}/${m[2]}/${m[3]}';
    return url.trim();
  }

  /// URL of a SKILL.md or of a .zip archive.
  Future<Skill> installFromUrl(String url) async {
    final u = Uri.tryParse(_rawUrl(url));
    if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
      throw const SkillFormatException('Enter a valid http(s) URL.');
    }
    final r = await _dio.getUri<List<int>>(u, options: Options(responseType: ResponseType.bytes));
    final bytes = r.data ?? const <int>[];
    if (bytes.length > 30 * 1024 * 1024) throw const SkillFormatException('The file is larger than 30 MB.');
    final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
    if (isZip) return installFromZipBytes(bytes, source: u.toString());
    final decoded = _decodeUtf8(bytes) ?? utf8.decode(bytes, allowMalformed: true);
    if (decoded.trimLeft().startsWith('<')) {
      throw const SkillFormatException('That URL returned a web page, not a SKILL.md. Use the "raw" file link.');
    }
    return _upsert(parseSkillMd(decoded), source: u.toString());
  }

  Future<Skill> installFromZipBytes(List<int> bytes, {String source = 'zip'}) async {
    final docs = await getApplicationDocumentsDirectory();
    final tmp = Directory('${docs.path}/skills/.tmp_${_uuid.v4()}');
    await tmp.create(recursive: true);
    try {
      final ex = await extractSkillZip(bytes, tmp.path);
      final parsed = parseSkillMd(ex.skillMd);
      final dest = Directory('${docs.path}/skills/${parsed.name}');
      if (await dest.exists()) await dest.delete(recursive: true);
      String? dir;
      if (ex.files.isNotEmpty) {
        await tmp.rename(dest.path);
        dir = dest.path;
      }
      return _upsert(parsed, source: source.startsWith('http') ? source : 'zip', dir: dir);
    } finally {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }
  }

  Future<void> setEnabled(String id, bool v) =>
      (_db.update(_db.skills)..where((s) => s.id.equals(id))).write(SkillsCompanion(enabled: Value(v)));

  Future<void> delete(Skill s) async {
    if (s.dir != null) {
      final d = Directory(s.dir!);
      if (await d.exists()) await d.delete(recursive: true);
    }
    await (_db.delete(_db.skills)..where((t) => t.id.equals(s.id))).go();
  }

  Future<void> restoreBuiltins() => ensureBuiltins(force: true);

  Future<List<String>> files(Skill s) async {
    if (s.dir == null) return const [];
    final d = Directory(s.dir!);
    if (!await d.exists()) return const [];
    final out = <String>[];
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) out.add(e.path.substring(d.path.length + 1).replaceAll('\\', '/'));
      if (out.length >= 200) break;
    }
    out.sort();
    return out;
  }

  /// What `load_skill` returns to the model.
  Future<String> load(String name, {String? file}) async {
    final slug = skillSlug(name);
    final s = await (_db.select(_db.skills)..where((t) => t.name.equals(slug) | t.name.equals(name))).getSingleOrNull();
    if (s == null || !s.enabled) {
      final all = await enabledSkills();
      throw StateError('No enabled skill named "$name". Available: ${all.map((e) => e.name).join(', ')}');
    }
    if (file != null && file.trim().isNotEmpty) {
      final rel = file.replaceAll('\\', '/').trim();
      if (s.dir == null || rel.split('/').any((p) => p == '..')) throw StateError('This skill has no file "$file".');
      final f = File('${s.dir}/$rel');
      if (!await f.exists()) throw StateError('This skill has no file "$file".');
      final len = await f.length();
      if (len > 400 * 1024) throw StateError('"$file" is too large to load (${len ~/ 1024} KB).');
      final bytes = await f.readAsBytes();
      return _decodeUtf8(bytes) ?? '(binary file, ${bytes.length} bytes)';
    }
    final fs = await files(s);
    final b = StringBuffer('# Skill: ${s.name}\n\n${s.body}');
    if (fs.isNotEmpty) {
      b.write('\n\n---\nFiles in this skill (load one with load_skill name="${s.name}" file="<path>"):\n');
      for (final f in fs) {
        b.write('- $f\n');
      }
    }
    return b.toString();
  }
}

String? _decodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

final skillsRepoProvider = Provider<SkillsRepo>((ref) => SkillsRepo(ref.watch(dbProvider)));
