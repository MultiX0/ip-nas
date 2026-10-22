// Agent Skills format: SKILL.md = YAML front matter (name, description, ...) + markdown body.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:yaml/yaml.dart';

class ParsedSkill {
  final String name;
  final String description;
  final String body;
  const ParsedSkill(this.name, this.description, this.body);
}

class SkillFormatException implements Exception {
  final String message;
  const SkillFormatException(this.message);
  @override
  String toString() => message;
}

/// Lowercase letters, digits and hyphens, max 64 chars (Agent Skills naming rule).
String skillSlug(String s) {
  final v = s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9؀-ۿ-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return v.length > 64 ? v.substring(0, 64) : v;
}

ParsedSkill parseSkillMd(String raw) {
  var text = raw.replaceAll('\r\n', '\n');
  if (text.startsWith('﻿')) text = text.substring(1);
  text = text.trimLeft();
  if (!text.startsWith('---')) {
    throw const SkillFormatException('SKILL.md must start with a "---" front matter block containing name and description.');
  }
  final end = RegExp(r'^---\s*$', multiLine: true).allMatches(text).skip(1).firstOrNull;
  if (end == null) throw const SkillFormatException('The front matter block is not closed with "---".');
  final yamlText = text.substring(text.indexOf('\n') + 1, end.start);
  final body = text.substring(end.end).trim();
  dynamic meta;
  try {
    meta = loadYaml(yamlText);
  } catch (e) {
    throw SkillFormatException('Invalid YAML front matter: $e');
  }
  if (meta is! Map) throw const SkillFormatException('The front matter must be a YAML map with name and description.');
  final name = skillSlug((meta['name'] ?? '').toString());
  final description = (meta['description'] ?? '').toString().trim();
  if (name.isEmpty) throw const SkillFormatException('The skill has no "name" in its front matter.');
  if (description.isEmpty) throw const SkillFormatException('The skill has no "description" in its front matter.');
  if (description.length > 1024) throw const SkillFormatException('The description is longer than 1024 characters.');
  if (body.isEmpty) throw const SkillFormatException('The skill body (instructions after the front matter) is empty.');
  return ParsedSkill(name, description, body);
}

class ExtractedZip {
  final String skillMd;
  final List<String> files; // relative paths written next to SKILL.md
  const ExtractedZip(this.skillMd, this.files);
}

/// Unzips a skill archive into [destDir] in a background isolate. The folder holding the shallowest SKILL.md is
/// the skill root; only files under it are kept. Guards against path traversal and zip bombs.
Future<ExtractedZip> extractSkillZip(List<int> bytes, String destDir) => Isolate.run(() async {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? md;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final n = f.name.replaceAll('\\', '/');
        if (n.split('/').last.toUpperCase() != 'SKILL.MD') continue;
        if (n.contains('__MACOSX')) continue;
        if (md == null || n.split('/').length < md.name.replaceAll('\\', '/').split('/').length) md = f;
      }
      if (md == null) throw const SkillFormatException('No SKILL.md found in the zip.');
      final mdName = md.name.replaceAll('\\', '/');
      final root = mdName.contains('/') ? mdName.substring(0, mdName.lastIndexOf('/') + 1) : '';
      final skillMd = utf8.decode(md.content, allowMalformed: true);
      final written = <String>[];
      var total = 0;
      for (final f in archive.files) {
        if (!f.isFile) continue;
        final n = f.name.replaceAll('\\', '/');
        if (!n.startsWith(root) || n == mdName || n.contains('__MACOSX')) continue;
        final rel = n.substring(root.length);
        if (rel.isEmpty || rel.startsWith('/') || rel.split('/').any((p) => p == '..' || p.contains(':'))) continue;
        final data = f.content;
        total += data.length;
        if (total > 50 * 1024 * 1024 || written.length >= 500) {
          throw const SkillFormatException('The skill archive is too large (max 50 MB / 500 files).');
        }
        final out = File('$destDir/$rel');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(data);
        written.add(rel);
      }
      return ExtractedZip(skillMd, written);
    });

