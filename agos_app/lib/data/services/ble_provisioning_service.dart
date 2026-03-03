import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart'
    as classic;
import 'package:permission_handler/permission_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLE Provisioning Service
//
// Discovers nearby BLE devices, connects to the AGOS ESP32 device, and sends
// WiFi credentials via a custom BLE characteristic (GATT write).
//
// ESP32 GATT layout expected:
//   Service UUID  : 4fafc201-1fb5-459e-8fcc-c5c9c331914b
//   Characteristic: beb5483e-36e1-4688-b7f5-ea07361b26a8  (write, notify)
//
// Payload sent as JSON: {"ssid":"<ssid>","password":"<pass>"}
// ─────────────────────────────────────────────────────────────────────────────

/// GATT service / characteristic UUIDs — must match the ESP32 firmware.
const _kServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const _kCharacteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

/// Minimum BLE scan duration per scan cycle (seconds).
const _kScanSeconds = 10;

class AgosBluetoothDevice {
  final BluetoothDevice? device;          // BLE device (null for classic-only)
  final classic.BluetoothDevice? classicDevice; // Classic device (null for BLE-only)
  final String name;
  final int rssi; // signal strength in dBm (0 if unknown)
  final bool isClassic; // true = Classic Bluetooth, false = BLE

  AgosBluetoothDevice({
    required this.name,
    required this.rssi,
    this.device,
    this.classicDevice,
    this.isClassic = false,
  });

  /// Human-readable signal label.
  String get signalLabel {
    if (isClassic) return 'Paired';
    if (rssi >= -60) return 'Strong';
    if (rssi >= -75) return 'Medium';
    return 'Weak';
  }
}

class BleProvisioningService {
  static final BleProvisioningService _instance =
      BleProvisioningService._internal();
  factory BleProvisioningService() => _instance;
  BleProvisioningService._internal();

  /// Set to true to bypass real hardware — returns fake devices and skips
  /// all Bluetooth/WiFi operations so the full setup flow can be tested
  /// without an ESP32 device.
  bool simulationMode = false;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  classic.FlutterBluetoothClassic? _classicBluetooth;

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request all permissions needed for BLE scanning on the current OS.
  Future<bool> requestPermissions() async {
    if (simulationMode) return true;
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Scan for nearby BLE devices AND return Classic Bluetooth paired devices.
  /// Returns a merged, deduplicated list sorted by type (AGOS first, then BLE, then Classic).
  Future<List<AgosBluetoothDevice>> scan() async {
    // ── Simulation Mode ──────────────────────────────────────────────────────
    if (simulationMode) {
      await Future.delayed(const Duration(seconds: 2)); // fake scan delay
      return [
        AgosBluetoothDevice(name: 'AGOS-Device-001', rssi: -55, isClassic: false),
        AgosBluetoothDevice(name: 'AGOS-Device-002', rssi: -72, isClassic: false),
        AgosBluetoothDevice(name: 'Phone Speaker',   rssi: -80, isClassic: true),
        AgosBluetoothDevice(name: 'SmartWatch',      rssi: -65, isClassic: false),
      ];
    }
    // ─────────────────────────────────────────────────────────────────────────

    final found = <String, AgosBluetoothDevice>{};

    // --- BLE scan ---
    try {
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final name = r.device.platformName.trim();
          if (name.isEmpty) continue;
          found[name] = AgosBluetoothDevice(
            device: r.device,
            name: name,
            rssi: r.rssi,
            isClassic: false,
          );
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: _kScanSeconds),
      );
      await FlutterBluePlus.isScanning.where((s) => !s).first;
      await sub.cancel();
    } catch (_) {
      // BLE scan failed — still return Classic devices below
    }

