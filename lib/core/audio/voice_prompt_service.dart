import 'voice_prompt_service_base.dart';
import 'voice_prompt_service_native.dart'
    if (dart.library.js_interop) 'voice_prompt_service_web.dart'
    as platform;

export 'voice_prompt_service_base.dart';

VoicePromptService createVoicePromptService() =>
    platform.createPlatformVoicePromptService();

bool isPlatformVoicePromptService(VoicePromptService service) =>
    platform.isPlatformVoicePromptService(service);
