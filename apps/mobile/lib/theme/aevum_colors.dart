import 'package:flutter/material.dart';

/// Brand tokens extracted from aevumhealthhub.com (dark navy + teal accent).
class AevumColors {
  AevumColors._();

  // Primary palette — from CSS custom properties
  static const Color primary = Color(0xFF63BEE9);       // --primary  hsl(199 75% 65%)
  static const Color primaryDark = Color(0xFF245684);    // scrollbar-thumb / deeper teal
  static const Color secondary = Color(0xFF8FD0F2);      // --secondary  hsl(211 36% 66%)
  static const Color accent = Color(0xFF63BEE9);         // --accent (same as primary on site)
  static const Color cream = Color(0xFFF3E8D2);          // warm paper / interior tone
  static const Color gold = Color(0xFFE4B860);           // warm highlight used sparingly

  // Surfaces
  static const Color background = Color(0xFF0D2742);     // body bg
  static const Color surface = Color(0xFF13314F);        // --card
  static const Color surfaceDim = Color(0xFF0A1A27);     // darker panels / overlays
  static const Color border = Color(0xFF2B4564);         // --border
  static const Color muted = Color(0xFF1C3654);          // --muted  hsl(213 50% 22%)
  static const Color mist = Color(0xFF224D73);           // soft atmospheric mid tone

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);    // --foreground
  static const Color textSecondary = Color(0xFFB0CEE8);  // --muted-foreground  hsl(211 40% 80%)

  // Semantic
  static const Color success = Color(0xFF34D399);        // emerald-400 (bright on dark)
  static const Color warning = Color(0xFFFBBF24);        // amber-400
  static const Color error = Color(0xFFE25050);          // --destructive  hsl(0 72% 60%)
}