    // --- Classic Bluetooth paired devices ---
    try {
      final bt = classic.FlutterBluetoothClassic();
      final isEnabled = await bt.isBluetoothEnabled();
      if (isEnabled) {
        final pairedDevices = await bt.getPairedDevices();
        for (final d in pairedDevices) {
          final name = d.name.trim();
          if (name.isEmpty) continue;
          // Only add if not already found via BLE (prefer BLE entry)
          if (!found.containsKey(name)) {
            found[name] = AgosBluetoothDevice(
              classicDevice: d,
              name: name,
              rssi: 0,
              isClassic: true,
            );
          }
        }
      }
    } catch (_) {
      // Classic not available on this platform — ignore
    }

    final list = found.values.toList();
    // Sort: AGOS devices first, then by signal strength (BLE), then Classic last
    list.sort((a, b) {
      final aIsAgos = a.name.startsWith('AGOS');
      final bIsAgos = b.name.startsWith('AGOS');
      if (aIsAgos != bIsAgos) return aIsAgos ? -1 : 1;
      if (a.isClassic != b.isClassic) return a.isClassic ? 1 : -1;
      return b.rssi.compareTo(a.rssi); // strongest BLE first
    });
    return list;
  }

  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  // ---------------------------------------------------------------------------
  // Connection + Provisioning
  // ---------------------------------------------------------------------------

  /// Connect to [device]. Handles both BLE (GATT) and Classic Bluetooth.
  Future<void> connect(AgosBluetoothDevice device) async {
    if (simulationMode) {
      await Future.delayed(const Duration(seconds: 1)); // fake connect delay
      return;
    }
    if (device.isClassic && device.classicDevice != null) {
      // Classic Bluetooth connection
      final bt = classic.FlutterBluetoothClassic();
      final success = await bt.connect(device.classicDevice!.address);
      if (!success) {
        throw Exception('Failed to connect to ${device.name} via Classic Bluetooth.');
      }
      _classicBluetooth = bt;
      _connectedDevice = null;
    } else if (device.device != null) {
      // BLE connection
      _connectedDevice = device.device;
      await _connectedDevice!.connect(autoConnect: false);
      final services = await _connectedDevice!.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == _kServiceUuid) {
          for (final chr in svc.characteristics) {
            if (chr.uuid.toString().toLowerCase() == _kCharacteristicUuid) {
              _characteristic = chr;
              return;
            }
          }
        }
      }
      // Service not found — disconnect and throw
      await disconnect();
      throw Exception(
          'Provisioning service not found. Make sure you selected the correct AGOS device.');
    } else {
      throw Exception('Invalid device — cannot connect.');
    }
  }

  /// Send WiFi credentials (and optional device ID) to the connected ESP32.
  /// The [deviceId] is the identifier the ESP32 should use when connecting
  /// to the backend WebSocket: ws://server/ws/{deviceId}
  Future<void> sendWifiCredentials({
    required String ssid,
    required String password,
    String? deviceId,
  }) async {
    if (simulationMode) {
      await Future.delayed(const Duration(seconds: 1)); // fake send delay
      return;
    }
    if (_classicBluetooth == null && _characteristic == null) {
      throw Exception('Not connected to a device. Please go back and select your AGOS device.');
    }
    final payload = jsonEncode({
      'ssid': ssid,
      'password': password,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    });
    if (_classicBluetooth != null) {
      // Classic Bluetooth
      final success = await _classicBluetooth!.sendString(payload);
      if (!success) throw Exception('Failed to send credentials via Classic Bluetooth.');
    } else if (_characteristic != null) {
      // BLE
      await _characteristic!.write(
        utf8.encode(payload),
        withoutResponse: false,
      );
    } else {
      throw Exception('Not connected to a device.');
    }
  }

  /// Disconnect from the currently connected device.
  Future<void> disconnect() async {
    _characteristic = null;
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    if (_classicBluetooth != null) {
      await _classicBluetooth!.disconnect();
      _classicBluetooth = null;
    }
  }

  bool get isConnected => _connectedDevice != null || _classicBluetooth != null;
}
