import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var platformChannel: FlutterMethodChannel?
  private let clientIdentityStore = IOSClientIdentityStore()
  private var aiv0BleControlBridge: Aiv0BleControlBridge?
  private var hfpAudioBridge: HfpAudioBridge?
  private var voicePromptBridge: VoicePromptBridge?
  private var speechRecognizerBridge: IOSSpeechRecognizerBridge?
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

    let channel = FlutterMethodChannel(
      name: "ailingo_platform",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [clientIdentityStore] call, result in
      switch call.method {
      case "device.clientId":
        result(clientIdentityStore.getOrCreate())
      case "device.resetClientId":
        result(clientIdentityStore.reset())
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
