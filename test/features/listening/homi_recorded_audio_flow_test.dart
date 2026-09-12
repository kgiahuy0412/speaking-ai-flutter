import 'dart:async';

import 'package:ai_speaking_flutter_app/app/app_theme.dart';
import 'package:ai_speaking_flutter_app/core/audio/voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/homi_audio_library.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/lesson_media_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/application/recorded_lesson_voice_prompt_service.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/listening_content.dart';
import 'package:ai_speaking_flutter_app/features/listening/domain/lesson_guide_flow.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_challenge_screen.dart';
import 'package:ai_speaking_flutter_app/features/listening/presentation/lesson_mission_screen.dart';
import 'package:ai_speaking_flutter_app/l10n/display_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ListeningLessonContent lesson;
  late List<ListeningMissionContent> missions;
  setUpAll(() async {
    final catalog = await AssetListeningContentRepository().load();
    lesson = catalog.groups.first.topics.first.lessons.first;
    missions = catalog.groups.first.levels.first.missionBank.take(4).toList();
    await HomiAudioLibrary().uriForAudioCode('CORE_SPEAK_01');
  });

  for (final mission in [false, true]) {
    testWidgets(
      '${mission ? 'Mission' : 'Challenge'} keeps the mic closed until its recorded prompt ends',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final media = _HeldPromptMedia();
        final voice = _Voice();
        final service = RecordedLessonVoicePromptService(
          mediaService: media,
          fallback: voice,
          age: 4,
        );
        final screen = mission
            ? LessonMissionScreen(
                language: DisplayLanguage.vietnamese,
                startAge: 3,
                lesson: lesson,
                missions: missions,
                mediaService: media,
                attemptEvaluator: RecordedAttemptEvaluator(),
                voicePromptService: service,
              )
            : LessonChallengeScreen(
                language: DisplayLanguage.vietnamese,
                startAge: 3,
                lesson: lesson,
                challenges: lesson.challengeBank.take(2).toList(),
                mediaService: media,
                attemptEvaluator: RecordedAttemptEvaluator(),
                voicePromptService: service,
              );
        await tester.pumpWidget(
          MaterialApp(theme: buildAppTheme(), home: screen),
        );
        // The index is preloaded above; flush the async prompt chain before
        // advancing the fake clock beyond the old ten-second TTS watchdog.
        for (var i = 0; i < 8 && media.played.isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        final id = mission ? missions.first.id : lesson.challengeBank.first.id;
        expect(
          media.played,
          hasLength(1),
          reason: 'Fallback speech: ${voice.spoken}',
        );
        expect(media.played.single.scheme, 'https');
        expect(
          media.played.single.path,
          matches('/${id}_PROMPT-[0-9a-f]{16}\\.mp3\$'),
        );
        expect(voice.spoken, isEmpty);
        await tester.pump(const Duration(seconds: 12));
        expect(media.recordingStarts, 0);
        media.release();
        for (var i = 0; i < 8 && media.recordingStarts == 0; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(media.recordingStarts, 1);
        expect(
          voice.spoken,
          hasLength(1),
        ); // Invitation follows the full prompt.
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _HeldPromptMedia extends LessonMediaService {
  final started = Completer<void>();
  final completion = Completer<void>();
  final played = <Uri>[];
  int recordingStarts = 0;
  void release() {
    if (!completion.isCompleted) completion.complete();
  }

  @override
  Future<void> playToCompletion(
    Uri uri, {
    Duration timeout = const Duration(seconds: 45),
    LessonPlaybackRoute route = LessonPlaybackRoute.selectedLessonDevice,
  }) async {
    played.add(uri);
    if (!started.isCompleted) started.complete();
    await completion.future;
  }

  @override
  Future<void> prepareSelectedLessonOutput() async {}
  @override
  Future<void> stopPlayback() async => release();
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
    recordingStarts++;
  }

  @override
  Future<void> cancelRecording() async {}
}

class _Voice implements VoicePromptService {
  final spoken = <String>[];
  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) async {
    spoken.add(text);
  }

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      speak(text, locale: locale);
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
