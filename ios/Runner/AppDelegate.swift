import Flutter
import MLKitCommon
import MLKitTranslate
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var platformChannel: FlutterMethodChannel?
  private let clientIdentityStore = IOSClientIdentityStore()
  private let installationCredentialStore = IOSInstallationCredentialStore()
  private var aiv0BleControlBridge: Aiv0BleControlBridge?
  private var hfpAudioBridge: HfpAudioBridge?
  private var voicePromptBridge: VoicePromptBridge?
  private var speechRecognizerBridge: IOSSpeechRecognizerBridge?
  private var backgroundLearningBridge: BackgroundLearningBridge?
  private var offlineTranslationModelBridge: IOSOfflineTranslationModelBridge?
  private var audioSessionCoordinator: IOSAudioSessionCoordinator?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    aiv0BleControlBridge?.dispose()
    hfpAudioBridge?.dispose()
    voicePromptBridge?.dispose()
    speechRecognizerBridge?.dispose()
    backgroundLearningBridge?.dispose()
    offlineTranslationModelBridge?.dispose()
    audioSessionCoordinator?.dispose()
    let coordinator = IOSAudioSessionCoordinator()
    audioSessionCoordinator = coordinator
    aiv0BleControlBridge = Aiv0BleControlBridge(
      messenger: messenger,
      audioSessionCoordinator: coordinator
    )
    hfpAudioBridge = HfpAudioBridge(
      messenger: messenger,
      audioSessionCoordinator: coordinator
    )
    voicePromptBridge = VoicePromptBridge(
      messenger: messenger,
      audioSessionCoordinator: coordinator
    )
    speechRecognizerBridge = IOSSpeechRecognizerBridge(
      messenger: messenger,
      audioSessionCoordinator: coordinator
    )
    backgroundLearningBridge = BackgroundLearningBridge(
      messenger: messenger,
      audioSessionCoordinator: coordinator
    )
    offlineTranslationModelBridge = IOSOfflineTranslationModelBridge(
      messenger: messenger
    )

    let channel = FlutterMethodChannel(
      name: "ailingo_platform",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [clientIdentityStore, installationCredentialStore] call, result in
      switch call.method {
      case "device.clientId":
        result(clientIdentityStore.getOrCreate())
      case "device.resetClientId":
        result(clientIdentityStore.reset())
      case "auth.credentials.read":
        result(installationCredentialStore.read())
      case "auth.credentials.write":
        guard let encoded = call.arguments as? String, !encoded.isEmpty else {
          result(
            FlutterError(
              code: "invalid_credentials",
              message: "Installation credential không hợp lệ.",
              details: nil
            )
          )
          return
        }
        result(installationCredentialStore.write(encoded))
      case "auth.credentials.clear":
        result(installationCredentialStore.clear())
      case "ble.isSupported":
        result(true)
      case "device.protocolInfo":
        result([
          "architecture": "HFP_AUDIO_PLUS_BLE_CONTROL",
          "controlServiceUuid": "9E3B0001-4A7C-4D6F-8B21-5C17A2D94010",
          "buttonEventUuid": "9E3B0002-4A7C-4D6F-8B21-5C17A2D94010",
          "appStateUuid": "9E3B0003-4A7C-4D6F-8B21-5C17A2D94010",
          "batteryServiceUuid": "0000180F-0000-1000-8000-00805F9B34FB",
          "batteryLevelUuid": "00002A19-0000-1000-8000-00805F9B34FB",
          "deviceInformationServiceUuid": "0000180A-0000-1000-8000-00805F9B34FB",
          "firmwareRevisionUuid": "00002A26-0000-1000-8000-00805F9B34FB",
          "audioTransport": "HFP",
          "legacyBleAudioEnabledByDefault": false,
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    platformChannel = channel
  }
}

/// ML Kit's stock Flutter model manager currently allows cellular downloads
/// on iOS even when Dart requests Wi-Fi. HOMI owns this narrow bridge so the
/// parent's Wi-Fi-only choice is enforced by MLKit's native download condition.
private final class IOSOfflineTranslationModelBridge {
  private let channel: FlutterMethodChannel
  private let modelManager = ModelManager.modelManager()
  private var pending: [String: PendingTranslationModelDownload] = [:]
  private var vietnameseEnglishTranslator: Translator?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "homi_offline_translation_models",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
      let locale = arguments["locale"] as? String,
      let targetModel = model(for: locale)
    else {
      result(
        FlutterError(
          code: "OFFLINE_TRANSLATION_LANGUAGE_UNSUPPORTED",
          message: "Only Vietnamese and English offline translation models are supported.",
          details: nil
        )
      )
      return
    }

    switch call.method {
    case "model.status":
      result(modelManager.isModelDownloaded(targetModel))
    case "model.requestDownload":
      requestDownload(
        model: targetModel,
        locale: normalized(locale),
        wifiOnly: arguments["wifiOnly"] as? Bool ?? true,
        result: result
      )
    case "translate":
      translate(arguments: arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func translate(
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard let text = arguments["text"] as? String,
      let vietnameseModel = model(for: "vi"),
      let englishModel = model(for: "en"),
      modelManager.isModelDownloaded(vietnameseModel),
      modelManager.isModelDownloaded(englishModel)
    else {
      result(
        FlutterError(
          code: "OFFLINE_TRANSLATION_MODEL_UNAVAILABLE",
          message: "Vietnamese and English translation models are not installed.",
          details: nil
        )
      )
      return
    }
    let translator = vietnameseEnglishTranslator ?? Translator.translator(
      options: TranslatorOptions(
        sourceLanguage: TranslateLanguage(rawValue: "vi"),
        targetLanguage: TranslateLanguage(rawValue: "en")
      )
    )
    vietnameseEnglishTranslator = translator
    translator.translate(text) { translatedText, error in
      if let error = error as NSError? {
        result(
          FlutterError(
            code: "OFFLINE_TRANSLATION_FAILED",
            message: error.localizedDescription,
            details: error.domain
          )
        )
      } else {
        result(translatedText ?? "")
      }
    }
  }

  private func requestDownload(
    model: TranslateRemoteModel,
    locale: String,
    wifiOnly: Bool,
    result: @escaping FlutterResult
  ) {
    if modelManager.isModelDownloaded(model) {
      result(true)
      return
    }
    if pending[locale] != nil {
      result(
        FlutterError(
          code: "OFFLINE_TRANSLATION_DOWNLOAD_IN_PROGRESS",
          message: "The language model is already downloading.",
          details: locale
        )
      )
      return
    }

    let successToken = NotificationCenter.default.addObserver(
      forName: Notification.Name.mlkitModelDownloadDidSucceed,
      object: model,
      queue: .main
    ) { [weak self] _ in
      self?.complete(locale: locale, succeeded: true)
    }
    let failureToken = NotificationCenter.default.addObserver(
      forName: Notification.Name.mlkitModelDownloadDidFail,
      object: model,
      queue: .main
    ) { [weak self] _ in
      self?.complete(locale: locale, succeeded: false)
    }
    pending[locale] = PendingTranslationModelDownload(
      successToken: successToken,
      failureToken: failureToken,
      result: result
    )
    let conditions = ModelDownloadConditions(
      allowsCellularAccess: !wifiOnly,
      allowsBackgroundDownloading: true
    )
    modelManager.download(model, conditions: conditions)
  }

  private func complete(locale: String, succeeded: Bool) {
    guard let download = pending.removeValue(forKey: locale) else { return }
    NotificationCenter.default.removeObserver(download.successToken)
    NotificationCenter.default.removeObserver(download.failureToken)
    if succeeded {
      download.result(true)
    } else {
      download.result(
        FlutterError(
          code: "OFFLINE_TRANSLATION_DOWNLOAD_FAILED",
          message: "The offline translation model could not be downloaded.",
          details: locale
        )
      )
    }
  }

  private func model(for locale: String) -> TranslateRemoteModel? {
    let code = normalized(locale)
    guard code == "vi" || code == "en" else { return nil }
    return TranslateRemoteModel.translateRemoteModel(
      language: TranslateLanguage(rawValue: code)
    )
  }

  private func normalized(_ locale: String) -> String {
    locale.replacingOccurrences(of: "_", with: "-")
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init) ?? ""
  }

  func dispose() {
    channel.setMethodCallHandler(nil)
    vietnameseEnglishTranslator = nil
    let active = pending
    pending.removeAll()
    for (locale, download) in active {
      NotificationCenter.default.removeObserver(download.successToken)
      NotificationCenter.default.removeObserver(download.failureToken)
      download.result(
        FlutterError(
          code: "OFFLINE_TRANSLATION_DOWNLOAD_CANCELLED",
          message: "The Flutter engine was restarted during model download.",
          details: locale
        )
      )
    }
  }
}

private final class PendingTranslationModelDownload {
  let successToken: NSObjectProtocol
  let failureToken: NSObjectProtocol
  let result: FlutterResult

  init(
    successToken: NSObjectProtocol,
    failureToken: NSObjectProtocol,
    result: @escaping FlutterResult
  ) {
    self.successToken = successToken
    self.failureToken = failureToken
    self.result = result
  }
}

private final class IOSInstallationCredentialStore {
  private let account = "installation.credentials.v1"

  func read() -> String? {
    let query = key.merging([
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]) { _, new in new }
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  func write(_ value: String) -> Bool {
    SecItemDelete(key as CFDictionary)
    var item = key
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
  }

  func clear() -> Bool {
    let status = SecItemDelete(key as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private var key: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String:
        "\(Bundle.main.bundleIdentifier ?? "com.innotrik.aispeaking").installation-auth",
      kSecAttrAccount as String: account,
    ]
  }
}

private final class IOSClientIdentityStore {
  private let account = "device.clientId"

  func getOrCreate() -> String {
    if let stored = read(), !stored.isEmpty {
      return stored
    }

    let clientId = "ios_\(UUID().uuidString.lowercased())"
    store(clientId)
    return clientId
  }

  func reset() -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }

  private var service: String {
    "\(Bundle.main.bundleIdentifier ?? "com.innotrik.aispeaking").client-identity"
  }

  private func read() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private func store(_ value: String) {
    let key: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(key as CFDictionary)

    var item = key
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }
}
