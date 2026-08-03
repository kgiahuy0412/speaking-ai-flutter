# Design QA — shared minimal background

- Date: 2026-08-02
- Scope: Flutter Web and Android UI
- Shared background: `assets/images/learning-minimal-sky-background.png`
- Explicit exception: `SongKaraokeScreen` keeps `assets/images/song-karaoke-sunrise.webp`

## Checks

- Conversation, topic catalog, topic lesson list, lesson intro, lesson practice, lesson review, vocabulary, PWA install, Android update splash, and required-update screen use `LearningScenery`.
- Song karaoke default asset is isolated through `songKaraokeBackgroundAsset`.
- Conversation feedback buttons remain removed.
- Web viewport inspection confirmed the shared background on conversation and topic screens.
- Topic image fetch warnings appeared only when the temporary preview server reached its configured timeout; the corresponding source and built assets are present.
- Flutter analyze passed for all changed Dart files.
- 24 focused widget/golden tests passed.
- Web release build passed.
- Android release APK build passed.
- Visual comparison: `background-scope-board.png`.

## Result

final result: passed
