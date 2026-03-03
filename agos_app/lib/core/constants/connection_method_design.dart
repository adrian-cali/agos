import 'package:flutter/material.dart';

/// Design tokens for Connection Method screen (Figma node 335:716).
/// Use these for font, sizing, spacing, and color so the screen matches the design exactly.
class ConnectionMethodDesign {
  ConnectionMethodDesign._();

  // ----- Background -----
  static const backgroundGradient = [
    Color(0xFFF8FAFC), // #F8FAFC (Figma)
    Color(0xFFEFF6FF), // #EFF6FF (Figma middle stop)
    Color(0xFFECFEFF), // #ECFEFF (Figma last stop)
  ];
  static const backgroundGradientStops = [0.0, 0.5, 1.0];

  // ----- Progress bar -----
  static const double progressValue = 0.25;
  static const double progressHeight = 8; // Figma ~7.99
  static const double progressRadius = 4;
  static const Color progressFill = Color(0xFF0F172A); // #0F172A (Figma)
  static const Color progressTrack = Color.fromRGBO(15, 23, 42, 0.20); // rgba(15,23,42,0.2)


  // ----- Spacing (px) -----
  static const double screenPaddingH = 25; // Figma uses 25px horizontal padding
  static const double topPadding = 9; // top padding in Figma header
  static const double progressToStatus = 8; // gap ~8px in Figma
  static const double sectionToTitle = 25;
  static const double titleToSubtitle = 4; // small gap between title and subtitle
  static const double sectionToCards = 25;
  static const double gapBetweenCards = 16;
  static const double bottomButtonTop = 16;
  static const double bottomButtonBottom = 16; // adjusted to match Figma spacing


  // ----- Status text "Setting up your AGOS system..." -----
  static const double statusFontSize = 12; // Figma 12px
  static const FontWeight statusFontWeight = FontWeight.w400;
  static const Color statusColor = Color(0xFF45556C); // #45556C (Figma)
  static const double statusLineHeight = 16 / 12; // 1.333


  // ----- Main title "Choose Connection Method" -----
  static const double titleFontSize = 24; // Figma 24px (Poppins)
  static const FontWeight titleChooseWeight = FontWeight.w400;
  static const FontWeight titleHighlightWeight = FontWeight.w400;
  static const Color titleChooseColor = Color(0x00000000); // text is rendered with gradient
  static const List<Color> titleGradient = [
    Color(0xFF1447E6), // rgb(20,71,230)
    Color(0xFF0092B8), // rgb(0,146,184)
    Color(0xFF1447E6),
  ];
  static const double titleLineHeight = 32 / 24; // 1.3333


  // ----- Subtitle -----
  static const double subtitleFontSize = 16; // Figma 16px
  static const FontWeight subtitleFontWeight = FontWeight.w400;
  static const Color subtitleColor = Color(0xFF45556C); // #45556C (Figma)
  static const double subtitleLineHeight = 24 / 16; // 1.5


  // ----- Connection card -----
  static const double cardPadding = 17.18; // Figma padding
  static const double cardRadius = 16; // Figma 16px
  static const Color cardBackground = Color.fromRGBO(255, 255, 255, 0.7); // semi-transparent white from Figma
  static const double cardShadowBlur = 8; // Figma 8px blur
  static const double cardShadowOffsetY = 0; // shadow offset 0 in Figma
  static const Color cardShadowColor = Color.fromRGBO(93, 173, 226, 0.15); // rgba(93,173,226,0.15)
  static const double cardShadowOpacity = 1.0; // color already contains alpha
  static const Color cardBorderColor = Color.fromRGBO(255, 255, 255, 0.18);
  static const double cardBorderWidth = 1.18;

  // ----- Card icon container -----
  static const double iconSize = 55.97; // Figma 55.97
  static const double iconRadius = 20; // Figma rounded-[20px]
  static const double iconGlyphSize = 32; // fits Figma inner padding
  static const double iconToContent = 16; 

  // ----- Card title (e.g. "WiFi Connection") -----
  static const double cardTitleFontSize = 16; // Figma 16px
  static const FontWeight cardTitleFontWeight = FontWeight.w400;
  static const Color cardTitleColor = Color(0xFF1D293D); // #1D293D
  static const double cardTitleToDescription = 6; 

  // ----- Card description -----
  static const double cardDescriptionFontSize = 14;
  static const FontWeight cardDescriptionFontWeight = FontWeight.w400;
  static const Color cardDescriptionColor = Color(0xFF45556C); // #45556C
  static const double cardDescriptionLineHeight = 20 / 14; // ~1.4286 (Figma uses 20px leading)
  static const double cardDescriptionToRecommendation = 10; 

  // ----- Card recommendation (green line) -----
  static const double recommendationFontSize = 12; // Figma 12px
  static const FontWeight recommendationFontWeight = FontWeight.w400;
  static const Color recommendationColor = Color(0xFF009966);
  static const double recommendationIconSize = 16;
  static const double recommendationIconToText = 6; 

  // ----- Icon gradients -----
  static const wifiGradientStart = Color(0xFF00D3F2); // rgb(0,211,242)
  static const wifiGradientEnd = Color(0xFF155DFC); // rgb(21,93,252)
  static const bluetoothGradientStart = Color(0xFFC27AFF); // rgb(194,122,255)
  static const bluetoothGradientEnd = Color(0xFFE60076); // rgb(230,0,118)


  // ----- Back button -----
  static const double backButtonPaddingV = 6; // matches 36px height in Figma
  static const double backButtonPaddingH = 16;
  static const double backButtonRadius = 14; // Figma rounded-[14px]
  static const double backButtonBorderWidth = 1.18;
  static const Color backButtonBackground = Color(0xFFFFFFFF); // white background
  static const double backButtonBackgroundOpacity = 1.0;
  static const Color backButtonBorderColor = Color(0xFFA2F4FD); // #A2F4FD (Figma border)
  static const double backButtonBorderOpacity = 1.0;
  static const double backButtonFontSize = 14; // Figma 14px
  static const FontWeight backButtonFontWeight = FontWeight.w500; // Inter:Medium
  static const Color backButtonTextColor = Color(0xFF0A1929); // #0A1929
  static const double backButtonIconSize = 16; // Figma ~16px
  static const double backButtonIconToText = 8;
}
