import 'package:ai_speaking_flutter_app/features/conversation/domain/conversation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves a relative audio URL against the backend', () {
    final result = ConversationResult.fromJson(<String, dynamic>{
      'conversationId': 'conv_1',
      'sessionId': 'sess_1',
      'context': 'school',
      'vietnameseText': 'Con cần bút chì',
      'englishText': 'I need a pencil, please.',
      'audioUrl': '/api/audio/stream?text=pencil',
      'processingMode': 'rule',
      'textSource': 'phrase_rule',
      'audioSource': 'cache',
      'asrMode': 'batch_chunks',
      'latency': <String, dynamic>{
        'asrMs': 10,
        'llmMs': 3,
        'ttsMs': 1,
        'timeToFirstAudioMs': 14,
      },
    }, backendBaseUri: Uri.parse('https://api.example.com'));

    expect(
      result.audioUri,
      Uri.parse('https://api.example.com/api/audio/stream?text=pencil'),
    );
    expect(result.context, PracticeContext.school);
  });

  test('history converts timestamps to local time and keeps metadata', () {
    final sourceTime = DateTime.parse('2026-07-20T13:35:21.399Z');
    final item = ConversationHistoryItem.fromJson(<String, dynamic>{
      'conversationId': 'conv_history_1',
      'context': 'outside',
      'vietnameseText': 'Ngày mai mình đi công viên nhé.',
      'englishText': 'Can we go to the park tomorrow?',
      'audioUrl': '/api/audio/stream?text=park',
      'createdAt': sourceTime.toIso8601String(),
      'qualityApproved': false,
      'learningStatus': 'observing',
      'learningUseCount': 2,
      'processingMode': 'ai',
      'textSource': 'openai',
      'audioSource': 'openai_tts',
      'asrMode': 'batch_chunks',
      'inputMode': 'audio',
      'latency': <String, dynamic>{
        'asrMs': 1708,
        'llmMs': 1681,
        'ttsMs': 1,
        'timeToFirstAudioMs': 6538,
      },
    }, backendBaseUri: Uri.parse('https://api.example.com'));

    expect(item.createdAt, sourceTime.toLocal());
    expect(item.createdAt.isUtc, isFalse);
    expect(item.reviewStatus, HistoryReviewStatus.rejected);
    expect(item.context, PracticeContext.outside);
    expect(item.processingMode, 'ai');
    expect(item.asrMode, 'batch_chunks');
    expect(item.latency.timeToFirstAudioMs, 6538);
    expect(item.learningStatus, 'observing');
    expect(item.learningUseCount, 2);
    expect(
      item.audioUri,
      Uri.parse('https://api.example.com/api/audio/stream?text=park'),
    );
  });

  test('history distinguishes unreviewed and approved items', () {
    final pending = ConversationHistoryItem.fromJson(<String, dynamic>{
      'conversationId': 'pending',
      'createdAt': '2026-07-20T13:35:21.399Z',
    });
    final approved = ConversationHistoryItem.fromJson(<String, dynamic>{
      'conversationId': 'approved',
      'createdAt': '2026-07-20T13:35:21.399Z',
      'qualityApproved': true,
    });

    expect(pending.reviewStatus, HistoryReviewStatus.pending);
    expect(approved.reviewStatus, HistoryReviewStatus.approved);
    expect(
      pending.copyWithReview(false).reviewStatus,
      HistoryReviewStatus.rejected,
    );
  });

  test('parses an automatic learning outcome from a conversation', () {
    final result = ConversationResult.fromJson(<String, dynamic>{
      'conversationId': 'conv_learning',
      'sessionId': 'sess_learning',
      'context': 'home',
      'vietnameseText': 'Con muốn đi công viên',
      'englishText': 'I want to go to the park.',
      'audioUrl': null,
      'processingMode': 'ai',
      'textSource': 'text_cache',
      'audioSource': 'cache',
      'asrMode': 'android_streaming',
      'latency': <String, dynamic>{},
      'learning': <String, dynamic>{
        'status': 'observing',
        'promoted': false,
        'useCount': 2,
        'threshold': 3,
        'message': 'Đang học câu này.',
      },
    }, backendBaseUri: Uri.parse('https://api.example.com'));

    expect(result.learning?.status, 'observing');
    expect(result.learning?.useCount, 2);
    expect(result.learning?.threshold, 3);
  });
}
