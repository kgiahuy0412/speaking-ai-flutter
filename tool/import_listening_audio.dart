import 'dart:convert';
import 'dart:io';

const _catalogPath = 'assets/data/listening_lessons.json';
const _audioAssetRoot = 'assets/audio';
const _packagePattern = r'^AIV0_(A\d+)_AGE(\d+)-(\d+)_THEME(\d{2})_';

void main(List<String> rawArguments) {
  final arguments = List<String>.of(rawArguments);
  final apply = arguments.remove('--apply');
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/import_listening_audio.dart '
      '[--apply] <source-directory>',
    );
    exitCode = 64;
    return;
  }

  final sourceRoot = Directory(arguments.single).absolute;
  if (!sourceRoot.existsSync()) {
    throw StateError('Source directory does not exist: ${sourceRoot.path}');
  }

  final catalogFile = File(_nativePath(_catalogPath));
  final originalCatalog = catalogFile.readAsStringSync();
  final decoded = jsonDecode(originalCatalog) as Map<String, dynamic>;
  const encoder = JsonEncoder.withIndent('  ');
  final canonicalOriginal = '${encoder.convert(decoded)}\n';
  if (_normalizeLines(originalCatalog) != canonicalOriginal) {
    throw StateError(
      '$_catalogPath is not in canonical two-space JSON format. '
      'Import stopped to avoid a whole-file formatting diff.',
    );
  }

  final packagePattern = RegExp(_packagePattern);
  final packageDirectories =
      sourceRoot
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where(
            (directory) => packagePattern.hasMatch(_basename(directory.path)),
          )
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  if (packageDirectories.isEmpty) {
    throw StateError(
      'No listening audio packages found in ${sourceRoot.path}.',
    );
  }

  final assetDeclarations = <String>[];
  final linkedUris = <String>{};
  var manifestEntries = 0;
  var copiedFiles = 0;
  var unchangedFiles = 0;

  for (final outerDirectory in packageDirectories) {
    final packageName = _basename(outerDirectory.path);
    final match = packagePattern.firstMatch(packageName)!;
    final startAge = int.parse(match.group(2)!);
    final endAge = int.parse(match.group(3)!);
    final topicNumber = int.parse(match.group(4)!);
    final nestedDirectory = Directory(_join(outerDirectory.path, packageName));
    final sourcePackage = nestedDirectory.existsSync()
        ? nestedDirectory
        : outerDirectory;
    final manifestFile = File(_join(sourcePackage.path, 'audio_manifest.json'));
    final manifest = (jsonDecode(manifestFile.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final sourceMp3Count = Directory(_join(sourcePackage.path, 'audio'))
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.mp3'))
        .length;
    if (sourceMp3Count != manifest.length) {
      throw StateError(
        '$packageName has $sourceMp3Count MP3 files but '
        '${manifest.length} manifest entries.',
      );
    }

    final group = _exactlyOne(
      decoded['groups'] as List,
      (item) => item['startAge'] == startAge && item['endAge'] == endAge,
      'age group $startAge-$endAge',
    );
    final topic = _exactlyOne(
      group['topics'] as List,
      (item) => item['number'] == topicNumber,
      'topic $topicNumber in age group $startAge-$endAge',
    );

    assetDeclarations
      ..add('    - $_audioAssetRoot/$packageName/')
      ..add('    - $_audioAssetRoot/$packageName/audio/');

    for (final entry in manifest) {
      manifestEntries += 1;
      final audioId = entry['audio_id'] as String;
      final audioType = entry['audio_type'] as String;
      final relativePath = (entry['relative_path'] as String).replaceAll(
        r'\',
        '/',
      );
      if (entry['qa_status'] != 'PASS') {
        throw StateError('$audioId did not pass QA.');
      }
      final sourceFile = File(
        _joinAll(<String>[sourcePackage.path, ...relativePath.split('/')]),
      );
      if (!sourceFile.existsSync()) {
        throw StateError('Manifest file is missing: ${sourceFile.path}');
      }

      final lessonMatch = RegExp(
        r'^L(\d{2})$',
      ).firstMatch(entry['lesson_id'] as String);
      if (lessonMatch == null) {
        throw FormatException('Invalid lesson ID for $audioId.');
      }
      final lessonNumber = int.parse(lessonMatch.group(1)!);
      final lesson = _exactlyOne(
        topic['lessons'] as List,
        (item) => item['number'] == lessonNumber,
        'lesson $lessonNumber in $packageName',
      );
      final uri = 'asset:///$_audioAssetRoot/$packageName/$relativePath';
      if (!linkedUris.add(uri)) {
        throw StateError('Duplicate audio URI: $uri');
      }

      switch (audioType) {
        case 'lesson_opening':
          lesson['introAudioUrl'] = uri;
        case 'learning_sentence':
          final sentence = _sentenceFor(entry, lesson, 'EN');
          _expectText(sentence['english'], entry['source_text'], audioId);
          sentence['audioUrl'] = uri;
        case 'meaning_sentence':
          final sentence = _sentenceFor(entry, lesson, 'VI');
          _expectText(sentence['vietnamese'], entry['source_text'], audioId);
          sentence['vietnameseAudioUrl'] = uri;
        case 'dialogue_transition':
          lesson['dialogueTransitionAudioId'] = audioId;
          lesson['dialogueTransitionAudioUrl'] = uri;
        case 'full_dialogue':
          if (lesson['lessonType'] != 'dialogue') {
            throw StateError('$audioId belongs to a non-dialogue lesson.');
          }
          lesson['fullAudioId'] = audioId;
          lesson['fullAudioUrl'] = uri;
        default:
          throw UnsupportedError('Unsupported audio type: $audioType');
      }
    }

    if (apply) {
      final targetPackage = Directory(
        _joinAll(<String>[
          Directory.current.path,
          ..._audioAssetRoot.split('/'),
          packageName,
        ]),
      );
      final result = _syncDirectory(sourcePackage, targetPackage);
      copiedFiles += result.copied;
      unchangedFiles += result.unchanged;
    }
  }

  if (manifestEntries != linkedUris.length) {
    throw StateError(
      'Linked ${linkedUris.length} unique URIs for $manifestEntries entries.',
    );
  }

  if (apply) {
    catalogFile.writeAsStringSync('${encoder.convert(decoded)}\n', flush: true);
    _updatePubspec(assetDeclarations);
  }

  stdout.writeln('packages=${packageDirectories.length}');
  stdout.writeln('manifest_entries=$manifestEntries');
  stdout.writeln('linked_uris=${linkedUris.length}');
  stdout.writeln('copied_files=$copiedFiles');
  stdout.writeln('unchanged_files=$unchangedFiles');
  stdout.writeln('mode=${apply ? 'apply' : 'dry-run'}');
}

Map<String, dynamic> _sentenceFor(
  Map<String, dynamic> entry,
  Map<String, dynamic> lesson,
  String language,
) {
  final audioId = entry['audio_id'] as String;
  final match = RegExp('_S(\\d{3})_$language\$').firstMatch(audioId);
  if (match == null) {
    throw FormatException('Invalid sentence audio ID: $audioId');
  }
  final sentenceNumber = int.parse(match.group(1)!);
  return _exactlyOne(
    lesson['sentences'] as List,
    (item) => item['number'] == sentenceNumber,
    'sentence $sentenceNumber for $audioId',
  );
}

void _expectText(Object? catalogText, Object? manifestText, String audioId) {
  if ((catalogText as String).trim() != (manifestText as String).trim()) {
    throw StateError('Manifest text does not match the catalog for $audioId.');
  }
}

Map<String, dynamic> _exactlyOne(
  List<dynamic> items,
  bool Function(Map<String, dynamic>) predicate,
  String description,
) {
  final matches = items
      .cast<Map<String, dynamic>>()
      .where(predicate)
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError('Expected one $description, found ${matches.length}.');
  }
  return matches.single;
}

