import '../domain/homi_fallback_catalog.dart';
import 'main_speaking_command_resolver.dart';

/// What the app should do after a recognized command in continuous
/// translation. Keeping this state outside [ConversationController] prevents
/// control phrases from reaching the translation backend.
enum MainSpeakingFallbackAction {
  resumeTranslation,
  openOtherLearning,
  openMainAssistant,
}

class MainSpeakingFallbackTurn {
  const MainSpeakingFallbackTurn({required this.action, this.promptText});

  final MainSpeakingFallbackAction action;
  final String? promptText;
}

/// Applies FB-009 while automatic continuous translation is active.
///
/// The first leave/stop command is confirmed before the session is exited.
/// While confirmation is open every final transcript is consumed here, rather
/// than accidentally being translated as normal content.
class MainSpeakingFallbackFlow {
  MainSpeakingFallbackFlow({
    MainSpeakingCommandResolver commandResolver =
        const MainSpeakingCommandResolver(),
  }) : _commandResolver = commandResolver;

  final MainSpeakingCommandResolver _commandResolver;
  MainSpeakingCommand? _pendingCommand;

  bool get isAwaitingConfirmation => _pendingCommand != null;

  void reset() => _pendingCommand = null;

  bool canHandle(String recognizedText) =>
      recognizedText.trim().isNotEmpty &&
      (isAwaitingConfirmation ||
          _commandResolver.resolve(recognizedText) != null);

  MainSpeakingFallbackTurn? handle(String recognizedText) {
    final pendingCommand = _pendingCommand;
    if (pendingCommand != null) {
      return _handleConfirmation(recognizedText, pendingCommand);
    }

    final command = _commandResolver.resolve(recognizedText);
    if (command == null) {
      return null;
    }
    if (command == MainSpeakingCommand.help) {
      return MainSpeakingFallbackTurn(
        action: MainSpeakingFallbackAction.resumeTranslation,
        promptText: HomiFallbackCatalog.assistantPromptById['AI-022']!,
      );
    }

    _pendingCommand = command;
    return MainSpeakingFallbackTurn(
      action: MainSpeakingFallbackAction.resumeTranslation,
      promptText: HomiFallbackCatalog.fallbackPolicyById['FB-009']!.firstPrompt,
    );
  }

  MainSpeakingFallbackTurn _handleConfirmation(
    String recognizedText,
    MainSpeakingCommand pendingCommand,
  ) {
    final command = _commandResolver.resolve(recognizedText);
    // A new explicit stop is global. It must not inherit a pending
    // other-learning request, otherwise “học cái khác” → “dừng” would open
    // the other-learning menu instead of stopping translation.
    if (command == MainSpeakingCommand.stopTranslation) {
      _pendingCommand = null;
      return MainSpeakingFallbackTurn(
        action: _actionFor(MainSpeakingCommand.stopTranslation),
      );
    }
    if (_isAffirmativeConfirmation(recognizedText)) {
      _pendingCommand = null;
      return MainSpeakingFallbackTurn(action: _actionFor(pendingCommand));
    }
    if (_isNegativeConfirmation(recognizedText)) {
      _pendingCommand = null;
      return const MainSpeakingFallbackTurn(
        action: MainSpeakingFallbackAction.resumeTranslation,
      );
    }

    _pendingCommand = null;
    return MainSpeakingFallbackTurn(
      action: MainSpeakingFallbackAction.resumeTranslation,
      promptText:
          HomiFallbackCatalog.fallbackPolicyById['FB-009']!.secondPrompt,
    );
  }

  static MainSpeakingFallbackAction _actionFor(MainSpeakingCommand command) =>
      switch (command) {
        MainSpeakingCommand.otherLearning =>
          MainSpeakingFallbackAction.openOtherLearning,
        MainSpeakingCommand.stopTranslation =>
          MainSpeakingFallbackAction.openMainAssistant,
        MainSpeakingCommand.help =>
          MainSpeakingFallbackAction.resumeTranslation,
      };

  static bool _isAffirmativeConfirmation(String recognizedText) =>
      HomiFallbackCatalog.matchesChildPhrase('INT-019', recognizedText);

  static bool _isNegativeConfirmation(String recognizedText) =>
      HomiFallbackCatalog.matchesChildPhrase('INT-020', recognizedText);
}
