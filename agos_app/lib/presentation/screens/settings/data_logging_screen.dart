import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../data/services/firestore_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';

class DataLoggingScreen extends ConsumerStatefulWidget {
  const DataLoggingScreen({super.key});

  @override
  ConsumerState<DataLoggingScreen> createState() => _DataLoggingScreenState();
}

class _DataLoggingScreenState extends ConsumerState<DataLoggingScreen> {
  int _retentionDays = 30; // 7, 30, or 90

  // Don't show loading state — show defaults immediately, update silently
  bool _loadingPrefs = false;
  bool _exportingCsv = false;
  bool _exportingJson = false;
  bool _exportingPdf = false;
  bool _savingPrefs = false;

  String get _deviceId =>
      ref.read(linkedDeviceIdProvider).valueOrNull ?? 'agos-zksl9QK3';

  @override
  void initState() {
    super.initState();
    // Defer prefs load to first frame so providers are fully initialized
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrefs());
  }

  Future<void> _loadPrefs() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) setState(() => _loadingPrefs = false);
      return;
    }
    try {
      final service = ref.read(firestoreServiceProvider);
      final prefs = await service
          .loadDataLoggingPrefs(user.uid)
          .timeout(const Duration(seconds: 5));
      if (mounted) {
        setState(() {
          _retentionDays = prefs['retentionDays'] as int? ?? 30;
          _loadingPrefs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPrefs = false);
    }
  }

  Future<List<SensorReading>> _fetchReadings() async {
    final service = ref.read(firestoreServiceProvider);
    // Cap at 7 days to stay within Firestore free-tier read limits.
    // Upgrade to Blaze plan or reduce retention to export more.
    const int maxExportDays = 7;
    final exportDays = _retentionDays.clamp(1, maxExportDays);
    return service.fetchReadings(_deviceId, days: exportDays);
  }

  Future<void> _exportCsv() async {
    setState(() => _exportingCsv = true);
    try {
      final readings = await _fetchReadings();
      if (readings.isEmpty) {
        _snack('No data to export.');
        return;
      }
      final buf = StringBuffer();
      buf.writeln(
          'timestamp,device_id,turbidity_ntu,ph,tds_ppm,level_pct,volume_liters,flow_rate,pump_active');
      for (final r in readings) {
        buf.writeln(
            '${r.timestamp.toIso8601String()},${r.deviceId},${r.turbidity},${r.ph},${r.tds},${r.level},${r.volume},${r.flowRate},${r.pumpActive}');
      }
      final csvBytes = Uint8List.fromList(utf8.encode(buf.toString()));
      await Share.shareXFiles(
        [XFile.fromData(csvBytes, name: 'agos_export.csv', mimeType: 'text/csv')],
        subject: 'AGOS Sensor Data Export',
      );
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _exportJson() async {
    setState(() => _exportingJson = true);
    try {
      final readings = await _fetchReadings();
      if (readings.isEmpty) {
        _snack('No data to export.');
        return;
      }
      final list = readings
          .map((r) => {
                'timestamp': r.timestamp.toIso8601String(),
                'device_id': r.deviceId,
                'turbidity': r.turbidity,
                'ph': r.ph,
                'tds': r.tds,
                'level_pct': r.level,
                'volume_liters': r.volume,
                'flow_rate': r.flowRate,
                'pump_active': r.pumpActive,
              })
          .toList();
      final json = const JsonEncoder.withIndent('  ').convert(list);
      final jsonBytes = Uint8List.fromList(utf8.encode(json));
      await Share.shareXFiles(
        [XFile.fromData(jsonBytes, name: 'agos_export.json', mimeType: 'application/json')],
        subject: 'AGOS Sensor Data Export (JSON)',
      );
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exportingJson = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final readings = await _fetchReadings();
      final doc = pw.Document();
      final now = DateTime.now();

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Header(level: 0, child: pw.Text('AGOS Water Quality Report')),
          pw.Paragraph(
              text:
                  'Generated: ${now.year}-${_pad(now.month)}-${_pad(now.day)} ${_pad(now.hour)}:${_pad(now.minute)}'),
          pw.Paragraph(text: 'Device: $_deviceId'),
          pw.Paragraph(
              text: 'Period: last $_retentionDays days | Readings: ${readings.length}'),
          pw.SizedBox(height: 12),
          if (readings.isEmpty)
            pw.Paragraph(text: 'No data found for this period.')
          else ...[
            _summaryTable(readings),
            pw.SizedBox(height: 12),
            pw.Text('Latest 50 Readings',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            _dataTable(readings.reversed.take(50).toList().reversed.toList()),
          ],
        ],
      ));

      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'agos_report.pdf');
    } catch (e) {
      _snack('PDF generation failed: $e');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  pw.Widget _summaryTable(List<SensorReading> readings) {
    double avgTurb = readings.map((r) => r.turbidity).reduce((a, b) => a + b) /
        readings.length;
    double avgPh =
        readings.map((r) => r.ph).reduce((a, b) => a + b) / readings.length;
    double avgTds =
        readings.map((r) => r.tds).reduce((a, b) => a + b) / readings.length;
    return pw.Table.fromTextArray(
      headers: ['Metric', 'Average', 'Min', 'Max'],
      data: [
        [
          'Turbidity (NTU)',
          avgTurb.toStringAsFixed(2),
          readings
              .map((r) => r.turbidity)
              .reduce((a, b) => a < b ? a : b)
              .toStringAsFixed(2),
          readings
              .map((r) => r.turbidity)
              .reduce((a, b) => a > b ? a : b)
              .toStringAsFixed(2),
        ],
        [
          'pH',
          avgPh.toStringAsFixed(2),
          readings
              .map((r) => r.ph)
              .reduce((a, b) => a < b ? a : b)
              .toStringAsFixed(2),
          readings
              .map((r) => r.ph)
              .reduce((a, b) => a > b ? a : b)
              .toStringAsFixed(2),
        ],
        [
          'TDS (ppm)',
          avgTds.toStringAsFixed(1),
          readings
              .map((r) => r.tds)
              .reduce((a, b) => a < b ? a : b)
              .toStringAsFixed(1),
          readings
              .map((r) => r.tds)
              .reduce((a, b) => a > b ? a : b)
              .toStringAsFixed(1),
        ],
      ],
    );
  }

  pw.Widget _dataTable(List<SensorReading> readings) {
    return pw.Table.fromTextArray(
      headers: ['Time', 'Turb', 'pH', 'TDS', 'Level%', 'Vol(L)'],
      data: readings
          .map((r) => [
                '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}',
                r.turbidity.toStringAsFixed(1),
                r.ph.toStringAsFixed(2),
                r.tds.toStringAsFixed(0),
                r.level.toStringAsFixed(1),
                r.volume.toStringAsFixed(1),
              ])
          .toList(),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    );
  }

  Future<void> _savePrefs() async {
    setState(() => _savingPrefs = true);
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;
      final service = ref.read(firestoreServiceProvider);
      await service.saveDataLoggingPrefs(user.uid, {
        'retentionDays': _retentionDays,
      });
      if (mounted) _snack('Preferences saved.');
    } catch (e) {
      if (mounted) _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: 8),
              FadeSlideIn(
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    _buildSectionHeader('LOGGING SETTINGS'),
                    const SizedBox(height: 8),
                    _buildRetentionCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('EXPORT DATA'),
                    const SizedBox(height: 8),
                    // Free-tier quota note
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFBAE6FD), width: 1),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Color(0xFF0369A1)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Exports are limited to the last 7 days to stay within free-tier read limits.',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildExportCard(
                      iconGradient: const [
                        Color(0xFF00D492),
                        Color(0xFF009689)
                      ],
                      iconData: Icons.table_chart_outlined,
                      title: 'Export as CSV',
                      subtitle: 'Spreadsheet format for analysis',
                      onTap: _exportCsv,
                      isLoading: _exportingCsv,
                    ),
                    const SizedBox(height: 5),
                    _buildExportCard(
                      iconGradient: const [
                        Color(0xFF51A2FF),
                        Color(0xFF4F39F6)
                      ],
                      iconData: Icons.data_object_outlined,
                      title: 'Export as JSON',
                      subtitle: 'Raw data format',
                      onTap: _exportJson,
                      isLoading: _exportingJson,
                    ),
                    const SizedBox(height: 5),
                    _buildExportCard(
                      iconGradient: const [
                        Color(0xFFC27AFF),
                        Color(0xFFE60076)
                      ],
                      iconData: Icons.picture_as_pdf_outlined,
                      title: 'Generate Report',
                      subtitle: 'PDF with charts and statistics',
                      onTap: _exportPdf,
                      isLoading: _exportingPdf,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionHeader('DATA MANAGEMENT'),
                    const SizedBox(height: 16),
                    // Warning notice
                    Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFFEE685), width: 1.18),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_outlined,
                              size: 20, color: Color(0xFF7B3306)),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Clear Historical Data',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    color: Color(0xFF7B3306),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Permanently delete all stored sensor data. This action cannot be undone.',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 12,
                                    color: Color(0xFFBB4D00),
                                    height: 1.33,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _showClearDataDialog(context),
                      child: Container(
                        width: double.infinity,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFFFFC9C9), width: 1.18),
                        ),
                        child: const Center(
                          child: Text(
                            'Clear All Data',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: Color(0xFFE7000B),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 2),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_ios,
                  size: 20, color: Color(0xFF141A1E)),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'Data Logging',
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFF1447E6), Color(0xFF0092B8)],
        ).createShader(bounds),
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData iconData,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(iconData, size: 20, color: const Color(0xFF314158)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: Color(0xFF314158),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF62748E),
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildToggle({
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: Container(
        width: 32,
        height: 18,
        decoration: BoxDecoration(
          color:
              value ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment:
              value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 14,
            height: 14,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRetentionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history, size: 20, color: Color(0xFF314158)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Retention Period',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        color: Color(0xFF314158),
                      ),
                    ),
                    Text(
                      'How long to keep historical data',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        color: Color(0xFF62748E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Day selector
          Row(
            children: [7, 30, 90].map((days) {
              final isActive = _retentionDays == days;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _retentionDays = days);
                      _savePrefs();
                    },
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: isActive
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF00B8DB),
                                  Color(0xFF155DFC)
                                ],
                              )
                            : null,
                        color: isActive ? null : const Color(0xFFF1F5F9),
                      ),
                      child: Center(
                        child: Text(
                          '$days days',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: isActive
                                ? Colors.white
                                : const Color(0xFF45556C),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExportCard({
    required List<Color> iconGradient,
    required IconData iconData,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5DADE2).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                  colors: iconGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: Icon(iconData, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    color: Color(0xFF314158),
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    color: Color(0xFF62748E),
                  ),
                ),
              ],
            ),
          ),
          isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFF62748E)),
        ],
      ),
    ),
    );
  }

  void _showClearDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Data',
            style: TextStyle(color: Color(0xFF141A1E))),
        content: const Text(
            'Permanently delete all stored sensor readings for this device. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF141A1E))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllData();
            },
            child: const Text('Clear',
                style: TextStyle(color: Color(0xFFE7000B))),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
    setState(() => _savingPrefs = true);
    try {
      final service = ref.read(firestoreServiceProvider);
      await service.deleteAllReadings(_deviceId);
      if (mounted) _snack('All sensor data cleared.');
    } catch (e) {
      if (mounted) _snack('Failed to clear data: $e');
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }
}
