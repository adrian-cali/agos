import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';
import '../../../data/services/ble_provisioning_service.dart';
import '../../widgets/bottom_nav_bar.dart';

enum _Stage { idle, scanning, connected, sending, done, error }

class ChangeWifiScreen extends StatefulWidget {
  const ChangeWifiScreen({super.key});

  @override
  State<ChangeWifiScreen> createState() => _ChangeWifiScreenState();
}

class _ChangeWifiScreenState extends State<ChangeWifiScreen> {
  final _passCtrl = TextEditingController();
  final _svc = BleProvisioningService();

  _Stage _stage = _Stage.idle;
  String _statusText = '';
  String _connectedDeviceName = '';
  bool _passVisible = false;

  // WiFi scan
  List<Map<String, dynamic>> _networks = [];
  bool _wifiScanning = false;
  String? _wifiScanError;
  String? _selectedSsid;
  bool _isPasswordStep = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _svc.disconnect();
    super.dispose();
  }

  // ── BLE connect ────────────────────────────────────────────────────────────

  Future<void> _connectBluetooth() async {
    setState(() {
      _stage = _Stage.scanning;
      _statusText = 'Scanning for AGOS device…';
    });
    try {
      final devices = await _svc.scan();
      final agos = devices.firstWhere(
        (d) => d.name.startsWith('AGOS'),
        orElse: () => throw Exception(
            'No AGOS device found nearby.\nMake sure the ESP32 is powered on and within range.'),
      );
      setState(() => _statusText = 'Connecting to ${agos.name}…');
      await _svc.connect(agos);
      setState(() {
        _stage = _Stage.connected;
        _connectedDeviceName = agos.name;
      });
      _scanWifi();
    } catch (e) {
      await _svc.disconnect();
      setState(() {
        _stage = _Stage.error;
        _statusText = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ── WiFi scan ───────────────────────────────────────────────────────────────

  Future<void> _scanWifi() async {
    setState(() {
      _wifiScanning = true;
      _wifiScanError = null;
    });

    if (_svc.simulationMode) {
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _networks = [
          {'name': 'HomeNetwork_5G', 'signal': 4, 'secured': true,  'level': -45},
          {'name': 'MyWifi2.4',      'signal': 3, 'secured': true,  'level': -60},
          {'name': 'GuestNetwork',   'signal': 2, 'secured': false, 'level': -75},
        ];
        _wifiScanning = false;
      });
      return;
    }

    try {
      final canScan =
          await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canScan != CanStartScan.yes) {
        setState(() {
          _wifiScanError = 'Cannot scan WiFi: ${canScan.name}. Check location permissions.';
          _wifiScanning = false;
        });
        return;
      }
      await WiFiScan.instance.startScan();
      final can = await WiFiScan.instance
          .canGetScannedResults(askPermissions: true);
      if (can != CanGetScannedResults.yes) {
        setState(() {
          _wifiScanError = 'Cannot read WiFi results: ${can.name}.';
          _wifiScanning = false;
        });
        return;
      }
      final results = await WiFiScan.instance.getScannedResults();
      final seen = <String>{};
      final networks = <Map<String, dynamic>>[];
      for (final ap in results) {
        final ssid = ap.ssid.trim();
        if (ssid.isEmpty) continue;
        if (seen.contains(ssid)) continue;
        seen.add(ssid);
        final secured = ap.capabilities.contains('WPA') ||
            ap.capabilities.contains('WEP');
        final level = ap.level;
        final bars = level >= -55
            ? 4
            : level >= -65
                ? 3
                : level >= -75
                    ? 2
                    : 1;
        networks.add({'name': ssid, 'signal': bars, 'secured': secured, 'level': level});
      }
      networks.sort((a, b) =>
          (b['level'] as int).compareTo(a['level'] as int));
      setState(() {
        _networks = networks;
        _wifiScanning = false;
        if (networks.isEmpty) {
          _wifiScanError = 'No WiFi networks found. Make sure WiFi is enabled.';
        }
      });
    } catch (e) {
      setState(() {
        _wifiScanError = 'WiFi scan failed: $e';
        _wifiScanning = false;
      });
    }
  }

  // ── Send credentials ────────────────────────────────────────────────────────

  Future<void> _sendCredentials() async {
    if (_selectedSsid == null) return;
    setState(() {
      _stage = _Stage.sending;
      _statusText = 'Sending new Wi-Fi credentials to device…';
    });
    try {
      await _svc.sendWifiCredentials(
          ssid: _selectedSsid!, password: _passCtrl.text);
      await _svc.disconnect();
      setState(() => _stage = _Stage.done);
    } catch (e) {
      await _svc.disconnect();
      setState(() {
        _stage = _Stage.error;
        _statusText = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: switch (_stage) {
                  _Stage.idle => _buildIdle(),
                  _Stage.scanning => _buildLoading(),
                  _Stage.connected => _buildConnectedForm(),
                  _Stage.sending => _buildLoading(),
                  _Stage.done => _buildDone(),
                  _Stage.error => _buildError(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFFF4F8FB),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: Color(0xFF141A1E),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Change Wi-Fi Network',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF141A1E),
            ),
          ),
        ],
      ),
    );
  }

  // ── Idle ───────────────────────────────────────────────────────────────────

  Widget _buildIdle() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D3F2).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.info_outline,
                          color: Color(0xFF00D3F2), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'How it works',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF141A1E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStep('1', 'Power on the ESP32 device'),
                _buildStep('2',
                    'Tap "Connect to Device" — your phone will find the ESP32 via Bluetooth'),
                _buildStep('3',
                    'Select your Wi-Fi network from the list and enter the password'),
                _buildStep('4',
                    'Tap "Update Wi-Fi" and the device will switch to the new network'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD54F)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bluetooth, color: Color(0xFFF9A825), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Make sure Bluetooth is enabled on your phone and the ESP32 is powered on.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: Color(0xFF5D4037),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _connectBluetooth,
            icon: const Icon(Icons.bluetooth_searching),
            label: const Text(
              'Connect to Device',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D3F2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      );

  Widget _buildStep(String number, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF00D3F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  number,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Color(0xFF4A6572),
                ),
              ),
            ),
          ],
        ),
      );

  // ── Loading ────────────────────────────────────────────────────────────────

  Widget _buildLoading() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              const CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF00D3F2))),
              const SizedBox(height: 24),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Color(0xFF4A6572),
                ),
              ),
            ],
          ),
        ),
      );

  // ── Connected — Network list + password ────────────────────────────────────

  Widget _buildConnectedForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Connected chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8FDF5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF34C785)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected,
                    color: Color(0xFF34C785), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Connected to $_connectedDeviceName',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A6B47),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (!_isPasswordStep) _buildNetworksList() else _buildPasswordStep(),
        ],
      );

  Widget _buildNetworksList() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Select a Wi-Fi Network',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF141A1E),
                  ),
                ),
              ),
              IconButton(
                icon: _wifiScanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh',
                onPressed: _wifiScanning ? null : _scanWifi,
              ),
            ],
          ),
          if (_wifiScanError != null) ...[  
            const SizedBox(height: 4),
            Text(_wifiScanError!,
                style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontFamily: 'Poppins')),
          ],
          const SizedBox(height: 8),
          if (_wifiScanning && _networks.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF00D3F2))),
            ))
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _networks.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (context, index) {
                  final net = _networks[index];
                  final ssid = net['name'] as String;
                  final secured = net['secured'] as bool;
                  final signal = net['signal'] as int;
                  return ListTile(
                    leading: Icon(
                      _signalIcon(signal),
                      color: const Color(0xFF00D3F2),
                    ),
                    title: Text(
                      ssid,
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF141A1E)),
                    ),
                    trailing: secured
                        ? const Icon(Icons.lock_outline,
                            size: 16, color: Color(0xFF90A5B4))
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedSsid = ssid;
                        _passCtrl.clear();
                        _isPasswordStep = true;
                      });
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'The ESP32 only supports 2.4 GHz networks.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Color(0xFF90A5B4),
            ),
          ),
        ],
      );

  Widget _buildPasswordStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back to list
          GestureDetector(
            onTap: () => setState(() {
              _isPasswordStep = false;
              _selectedSsid = null;
            }),
            child: const Row(
              children: [
                Icon(Icons.arrow_back_ios,
                    size: 14, color: Color(0xFF00D3F2)),
                SizedBox(width: 4),
                Text(
                  'Back to network list',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF00D3F2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedSsid ?? '',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF141A1E),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enter the Wi-Fi password',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF90A5B4),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  obscureText: !_passVisible,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _sendCredentials(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Leave blank for open networks',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_passVisible
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _passVisible = !_passVisible),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _sendCredentials,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D3F2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Update Wi-Fi',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );

  IconData _signalIcon(int bars) {
    if (bars >= 4) return Icons.signal_wifi_4_bar;
    if (bars == 3) return Icons.network_wifi_3_bar;
    if (bars == 2) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  // ── Done ──────────────────────────────────────────────────────────────────

  Widget _buildDone() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8FDF5),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: Color(0xFF34C785), size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'Wi-Fi Updated!',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF141A1E),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'The ESP32 will reconnect to the new\nnetwork in a few seconds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Color(0xFF90A5B4),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D3F2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48, vertical: 14),
                ),
                child: const Text('Back to Settings',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEEEE),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(Icons.error_outline,
                    color: Color(0xFFE74C3C), size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'Connection Failed',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF141A1E),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: Color(0xFF90A5B4),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontFamily: 'Poppins')),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => setState(() => _stage = _Stage.idle),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D3F2),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Try Again',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}


