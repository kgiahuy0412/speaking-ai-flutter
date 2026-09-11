import 'dart:io';

final class ArchitectureViolation {
  const ArchitectureViolation({required this.file, required this.message});

  final String file;
  final String message;

  @override
  String toString() => '$file: $message';
}

List<ArchitectureViolation> checkArchitectureBoundaries(Directory root) {
  final violations = <ArchitectureViolation>[];
  final libDirectory = Directory(_join(root.path, 'lib'));
  final featureDirectory = Directory(_join(libDirectory.path, 'features'));
  if (!featureDirectory.existsSync()) {
    return <ArchitectureViolation>[
      const ArchitectureViolation(
        file: 'lib/features',
        message: 'feature directory is missing',
      ),
    ];
  }

  final dartFiles = libDirectory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final source = _relativePath(root, file.path);
    final content = file.readAsStringSync();

    if (source.startsWith('lib/core/') &&
        _resolvedImports(
          root,
          file,
          content,
        ).any((target) => target.startsWith('lib/features/'))) {
      violations.add(
        ArchitectureViolation(
          file: source,
          message: 'core must not depend on a feature module',
        ),
      );
    }

    if (!source.startsWith('lib/features/')) continue;

    if (source.contains('/presentation/') &&
        (RegExp(r'\bMethodChannel\s*\(').hasMatch(content) ||
            RegExp(r'\bEventChannel\s*\(').hasMatch(content))) {
      violations.add(
        ArchitectureViolation(
          file: source,
          message: 'presentation must use a platform adapter, not a channel',
        ),
      );
    }

    for (final target in _resolvedImports(root, file, content)) {
      if (_isLogicLayer(source) && target.contains('/presentation/')) {
        violations.add(
          ArchitectureViolation(
            file: source,
            message: 'logic layer imports presentation: $target',
          ),
        );
      }

      if (_isForbiddenConversationPresentationDependency(source, target)) {
        violations.add(
          ArchitectureViolation(
            file: source,
            message:
                'feature must depend on an audio/session port, not conversation presentation: $target',
          ),
        );
      }

      if (_isUnapprovedCrossFeaturePresentationImport(source, target)) {
        violations.add(
          ArchitectureViolation(
            file: source,
            message: 'unapproved cross-feature presentation import: $target',
          ),
        );
      }
    }
  }

  return violations;
}

Iterable<String> _resolvedImports(
  Directory root,
  File source,
  String content,
) sync* {
  final importPattern = RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  for (final match in importPattern.allMatches(content)) {
    final importValue = match.group(1)!;
    String? absoluteTarget;
    const packagePrefix = 'package:ai_speaking_flutter_app/';
    if (importValue.startsWith(packagePrefix)) {
      absoluteTarget = _join(
        root.path,
        'lib/${importValue.substring(packagePrefix.length)}',
      );
    } else if (!importValue.contains(':')) {
      absoluteTarget = Uri.file(
        source.absolute.path,
        windows: Platform.isWindows,
      ).resolve(importValue).toFilePath(windows: Platform.isWindows);
    }
    if (absoluteTarget != null) {
      yield _relativePath(root, absoluteTarget);
    }
  }
}

bool _isLogicLayer(String source) =>
    source.contains('/application/') ||
    source.contains('/domain/') ||
    source.contains('/data/');

bool _isForbiddenConversationPresentationDependency(
  String source,
  String target,
) {
  final isolatedFeature =
      source.startsWith('lib/features/listening/') ||
      source.startsWith('lib/features/vocabulary/') ||
      source.startsWith('lib/features/voice_navigation/');
  return isolatedFeature &&
      target.startsWith('lib/features/conversation/presentation/');
}

bool _isUnapprovedCrossFeaturePresentationImport(String source, String target) {
  final sourceParts = source.split('/');
  final targetParts = target.split('/');
  if (sourceParts.length < 5 || targetParts.length < 5) return false;
  if (sourceParts[0] != 'lib' || sourceParts[1] != 'features') return false;
  if (targetParts[0] != 'lib' || targetParts[1] != 'features') return false;
  if (!target.contains('/presentation/')) return false;

  final sourceFeature = sourceParts[2];
  final targetFeature = targetParts[2];
  if (sourceFeature == targetFeature) return false;

  if (source == 'lib/features/home/presentation/home_learning_shell.dart') {
    return false;
  }

  return true;
}

String _relativePath(Directory root, String path) {
  final normalizedRoot = _normalize(root.absolute.path);
  final normalizedPath = _normalize(File(path).absolute.path);
  final prefix = normalizedRoot.endsWith('/')
      ? normalizedRoot
      : '$normalizedRoot/';
  if (!normalizedPath.startsWith(prefix)) return normalizedPath;
  return normalizedPath.substring(prefix.length);
}

String _join(String first, String second) =>
    '${first.replaceAll(RegExp(r'[\\/]+$'), '')}${Platform.pathSeparator}'
    '${second.replaceAll('/', Platform.pathSeparator)}';

String _normalize(String path) => path.replaceAll('\\', '/');

void main() {
  final violations = checkArchitectureBoundaries(Directory.current);
  if (violations.isEmpty) {
    stdout.writeln('Architecture boundaries: OK');
    return;
  }

  stderr.writeln('Architecture boundary violations:');
  for (final violation in violations) {
    stderr.writeln(' - $violation');
  }
  exitCode = 1;
}
