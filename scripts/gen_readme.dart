import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/gen_readme.dart <module_path>');
    exit(1);
  }

  final modulePath = args[0];
  final moduleDir = Directory(modulePath);
  if (!moduleDir.existsSync()) {
    stderr.writeln('Module path does not exist: $modulePath');
    exit(2);
  }

  _ensureOptionalFiles(moduleDir);

  final moduleName = moduleDir.uri.pathSegments.isNotEmpty
      ? moduleDir.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList()
          .last
      : modulePath;

  final files = _scanDartFiles(moduleDir);
  final architecture = _describeArchitecture(moduleDir);
  final debugNotes = _readOptional(moduleDir, 'DEBUG_NOTES.md');
  final errorLog = _readOptional(moduleDir, 'ERROR_LOG.md');
  final updateHistory = _readOptional(moduleDir, 'UPDATE_HISTORY.md');
  final userSection = _readUserSection(moduleDir);

  final b = StringBuffer();
  b.writeln('# $moduleName');
  b.writeln('');
  b.writeln('## Module Overview');
  b.writeln('');
  b.writeln(_moduleDescription(moduleName));
  b.writeln('');
  b.writeln('## Architecture');
  b.writeln('');
  b.writeln('```');
  b.writeln(architecture);
  b.writeln('```');
  b.writeln('');
  b.writeln('## File Structure');
  b.writeln('');
  for (final entry in files.entries) {
    b.writeln('### ${entry.key}');
    b.writeln('');
    b.writeln(entry.value.isEmpty ? 'No documentation available.' : entry.value);
    b.writeln('');
  }
  if (userSection.isNotEmpty) {
    b.writeln(userSection.trimRight());
    b.writeln('');
  }
  b.writeln('## Debug Notes');
  b.writeln('');
  b.writeln(debugNotes.isEmpty ? 'No debug notes documented yet.' : debugNotes);
  b.writeln('');
  b.writeln('## Error Log');
  b.writeln('');
  b.writeln(errorLog.isEmpty ? 'No errors recorded yet.' : errorLog);
  b.writeln('');
  b.writeln('## Update History');
  b.writeln('');
  b.writeln(updateHistory.isEmpty
      ? _defaultHistory()
      : updateHistory);

  stdout.write(b.toString());
}

Map<String, String> _scanDartFiles(Directory moduleDir) {
  final out = <String, String>{};
  for (final entity
      in moduleDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (entity.path.contains('/.dart_tool/')) continue;
    if (entity.path.contains('/build/')) continue;

    final rel = _relativePath(moduleDir.path, entity.path);
    final content = entity.readAsStringSync();
    out[rel] = _extractLeadingDocComment(content);
  }
  final keys = out.keys.toList()..sort();
  return {for (final k in keys) k: out[k]!};
}

void _ensureOptionalFiles(Directory moduleDir) {
  // These files are optional for content, but required for stable README
  // generation and to encourage consistent documentation habits.
  const names = <String>[
    'DEBUG_NOTES.md',
    'ERROR_LOG.md',
    'UPDATE_HISTORY.md',
  ];
  for (final name in names) {
    final f = File('${moduleDir.path}/$name');
    if (!f.existsSync()) {
      f.writeAsStringSync('');
    }
  }
}

String _relativePath(String root, String full) {
  final r = root.endsWith('/') ? root : '$root/';
  if (full.startsWith(r)) return full.substring(r.length);
  return full;
}

String _extractLeadingDocComment(String content) {
  final lines = content.split('\n');
  final b = StringBuffer();
  for (final line in lines) {
    final t = line.trimRight();
    if (t.trim().startsWith('///')) {
      b.writeln(t.trim().substring(3).trim());
      continue;
    }
    // Stop at first non-doc non-empty line.
    if (t.trim().isNotEmpty) break;
  }
  return b.toString().trim();
}

String _describeArchitecture(Directory moduleDir) {
  final parts = <String>[];

  final libDir = Directory('${moduleDir.path}/lib');
  if (libDir.existsSync()) {
    parts.add('Dart/Flutter module with lib/.');
  }

  if (Directory('${moduleDir.path}/lib/entities').existsSync()) {
    parts.add('Contains domain/entities definitions.');
  }
  if (Directory('${moduleDir.path}/lib/services').existsSync()) {
    parts.add('Contains service-layer logic.');
  }
  // Prefer describing UI if lib/widgets exists, but also detect the common
  // `lib/widgets/` placeholder being created later.
  if (Directory('${moduleDir.path}/lib/widgets').existsSync()) {
    parts.add('Contains UI widgets.');
  }
  if (Directory('${moduleDir.path}/test').existsSync()) {
    parts.add('Has module-local tests.');
  }

  if (parts.isEmpty) return 'Standard module structure.';
  return parts.join('\n');
}

String _readOptional(Directory moduleDir, String filename) {
  final f = File('${moduleDir.path}/$filename');
  if (!f.existsSync()) return '';
  return f.readAsStringSync().trim();
}

/// Preserve user-editable section inside README.md.
///
/// The section is defined by:
///   <!-- USER -->
///   ...
///   <!-- /USER -->
///
/// If no markers exist, return a default empty user section template.
String _readUserSection(Directory moduleDir) {
  final readme = File('${moduleDir.path}/README.md');
  if (!readme.existsSync()) {
    return _defaultUserSection();
  }

  final content = readme.readAsStringSync();
  final start = '<!-- USER -->';
  final end = '<!-- /USER -->';
  final startIndex = content.indexOf(start);
  final endIndex = content.indexOf(end);

  if (startIndex == -1 || endIndex == -1 || endIndex < startIndex) {
    return _defaultUserSection();
  }

  final section = content.substring(startIndex, endIndex + end.length);
  return section.trimRight();
}

String _defaultUserSection() {
  return '## User Notes\n\n'
      '<!-- USER -->\n'
      '\n'
      '<!-- /USER -->\n';
}

String _moduleDescription(String moduleName) {
  switch (moduleName) {
    case 'cloudplayplus_core':
      return 'Shared core library for iTerm2 remote streaming. Contains models, '
          'protocol definitions, and utilities reused by host and client.';
    case 'iterm2_host':
      return 'macOS host module. Responsible for iTerm2 integration via Python '
          'API scripts and hosting WebRTC sessions.';
    case 'android_client':
      return 'Flutter Android client for receiving iTerm2 streams (video/chat) '
          'and sending user input back to the host.';
    default:
      return 'iTerm2 remote streaming module.';
  }
}

String _defaultHistory() {
  return '## [0.1.0] - Initial Release\n'
      '- Initial module structure\n'
      '- CI gates enabled\n'
      '- Placeholder implementation\n';
}
