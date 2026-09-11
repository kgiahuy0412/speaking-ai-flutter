import 'audio_turn_coordinator.dart';
import 'voice_prompt_service_base.dart';

/// Adds process-wide prompt ownership without changing the platform prompt
/// implementation or its public contract.
class CoordinatedVoicePromptService
    implements
        VoicePromptService,
        SpeechReadyCuePlayer,
        PhoneSpeakerVoicePromptService,
        SelectedMediaOutputVoicePromptService,
        MainTurnVoicePromptService {
  CoordinatedVoicePromptService({
    required VoicePromptService delegate,
    required AudioTurnCoordinator coordinator,
    required AudioTurnOwner owner,
  }) : _delegate = delegate,
       _coordinator = coordinator,
       _owner = owner;

  final VoicePromptService _delegate;
  final AudioTurnCoordinator _coordinator;
  final AudioTurnOwner _owner;
  AudioTurnCancellation _pendingCancellation = AudioTurnCancellation();
  AudioTurnLease? _activeLease;
  bool _disposed = false;

  @override
  Future<void> speak(String text, {String locale = 'vi-VN'}) =>
      _runPrompt(() => _delegate.speak(text, locale: locale));

  @override
  Future<void> speakAndWait(String text, {String locale = 'vi-VN'}) =>
      _runPrompt(() => _delegate.speakAndWait(text, locale: locale));

  @override
  Future<void> speakAndWaitOnPhoneSpeaker(
    String text, {
    String locale = 'vi-VN',
  }) => _runPrompt(() {
    final delegate = _delegate;
    return delegate is PhoneSpeakerVoicePromptService
        ? (delegate as PhoneSpeakerVoicePromptService)
              .speakAndWaitOnPhoneSpeaker(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  });

  @override
  Future<void> speakAndWaitOnSelectedMediaOutput(
    String text, {
    String locale = 'vi-VN',
  }) => _runPrompt(() {
    final delegate = _delegate;
    return delegate is SelectedMediaOutputVoicePromptService
        ? (delegate as SelectedMediaOutputVoicePromptService)
              .speakAndWaitOnSelectedMediaOutput(text, locale: locale)
        : delegate.speakAndWait(text, locale: locale);
  });

  @override
  Future<void> playSpeechReadyCue() => _runPrompt(() {
    final delegate = _delegate;
    return delegate is SpeechReadyCuePlayer
        ? (delegate as SpeechReadyCuePlayer).playSpeechReadyCue()
        : Future<void>.value();
  });

  Future<void> _runPrompt(Future<void> Function() action) async {
    if (_disposed) {
      return;
    }
    final cancellation = _pendingCancellation;
    final lease = await _coordinator.acquire(
      owner: _owner,
      mode: AudioTurnMode.promptPlayback,
      cancellation: cancellation,
    );
    if (_disposed || cancellation.isCancelled) {
      await lease.release();
      return;
    }
    _activeLease = lease;
    try {
      await action();
    } finally {
      if (identical(_activeLease, lease)) {
        _activeLease = null;
      }
      await lease.release();
    }
  }

  @override
  Future<String?> beginMainTurn() async {
    final delegate = _delegate;
    return delegate is MainTurnVoicePromptService
        ? (delegate as MainTurnVoicePromptService).beginMainTurn()
        : null;
  }

  @override
  Future<void> endMainTurn(String reason, {String? turnId}) async {
    final delegate = _delegate;
    if (delegate is MainTurnVoicePromptService) {
      await (delegate as MainTurnVoicePromptService).endMainTurn(
        reason,
        turnId: turnId,
      );
    }
  }

  @override
  Future<void> stop() async {
    _pendingCancellation.cancel();
    _pendingCancellation = AudioTurnCancellation();
    final lease = _activeLease;
    _activeLease = null;
    if (lease != null && lease.isCurrent) {
      await _delegate.stop();
    }
    await lease?.release();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await stop();
  }
}
