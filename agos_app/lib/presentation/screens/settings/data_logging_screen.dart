import 'package:flutter/material.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/fade_slide_in.dart';

class DataLoggingScreen extends StatefulWidget {
  const DataLoggingScreen({super.key});

  @override
  State<DataLoggingScreen> createState() => _DataLoggingScreenState();
}

class _DataLoggingScreenState extends State<DataLoggingScreen> {
  bool _automaticLogging = true;
  bool _cloudSync = false;
  int _retentionDays = 30; // 7, 30, or 90

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
                    _buildSectionHeader('LOGGING SETTING'),
                    const SizedBox(height: 16),
                    // Logging settings cards
                    _buildCard(
                      iconData: Icons.bar_chart_outlined,
                      title: 'Automatic Logging',
                      subtitle: 'Record sensor data continuously',
                      trailing: _buildToggle(
                        value: _automaticLogging,
                        onChanged: (v) =>
                            setState(() => _automaticLogging = v),
                      ),
                    ),
                    const SizedBox(height: 5),
                    _buildCard(
                      iconData: Icons.cloud_outlined,
                      title: 'Cloud Sync',
                      subtitle: 'Backup data to cloud storage',
                      trailing: _buildToggle(
                        value: _cloudSync,
                        onChanged: (v) => setState(() => _cloudSync = v),
                      ),
                    ),
                    const SizedBox(height: 5),
                    _buildRetentionCard(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('EXPORT DATA'),
                    const SizedBox(height: 16),
                    _buildExportCard(
                      iconGradient: const [
                        Color(0xFF00D492),
                        Color(0xFF009689)
                      ],
                      iconData: Icons.table_chart_outlined,
                      title: 'Export as CSV',
                      subtitle: 'Spreadsheet format for analysis',
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
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
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
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
          Row(
            children: const [
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
                    onTap: () =>
                        setState(() => _retentionDays = days),
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
  }) {
    return Container(
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
          const Icon(Icons.chevron_right,
              size: 20, color: Color(0xFF62748E)),
        ],
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
            'Permanently delete all stored sensor data. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF141A1E))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All data cleared.')),
              );
            },
            child: const Text('Clear',
                style: TextStyle(color: Color(0xFFE7000B))),
          ),
        ],
      ),
    );
  }
}
