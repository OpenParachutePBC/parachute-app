import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app/features/recorder/services/omi/device_connection.dart';
import 'package:app/features/recorder/services/omi/models.dart';

/// Omi-specific device connection implementation
///
/// Handles audio streaming, button events, battery monitoring, and codec detection
/// for Omi wearable devices.
class OmiDeviceConnection extends DeviceConnection {
  BluetoothService? _batteryService;
  BluetoothService? _omiService;
  BluetoothService? _buttonService;
  BluetoothService? _deviceInfoService;

  OmiDeviceConnection({required super.device, required super.bleDevice});

  String get deviceId => device.id;

  @override
  Future<void> connect({
    Function(String deviceId, DeviceConnectionState state)?
    onConnectionStateChanged,
  }) async {
    await super.connect(onConnectionStateChanged: onConnectionStateChanged);

    // Discover required services
    _omiService = await getService(omiServiceUuid);
    if (_omiService == null) {
      debugPrint('[OmiConnection] Omi service not found');
      throw DeviceConnectionException('Omi BLE service not found');
    }

    _batteryService = await getService(batteryServiceUuid);
    if (_batteryService == null) {
      debugPrint('[OmiConnection] Battery service not found (non-critical)');
    }

    _buttonService = await getService(buttonServiceUuid);
    if (_buttonService == null) {
      debugPrint('[OmiConnection] Button service not found (non-critical)');
    }

    _deviceInfoService = await getService(deviceInformationServiceUuid);
    if (_deviceInfoService == null) {
      debugPrint(
        '[OmiConnection] Device Info service not found (non-critical)',
      );
    }

    debugPrint('[OmiConnection] Services discovered successfully');

    // Read firmware version
    final firmwareVersion = await getFirmwareVersion();
    if (firmwareVersion != null) {
      debugPrint('[OmiConnection] Firmware version: $firmwareVersion');
    }
  }

  @override
  Future<bool> isConnected() async {
    return bleDevice.isConnected;
  }

  @override
  Future<int> performRetrieveBatteryLevel() async {
    if (_batteryService == null) {
      debugPrint('[OmiConnection] Battery service not available');
      return -1;
    }

    final characteristic = getCharacteristic(
      _batteryService!,
      batteryLevelCharacteristicUuid,
    );

    if (characteristic == null) {
      debugPrint('[OmiConnection] Battery level characteristic not found');
      return -1;
    }

    try {
      final value = await characteristic.read();
      if (value.isNotEmpty) {
        final level = value[0];
        debugPrint('[OmiConnection] Battery level: $level%');
        return level;
      }
    } on PlatformException catch (e) {
      debugPrint(
        '[OmiConnection] Error reading battery: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('[OmiConnection] Error reading battery: $e');
    }

    return -1;
  }

  @override
  Future<StreamSubscription<List<int>>?> performGetBleBatteryLevelListener({
    void Function(int)? onBatteryLevelChange,
  }) async {
    if (_batteryService == null) {
      debugPrint('[OmiConnection] Battery service not available');
      return null;
    }

    final characteristic = getCharacteristic(
      _batteryService!,
      batteryLevelCharacteristicUuid,
    );

    if (characteristic == null) {
      debugPrint('[OmiConnection] Battery level characteristic not found');
      return null;
    }

    try {
      // Read current value
      final currentValue = await characteristic.read();
      if (currentValue.isNotEmpty && onBatteryLevelChange != null) {
        onBatteryLevelChange(currentValue[0]);
      }

      // Subscribe to notifications
      await characteristic.setNotifyValue(true);

      final listener = characteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty && onBatteryLevelChange != null) {
          onBatteryLevelChange(value[0]);
        }
      });

