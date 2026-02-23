import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/connection_method_design.dart';

class ConnectionMethodScreen extends StatelessWidget {
  const ConnectionMethodScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: ConnectionMethodDesign.backgroundGradient,
            stops: ConnectionMethodDesign.backgroundGradientStops,
          ),
        ),
        child: Stack(
          children: [
            // Main content (behind progress bar)
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Title
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: ConnectionMethodDesign.titleGradient,
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ).createShader(
                          Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                        ),
                        blendMode: BlendMode.srcIn,
                        child: Text(
                          'Choose Connection Method',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: ConnectionMethodDesign.titleFontSize,
                            fontWeight: ConnectionMethodDesign.titleChooseWeight,
                            height: ConnectionMethodDesign.titleLineHeight,
                            color: Colors.white, // masked by shader
                          ),
                        ),
                      ),
                      const SizedBox(height: ConnectionMethodDesign.titleToSubtitle),
                      Text(
                        'Select how you\'d like to connect to your AGOS hardware.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: ConnectionMethodDesign.subtitleFontSize,
                          fontWeight: ConnectionMethodDesign.subtitleFontWeight,
                          height: ConnectionMethodDesign.subtitleLineHeight,
                          color: ConnectionMethodDesign.subtitleColor,
                        ),
                      ),
                      const SizedBox(height: ConnectionMethodDesign.sectionToCards),

                      // Connection cards
                      _ConnectionCard(
                        icon: Icons.wifi,
                        iconGradient: const [
                          ConnectionMethodDesign.wifiGradientStart,
                          ConnectionMethodDesign.wifiGradientEnd,
                        ],
                        title: 'WiFi Connection',
                        description:
                            'Connect via your local WiFi network for stable, long-range communication.',
                        recommendation: 'Recommended for permanent installation',
                        onTap: () => Navigator.pushNamed(context, '/wifi-setup'),
                      ),
                      const SizedBox(height: ConnectionMethodDesign.gapBetweenCards),
                      _ConnectionCard(
                        icon: Icons.bluetooth,
                        iconGradient: const [
                          ConnectionMethodDesign.bluetoothGradientStart,
                          ConnectionMethodDesign.bluetoothGradientEnd,
                        ],
                        title: 'Bluetooth Connection',
                        description:
                            'Quick pairing for nearby devices without network setup.',
                        recommendation: 'Best for initial setup & testing',
                        onTap: () =>
                            Navigator.pushNamed(context, '/bluetooth-setup-1'),
                      ),
                      const SizedBox(height: 24),

                      // Back button  ✅ fixed brackets here
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pushReplacementNamed(
                            context,
                            '/welcome',
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: ConnectionMethodDesign.backButtonPaddingV,
                              horizontal: ConnectionMethodDesign.backButtonPaddingH,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                ConnectionMethodDesign.backButtonRadius,
                              ),
                            ),
                            backgroundColor:
                                ConnectionMethodDesign.backButtonBackground,
                            foregroundColor:
                                ConnectionMethodDesign.backButtonTextColor,
                            side: const BorderSide(
                              color: ConnectionMethodDesign.backButtonBorderColor,
                              width: ConnectionMethodDesign.backButtonBorderWidth,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.chevron_left,
                                size: ConnectionMethodDesign.backButtonIconSize,
                                color: ConnectionMethodDesign.backButtonTextColor,
                              ),
                              const SizedBox(
                                width: ConnectionMethodDesign.backButtonIconToText,
                              ),
                              Text(
                                'Back',
                                style: GoogleFonts.inter(
                                  fontSize: ConnectionMethodDesign.backButtonFontSize,
                                  fontWeight:
                                      ConnectionMethodDesign.backButtonFontWeight,
                                  color: ConnectionMethodDesign.backButtonTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Progress bar overlay (on top, in SafeArea)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(25, 9, 25, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        value: 0.25,
                        minHeight: 8,
                        backgroundColor: Color.fromRGBO(15, 23, 42, 0.20),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Setting up your AGOS system...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 16 / 12,
                        color: const Color(0xFF45556C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.description,
    required this.recommendation,
    required this.onTap,
  });

  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String description;
  final String recommendation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ConnectionMethodDesign.cardRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(ConnectionMethodDesign.cardPadding),
          decoration: BoxDecoration(
            color: ConnectionMethodDesign.cardBackground,
            borderRadius: BorderRadius.circular(ConnectionMethodDesign.cardRadius),
            border: Border.all(
              color: ConnectionMethodDesign.cardBorderColor,
              width: ConnectionMethodDesign.cardBorderWidth,
            ),
            boxShadow: const [
              BoxShadow(
                color: ConnectionMethodDesign.cardShadowColor,
                blurRadius: ConnectionMethodDesign.cardShadowBlur,
                offset: Offset(0, ConnectionMethodDesign.cardShadowOffsetY),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: ConnectionMethodDesign.iconSize,
                height: ConnectionMethodDesign.iconSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.circular(ConnectionMethodDesign.iconRadius),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: ConnectionMethodDesign.iconGlyphSize,
                ),
              ),
              const SizedBox(width: ConnectionMethodDesign.iconToContent),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: ConnectionMethodDesign.cardTitleFontSize,
                        fontWeight: ConnectionMethodDesign.cardTitleFontWeight,
                        color: ConnectionMethodDesign.cardTitleColor,
                      ),
                    ),
                    const SizedBox(
                      height: ConnectionMethodDesign.cardTitleToDescription,
                    ),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        fontSize: ConnectionMethodDesign.cardDescriptionFontSize,
                        fontWeight: ConnectionMethodDesign.cardDescriptionFontWeight,
                        height: ConnectionMethodDesign.cardDescriptionLineHeight,
                        color: ConnectionMethodDesign.cardDescriptionColor,
                      ),
                    ),
                    const SizedBox(
                      height: ConnectionMethodDesign.cardDescriptionToRecommendation,
                    ),
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: ConnectionMethodDesign.recommendationIconSize,
                          color: ConnectionMethodDesign.recommendationColor,
                        ),
                        const SizedBox(
                          width: ConnectionMethodDesign.recommendationIconToText,
                        ),
                        Expanded(
                          child: Text(
                            recommendation,
                            style: GoogleFonts.inter(
                              fontSize: ConnectionMethodDesign.recommendationFontSize,
                              fontWeight:
                                  ConnectionMethodDesign.recommendationFontWeight,
                              color: ConnectionMethodDesign.recommendationColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
