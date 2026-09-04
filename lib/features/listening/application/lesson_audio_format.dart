String lessonAudioExtensionForPath(String recordingPath) {
  if (recordingPath.startsWith('blob:')) return 'webm';

  final normalized = recordingPath
      .split('#')
      .first
      .split('?')
      .first
      .replaceAll('\\', '/');
  final filename = normalized.split('/').last.toLowerCase();
  for (final extension in const <String>['wav', 'm4a', 'webm']) {
    if (filename.endsWith('.$extension')) return extension;
  }
  return 'm4a';
}
