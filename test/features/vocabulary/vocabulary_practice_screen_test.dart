import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_session_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_practice_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a successful Android-style attempt commits the whole group', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const store = VocabularyStore();
    const sessionStore = VocabularySessionStore();
    await store.addParentEntries(const <VocabularyTranslation>[
      VocabularyTranslation(englishText: 'Apple', vietnameseText: 'Quả táo'),
    ], now: DateTime(2026, 9, 10, 8));
    final session = await sessionStore.prepareToday(
      store,
      now: DateTime(2026, 9, 10, 9),
    );
    final media = _FakeLessonMediaService();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: VocabularyPracticeScreen(
          language: DisplayLanguage.vietnamese,
          childAge: 6,
          session: session!,
          store: store,
          sessionStore: sessionStore,
          mediaService: media,
          attemptEvaluator: const RecordedAttemptEvaluator(),
          voicePromptService: const _FakeVoicePromptService(),
          samplePause: Duration.zero,
          autoStart: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vocabulary-practice-main-action')));
    await tester.pumpAndSettle();
    expect(media.recording, isTrue);

    await tester.tap(find.byKey(const Key('vocabulary-practice-main-action')));
    await tester.pumpAndSettle();

    expect(
      find.text('Bạn muốn học tiếp hay học nội dung khác?'),
      findsOneWidget,
    );
    final learned = (await store.read()).single;
    expect(learned.status, VocabularyLearningStatus.learnedWell);
    expect(learned.correctAudioPath, '/recordings/apple.m4a');
    expect(await sessionStore.readActive(), isNull);
  });
}

class _FakeLessonMediaService extends LessonMediaService {
  bool recording = false;

  @override
  Future<void> prepareSelectedLessonOutput() async {}

  @override
  Future<void> startRecording({
    required String lessonId,
    required int sentenceNumber,
    String? lessonTitle,
    String? sentenceId,
    String? english,
    String? vietnamese,
    bool saveToHistory = true,
  }) async {
    recording = true;
  }

  @override
  Future<LessonRecording> stopRecording() async {
    recording = false;
    return const LessonRecording(
      filePath: '/recordings/apple.m4a',
      duration: Duration(seconds: 2),
    );
  }

  @override
  Future<void> cancelRecording() async {
    recording = false;
  }

  @override
  Future<void> stopPlayback() async {}
}

class _FakeVoicePromptService implements VoicePromptService {
  const _FakeVoicePromptService();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}
}
