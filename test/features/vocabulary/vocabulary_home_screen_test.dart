import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adds a Vietnamese vocabulary entry and persists it', (
    tester,
  ) async {
    final store = _MemoryVocabularyStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DisplayLanguageScope(
          language: DisplayLanguage.vietnamese,
          child: VocabularyHomeScreen(
            isReady: true,
            store: store,
            voicePromptService: const _FakeVoicePromptService(),
            onReturnToConversation: () {},
            onHistory: () {},
            onSettings: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-vocabulary-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-vocabulary-field')),
      'quả táo',
    );
    await tester.pump();
    final confirm = find.byKey(const Key('confirm-add-vocabulary'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(store.entries.first.word, 'Apple');
    expect(store.entries.first.meaning, 'Quả táo');
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Quả táo'), findsOneWidget);
  });

  testWidgets(
    'translates an unknown Vietnamese word and speaks only its English text',
    (tester) async {
      final store = _MemoryVocabularyStore();
      final voice = _RecordingVoicePromptService();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              store: store,
              voicePromptService: voice,
              translator: (input) async {
                expect(input, 'con mèo');
                return const VocabularyTranslation(
                  englishText: 'cat',
                  vietnameseText: 'con mèo',
                );
              },
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-vocabulary-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add-vocabulary-field')),
        'con mèo',
      );
      await tester.pump();
      final confirm = find.byKey(const Key('confirm-add-vocabulary'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(store.entries, hasLength(1));
      expect(store.entries.single.word, 'Cat');
      expect(store.entries.single.meaning, 'Con mèo');
      expect(find.text('Cat'), findsOneWidget);
      expect(find.text('Con mèo'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pump();

      expect(voice.spokenTexts, <String>['Cat']);
      expect(voice.locales, <String>['en-US']);
    },
  );
}

class _MemoryVocabularyStore extends VocabularyStore {
  List<VocabularyEntry> entries = <VocabularyEntry>[];

  @override
  Future<List<VocabularyEntry>> read() async => entries;

  @override
  Future<void> write(List<VocabularyEntry> value) async {
    entries = List<VocabularyEntry>.of(value);
  }
}

class _FakeVoicePromptService implements VoicePromptService {
  const _FakeVoicePromptService();

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _RecordingVoicePromptService implements VoicePromptService {
  final List<String> spokenTexts = <String>[];
  final List<String> locales = <String>[];

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spokenTexts.add(text);
    locales.add(locale);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