({int copied, int unchanged}) _syncDirectory(
  Directory source,
  Directory target,
) {
  target.createSync(recursive: true);
  var copied = 0;
  var unchanged = 0;
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final targetPath = _join(target.path, relative);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
      continue;
    }
    if (entity is! File) {
      throw UnsupportedError('Unsupported package entry: ${entity.path}');
    }
    final targetFile = File(targetPath);
    targetFile.parent.createSync(recursive: true);
    if (targetFile.existsSync() && _filesEqual(entity, targetFile)) {
      unchanged += 1;
      continue;
    }
    entity.copySync(targetFile.path);
    copied += 1;
  }
  return (copied: copied, unchanged: unchanged);
}

bool _filesEqual(File left, File right) {
  if (left.lengthSync() != right.lengthSync()) {
    return false;
  }
  final leftBytes = left.readAsBytesSync();
  final rightBytes = right.readAsBytesSync();
  for (var index = 0; index < leftBytes.length; index += 1) {
    if (leftBytes[index] != rightBytes[index]) {
      return false;
    }
  }
  return true;
}

void _updatePubspec(List<String> assetDeclarations) {
  final pubspec = File('pubspec.yaml');
  final lines = const LineSplitter().convert(pubspec.readAsStringSync());
  lines.removeWhere(
    (line) => line.trimLeft().startsWith('- $_audioAssetRoot/'),
  );
  final dataAssetIndex = lines.indexWhere(
    (line) => line.trim() == '- $_catalogPath',
  );
  if (dataAssetIndex < 0) {
    throw StateError('Could not find $_catalogPath in pubspec.yaml.');
  }
  lines.insertAll(dataAssetIndex + 1, assetDeclarations);
  pubspec.writeAsStringSync('${lines.join('\n')}\n', flush: true);
}

String _normalizeLines(String value) => value.replaceAll('\r\n', '\n');

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _join(String left, String right) =>
    '$left${Platform.pathSeparator}$right';

String _joinAll(List<String> parts) => parts.join(Platform.pathSeparator);

String _nativePath(String path) => path.replaceAll('/', Platform.pathSeparator);
