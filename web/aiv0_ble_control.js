(function () {
  'use strict';

  const CONTROL_SERVICE = '9e3b0001-4a7c-4d6f-8b21-5c17a2d94010';
  const BUTTON_EVENT = '9e3b0002-4a7c-4d6f-8b21-5c17a2d94010';
  const APP_STATE = '9e3b0003-4a7c-4d6f-8b21-5c17a2d94010';
  const BATTERY_SERVICE = 'battery_service';
  const BATTERY_LEVEL = 'battery_level';
  const DEVICE_INFORMATION = 'device_information';
  const FIRMWARE_REVISION = 'firmware_revision_string';
  const DUPLICATE_WINDOW_MS = 750;

  const devices = new Map();
  const state = {
    callback: null,
    device: null,
    server: null,
    buttonCharacteristic: null,
    appStateCharacteristic: null,
    buttonListener: null,
    disconnectListener: null,
    batteryPercent: null,
    firmwareRevision: null,
    packetCount: 0,
    invalidPacketCount: 0,
    duplicatePacketCount: 0,
    reconnectCount: 0,
    lastRawHex: null,
    lastButton: null,
    lastGesture: null,
    lastPacketKey: null,
    lastPacketAt: 0,
    manualDisconnect: false,
  };

  function supported() {
    return Boolean(window.isSecureContext && navigator.bluetooth);
  }

  function unsupportedReason() {
    if (!window.isSecureContext) {
      return 'Web Bluetooth yêu cầu HTTPS. Hãy mở bản Web bằng địa chỉ HTTPS.';
    }
    return 'Trình duyệt này không hỗ trợ Web Bluetooth. Safari/iPhone không thể quét BLE; hãy dùng Chrome hoặc Edge trên Android/máy tính, hoặc dùng APK Android.';
  }

  function snapshot(phase, message) {
    return {
      type: 'status',
      phase: phase,
      deviceId: state.device ? state.device.id : null,
      deviceName: state.device ? (state.device.name || 'H20') : null,
      message: message || null,
      writeMode: state.appStateCharacteristic ? 'withResponse' : null,
      batteryPercent: state.batteryPercent,
      firmwareRevision: state.firmwareRevision,
      lastRawHex: state.lastRawHex,
      lastButton: state.lastButton,
      lastGesture: state.lastGesture,
      packetCount: state.packetCount,
      invalidPacketCount: state.invalidPacketCount,
      duplicatePacketCount: state.duplicatePacketCount,
      reconnectCount: state.reconnectCount,
    };
  }

  function emit(value) {
    if (typeof state.callback === 'function') state.callback(value);
  }

  function friendlyError(error) {
    if (error && error.name === 'NotFoundError') {
      return new Error('Bạn chưa chọn thiết bị BLE hoặc đã đóng bộ chọn Bluetooth.');
    }
    if (error && error.name === 'SecurityError') {
      return new Error('Trình duyệt đã chặn Bluetooth. Hãy dùng HTTPS và cho phép quyền Bluetooth.');
    }
    if (error && error.name === 'NetworkError') {
      return new Error('Không thể kết nối H20. Hãy bật thiết bị, đặt gần máy và thử lại.');
    }
    if (error instanceof Error) return error;
    return new Error(String(error || 'Web Bluetooth gặp lỗi không xác định.'));
  }

  function clearCharacteristicListener() {
    if (state.buttonCharacteristic && state.buttonListener) {
      state.buttonCharacteristic.removeEventListener(
        'characteristicvaluechanged',
        state.buttonListener,
      );
    }
    state.buttonCharacteristic = null;
    state.buttonListener = null;
    state.appStateCharacteristic = null;
  }

  function clearDisconnectListener() {
    if (state.device && state.disconnectListener) {
      state.device.removeEventListener(
        'gattserverdisconnected',
        state.disconnectListener,
      );
    }
    state.disconnectListener = null;
  }

  async function readBattery(server) {
    try {
      const service = await server.getPrimaryService(BATTERY_SERVICE);
      const characteristic = await service.getCharacteristic(BATTERY_LEVEL);
      const value = await characteristic.readValue();
      return value.byteLength > 0 ? value.getUint8(0) : null;
    } catch (_) {
      return null;
    }
  }

  async function readFirmware(server) {
    try {
      const service = await server.getPrimaryService(DEVICE_INFORMATION);
      const characteristic = await service.getCharacteristic(FIRMWARE_REVISION);
      const value = await characteristic.readValue();
      const bytes = new Uint8Array(
        value.buffer,
        value.byteOffset,
        value.byteLength,
      );
      return new TextDecoder('utf-8').decode(bytes).replace(/\0+$/g, '').trim() || null;
    } catch (_) {
      return null;
    }
  }

  function rawHex(bytes) {
    return bytes
      .map(function (byte) { return byte.toString(16).padStart(2, '0').toUpperCase(); })
      .join(' ');
  }

  function gestureName(value) {
    if (value === 0x01) return 'shortPress';
    if (value === 0x02) return 'longPress';
    if (value === 0x03) return 'release';
    return 'unknown';
  }

  function handleButtonNotification(event) {
    const value = event.target && event.target.value;
    if (!value) return;
    const bytes = Array.from(
      new Uint8Array(value.buffer, value.byteOffset, value.byteLength),
    );
    const now = Date.now();
    const key = bytes.join(',');
    const duplicate = key === state.lastPacketKey &&
      (now - state.lastPacketAt) <= DUPLICATE_WINDOW_MS;

    state.packetCount += 1;
    if (bytes.length !== 12 || bytes[0] !== 0x01) {
      state.invalidPacketCount += 1;
    }
    if (duplicate) state.duplicatePacketCount += 1;
    state.lastPacketKey = key;
    state.lastPacketAt = now;
    state.lastRawHex = rawHex(bytes);
    state.lastButton = bytes.length >= 2 && bytes[1] === 0x01 ? 'main' : 'unknown';
    state.lastGesture = bytes.length >= 4 ? gestureName(bytes[3]) : 'unknown';

    emit({
      type: 'button',
      deviceId: state.device ? state.device.id : null,
      receivedAtEpochMs: now,
      bytes: bytes,
      duplicate: duplicate,
    });
    emit(snapshot('connected', 'BLE Web đã nhận MAIN Raw Hex từ H20.'));
  }

  function resetConnectionState() {
    clearCharacteristicListener();
    state.server = null;
    state.batteryPercent = null;
    state.firmwareRevision = null;
    state.lastPacketKey = null;
    state.lastPacketAt = 0;
  }

  window.innotrikAiv0BleSupported = supported;
  window.innotrikAiv0BleUnsupportedReason = unsupportedReason;

  window.innotrikAiv0BleSetEventHandler = function (callback) {
    state.callback = typeof callback === 'function' ? callback : null;
  };

  window.innotrikAiv0BleScan = async function () {
    if (!supported()) throw new Error(unsupportedReason());
    try {
      // A name-only or service-only filter can hide early H20 firmware that
      // does not advertise 9E3B0001. The browser chooser remains the security
      // boundary; optionalServices grants access after the user selects H20.
      const device = await navigator.bluetooth.requestDevice({
        acceptAllDevices: true,
        optionalServices: [
          CONTROL_SERVICE,
          BATTERY_SERVICE,
          DEVICE_INFORMATION,
        ],
      });
      devices.set(device.id, device);
      return { id: device.id, name: device.name || 'H20', rssi: 0 };
    } catch (error) {
      throw friendlyError(error);
    }
  };

  window.innotrikAiv0BleConnect = async function (deviceId) {
    if (!supported()) throw new Error(unsupportedReason());
    const device = devices.get(String(deviceId));
    if (!device) {
      throw new Error('Hãy bấm Quét & kết nối và chọn H20 trước.');
    }
    try {
      clearCharacteristicListener();
      clearDisconnectListener();
      state.device = device;
      state.manualDisconnect = false;

      const server = await device.gatt.connect();
      const service = await server.getPrimaryService(CONTROL_SERVICE);
      const button = await service.getCharacteristic(BUTTON_EVENT);
      await button.startNotifications();

      state.server = server;
      state.buttonCharacteristic = button;
      state.buttonListener = handleButtonNotification;
      button.addEventListener('characteristicvaluechanged', state.buttonListener);

      try {
        state.appStateCharacteristic = await service.getCharacteristic(APP_STATE);
      } catch (_) {
        state.appStateCharacteristic = null;
      }

      state.disconnectListener = function () {
        const wasManual = state.manualDisconnect;
        resetConnectionState();
        emit(snapshot(
          'idle',
          wasManual
            ? 'Đã ngắt BLE Control AIV0.'
            : 'H20 đã mất kết nối BLE. Bấm Quét & kết nối để kết nối lại.',
        ));
      };
      device.addEventListener('gattserverdisconnected', state.disconnectListener);

      const details = await Promise.all([
        readBattery(server),
        readFirmware(server),
      ]);
      state.batteryPercent = details[0];
      state.firmwareRevision = details[1];
      return snapshot(
        'connected',
        state.appStateCharacteristic
          ? 'BLE Web đã kết nối; MAIN Raw Hex đã sẵn sàng.'
          : 'BLE Web đã kết nối MAIN; H20 chưa cung cấp APP State 9E3B0003.',
      );
    } catch (error) {
      resetConnectionState();
      throw friendlyError(error);
    }
  };

  window.innotrikAiv0BleDisconnect = async function () {
    state.manualDisconnect = true;
    if (state.device && state.device.gatt && state.device.gatt.connected) {
      state.device.gatt.disconnect();
    } else {
      resetConnectionState();
    }
    return snapshot('idle', 'Đã ngắt BLE Control AIV0.');
  };

  window.innotrikAiv0BleSendAppState = async function (bytes) {
    if (!state.appStateCharacteristic || !state.server || !state.server.connected) {
      throw new Error('Chưa kết nối APP State 9E3B0003.');
    }
    const value = new Uint8Array(Array.from(bytes || []));
    if (typeof state.appStateCharacteristic.writeValueWithResponse === 'function') {
      await state.appStateCharacteristic.writeValueWithResponse(value);
    } else {
      await state.appStateCharacteristic.writeValue(value);
    }
    return snapshot('connected', 'Đã gửi trạng thái ứng dụng tới H20.');
  };
})();