      bleDevice.cancelWhenDisconnected(listener);
      return listener;
    } on PlatformException catch (e) {
      debugPrint(
        '[OmiConnection] Error subscribing to battery: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('[OmiConnection] Error subscribing to battery: $e');
    }

    return null;
  }

  @override
  Future<StreamSubscription?> performGetBleButtonListener({
    required void Function(List<int>) onButtonReceived,
  }) async {
    debugPrint('[OmiConnection] Setting up button listener');

    if (_buttonService == null) {
      debugPrint('[OmiConnection] Button service not available');
      return null;
    }

    final characteristic = getCharacteristic(
      _buttonService!,
      buttonTriggerCharacteristicUuid,
    );

    if (characteristic == null) {
      debugPrint('[OmiConnection] Button characteristic not found');
      return null;
    }

    // Verify characteristic supports notifications
    if (!characteristic.properties.notify &&
        !characteristic.properties.indicate) {
      debugPrint(
        '[OmiConnection] Button characteristic does not support notifications',
      );
      return null;
    }

    try {
      // Ensure device is connected
      if (!bleDevice.isConnected) {
        debugPrint('[OmiConnection] Device not connected for button setup');
        return null;
      }

      // Enable notifications
      debugPrint('[OmiConnection] Enabling button notifications');
      await characteristic.setNotifyValue(true);

      // Subscribe to button events
      final listener = characteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          debugPrint(
            '[OmiConnection] 🔘 Button event received from device: $value',
          );
          onButtonReceived(value);
        }
      });

      bleDevice.cancelWhenDisconnected(listener);
      debugPrint('[OmiConnection] Button listener setup complete');
      return listener;
    } on PlatformException catch (e) {
      debugPrint(
        '[OmiConnection] Error subscribing to button: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('[OmiConnection] Error subscribing to button: $e');
    }

    return null;
  }

  @override
  Future<StreamSubscription?> performGetBleAudioBytesListener({
    required void Function(List<int>) onAudioBytesReceived,
  }) async {
    debugPrint('[OmiConnection] Setting up audio stream listener');

    if (_omiService == null) {
      debugPrint('[OmiConnection] Omi service not available');
      return null;
    }

    final characteristic = getCharacteristic(
      _omiService!,
      audioDataStreamCharacteristicUuid,
    );

    if (characteristic == null) {
      debugPrint('[OmiConnection] Audio characteristic not found');
      return null;
    }

    // Verify characteristic supports notifications
    if (!characteristic.properties.notify) {
      debugPrint(
        '[OmiConnection] Audio characteristic does not support notifications',
      );
      return null;
    }

    try {
      // Ensure device is connected
      if (!bleDevice.isConnected) {
        debugPrint('[OmiConnection] Device not connected for audio setup');
        return null;
      }

      // Request larger MTU on Android for better audio throughput
      if (Platform.isAndroid && bleDevice.mtuNow < 512) {
        try {
          await bleDevice.requestMtu(512);
          debugPrint('[OmiConnection] MTU set to 512 for audio');
        } catch (e) {
          debugPrint('[OmiConnection] MTU request failed: $e');
        }
      }

      // Enable notifications
      debugPrint('[OmiConnection] Enabling audio notifications');
      await characteristic.setNotifyValue(true);

      // Subscribe to audio stream
      final listener = characteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          onAudioBytesReceived(value);
        }
      });

      bleDevice.cancelWhenDisconnected(listener);
      debugPrint('[OmiConnection] Audio listener setup complete');
      return listener;
    } on PlatformException catch (e) {
      debugPrint(
        '[OmiConnection] Error subscribing to audio: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('[OmiConnection] Error subscribing to audio: $e');
    }

    return null;
  }

  @override
  Future<BleAudioCodec> performGetAudioCodec() async {
    debugPrint('[OmiConnection] Reading audio codec');

    if (_omiService == null) {
      debugPrint('[OmiConnection] Omi service not available');
      return BleAudioCodec.unknown;
    }

    final characteristic = getCharacteristic(
      _omiService!,
      audioCodecCharacteristicUuid,
    );

    if (characteristic == null) {
      debugPrint('[OmiConnection] Audio codec characteristic not found');
      return BleAudioCodec.unknown;
    }

    try {
      final value = await characteristic.read();
      if (value.isNotEmpty) {
        final codecId = value[0];
        final codec = _parseCodecId(codecId);
        debugPrint('[OmiConnection] Codec ID: $codecId, Codec: $codec');
        return codec;
      } else {
        debugPrint('[OmiConnection] Empty codec value');
        return BleAudioCodec.unknown;
      }
    } on PlatformException catch (e) {
      debugPrint(
        '[OmiConnection] Error reading codec: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('[OmiConnection] Error reading codec: $e');
    }

    return BleAudioCodec.unknown;
  }

  /// Read firmware version from device
  Future<String?> getFirmwareVersion() async {
    if (_deviceInfoService == null) {
      debugPrint('[OmiConnection] Device Info service not available');
      return null;
    }

    final characteristic = getCharacteristic(
      _deviceInfoService!,
      firmwareRevisionCharacteristicUuid,
    );

    if (characteristic == null) {
      debugPrint('[OmiConnection] Firmware revision characteristic not found');
      return null;
    }

    try {
      final value = await characteristic.read();
      if (value.isNotEmpty) {
        final firmwareVersion = String.fromCharCodes(value);
        debugPrint('[OmiConnection] Read firmware version: $firmwareVersion');
        return firmwareVersion;
      } else {
        debugPrint('[OmiConnection] Empty firmware version value');
        return null;
      }
    } on PlatformException catch (e) {
      debugPrint(
        '[OmiConnection] Error reading firmware version: ${e.code} - ${e.message}',
      );
    } catch (e) {
      debugPrint('[OmiConnection] Error reading firmware version: $e');
    }

    return null;
  }

  /// Parse codec ID from device to BleAudioCodec enum
  BleAudioCodec _parseCodecId(int codecId) {
    switch (codecId) {
      case 1:
        return BleAudioCodec.pcm8;
      case 10:
        return BleAudioCodec.pcm16;
      case 20:
        return BleAudioCodec.opus;
      case 11:
        return BleAudioCodec.mulaw8;
      case 12:
        return BleAudioCodec.mulaw16;
      default:
        debugPrint('[OmiConnection] Unknown codec ID: $codecId');
        return BleAudioCodec.unknown;
    }
  }
}
