import 'dart:convert';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/data/vocabulary_store.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_entry.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/presentation/vocabulary_home_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens the three vocabulary journeys from the redesigned home', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    expect(find.byKey(const Key('vocabulary-family-card')), findsOneWidget);
    expect(find.byKey(const Key('vocabulary-stars-card')), findsOneWidget);
    expect(find.byKey(const Key('vocabulary-review-card')), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-family-card')));
    await tester.pumpAndSettle();
    expect(find.text('Gia đình'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-back-to-journeys')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
    await tester.pumpAndSettle();
    expect(find.text('Ngôi sao của con'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-back-to-journeys')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('vocabulary-review-card')));
    await tester.pumpAndSettle();
    expect(find.text('Luyện lại'), findsOneWidget);
  });

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

  testWidgets('shows lesson sentences in Stars and Review collections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime(2026, 8, 14);
    final store = _MemoryVocabularyStore(<VocabularyEntry>[
      VocabularyEntry(
        id: 'star',
        word: "I'm An",
        meaning: 'Con là An',
        addedAt: now,
        collection: VocabularyCollection.star,
        sourceSentenceId: 'S1',
      ),
      VocabularyEntry(
        id: 'review',
        word: 'This is my bag',
        meaning: 'Đây là cặp của con',
        addedAt: now,
        collection: VocabularyCollection.review,
        sourceSentenceId: 'S2',
      ),
    ]);
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

    expect(find.text('1 từ yêu thích'), findsOneWidget);
    expect(find.text('1 từ cần ôn'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vocabulary-stars-card')));
    await tester.pumpAndSettle();
    expect(find.text("I'm An"), findsOneWidget);
    expect(find.text('This is my bag'), findsNothing);

    await tester.tap(find.byKey(const Key('vocabulary-back-to-journeys')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('vocabulary-review-card')));
    await tester.tap(find.byKey(const Key('vocabulary-review-card')));
    await tester.pumpAndSettle();
    expect(find.text('This is my bag'), findsOneWidget);
    expect(find.text("I'm An"), findsNothing);
  });

  testWidgets('refreshes collection counts after a lesson saves a sentence', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'innotrik.vocabulary.v1': jsonEncode(<Object>[]),
    });
    const store = VocabularyStore();
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
    expect(find.text('0 từ yêu thích'), findsOneWidget);

    await store.upsertLessonSentence(
      lessonCode: 'A035_T01_L01',
      sentenceId: 'S1',
      english: "I'm An",
      vietnamese: 'Con là An',
      collection: VocabularyCollection.star,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 từ yêu thích'), findsOneWidget);
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

  testWidgets('MAIN vocabulary commands open Review and Stars journeys', (
    tester,
  ) async {
    final registry = ActiveLearningModuleRegistry();
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ActiveLearningModuleScope(
          registry: registry,
          child: DisplayLanguageScope(
            language: DisplayLanguage.vietnamese,
            child: VocabularyHomeScreen(
              isReady: true,
              isActive: true,
              store: _MemoryVocabularyStore(),
              voicePromptService: const _FakeVoicePromptService(),
              onReturnToConversation: () {},
              onHistory: () {},
              onSettings: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(registry.activeKind, ActiveLearningModuleKind.vocabulary);
    await registry.pauseForMainAssistant();
    expect(registry.isActiveModulePaused, isTrue);

    final review = await registry.execute(
      ActiveLearningCommand.vocabularyPracticeAgain,
    );
    await tester.pumpAndSettle();
    expect(review.wasHandled, isTrue);
    expect(find.text('Luyện lại'), findsOneWidget);

    final stars = await registry.execute(ActiveLearningCommand.vocabularyStars);
    await tester.pumpAndSettle();
    expect(stars.wasHandled, isTrue);
    expect(find.text('Ngôi sao của con'), findsOneWidget);
  });
}

class _MemoryVocabularyStore extends VocabularyStore {
  _MemoryVocabularyStore([List<VocabularyEntry>? entries])
    : entries = List.of(entries ?? const <VocabularyEntry>[]);

  List<VocabularyEntry> entries;

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
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) async {}

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
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
