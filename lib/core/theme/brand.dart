import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Single source of truth for the Overcome brand.
///
/// The same token names are sent to the AI plan generator (see
/// `functions/src/brand.ts`) so generated templates can only reference
/// colors and icons that exist here.
abstract final class Brand {
  static const name = 'Overcome';
  static const tagline = 'Reclaim your attention. Rebuild your life.';

  // Core palette
  static const ink = Color(0xFF0A1628);
  static const midnight = Color(0xFF111D33);
  static const slate = Color(0xFF1B2A44);
  static const mist = Color(0xFFF5F7FB);
  static const cloud = Color(0xFFE6EAF2);

  static const aurora = Color(0xFF2DD4BF); // primary — recovery, clarity
  static const iris = Color(0xFF7C6CF6); // secondary — reflection, depth
  static const ember = Color(0xFFF59E5B); // accent — energy, momentum
  static const bloom = Color(0xFFF472B6); // accent — self-compassion
  static const success = Color(0xFF34D399);
  static const danger = Color(0xFFF87171);

  /// Accent tokens the AI agent is allowed to choose from.
  static const accents = <String, Color>{
    'aurora': aurora,
    'iris': iris,
    'ember': ember,
    'bloom': bloom,
    'success': success,
  };

  static Color accent(String? token) => accents[token] ?? aurora;

  static const auroraGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [aurora, iris],
  );

  static const emberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ember, bloom],
  );

  static LinearGradient gradientFor(String? token) {
    final c = accent(token);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c, Color.lerp(c, iris, 0.55)!],
    );
  }

  // Typography: Sora for display, Inter for body.
  static TextTheme textTheme(Color onSurface) {
    final display = GoogleFonts.soraTextTheme();
    final body = GoogleFonts.interTextTheme();
    return TextTheme(
      displayLarge: display.displayLarge!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.5),
      displayMedium: display.displayMedium!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
      displaySmall: display.displaySmall!.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5),
      headlineLarge: display.headlineLarge!.copyWith(fontWeight: FontWeight.w600),
      headlineMedium: display.headlineMedium!.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
      headlineSmall: display.headlineSmall!.copyWith(fontWeight: FontWeight.w600),
      titleLarge: display.titleLarge!.copyWith(fontWeight: FontWeight.w600),
      titleMedium: body.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      titleSmall: body.titleSmall!.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: body.bodyLarge!.copyWith(height: 1.5),
      bodyMedium: body.bodyMedium!.copyWith(height: 1.5),
      bodySmall: body.bodySmall,
      labelLarge: body.labelLarge!.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      labelMedium: body.labelMedium,
      labelSmall: body.labelSmall!.copyWith(letterSpacing: 0.8),
    ).apply(bodyColor: onSurface, displayColor: onSurface);
  }

  /// Icons the AI agent may reference by name in generated templates.
  static const icons = <String, IconData>{
    'spark': Icons.auto_awesome_rounded,
    'mind': Icons.psychology_alt_rounded,
    'heart': Icons.favorite_rounded,
    'shield': Icons.shield_moon_rounded,
    'sun': Icons.wb_sunny_rounded,
    'moon': Icons.bedtime_rounded,
    'walk': Icons.directions_walk_rounded,
    'book': Icons.menu_book_rounded,
    'journal': Icons.edit_note_rounded,
    'target': Icons.track_changes_rounded,
    'phone_off': Icons.phonelink_erase_rounded,
    'people': Icons.people_alt_rounded,
    'breath': Icons.air_rounded,
    'trophy': Icons.emoji_events_rounded,
    'clock': Icons.schedule_rounded,
  };

  static IconData icon(String? token) => icons[token] ?? Icons.auto_awesome_rounded;

  static const radius = 20.0;
  static const radiusLg = 28.0;
  static const motionFast = Duration(milliseconds: 220);
  static const motion = Duration(milliseconds: 420);
  static const motionSlow = Duration(milliseconds: 900);
}
