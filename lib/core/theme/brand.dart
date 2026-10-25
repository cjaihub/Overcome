import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Single source of truth for the Ovacome brand (deep teal + warm gold,
/// matching the logo set in `assets/brand/`).
///
/// The same token names are sent to the AI plan generator (see
/// `functions/src/brand.ts`) so generated templates can only reference
/// colors and icons that exist here.
abstract final class Brand {
  static const name = 'Ovacome';
  static const tagline = 'Reclaim your attention. Rebuild your life.';

  // Core palette
  static const ink = Color(0xFF061B1E); // deepest teal (dark background)
  static const midnight = Color(0xFF0A2A2E); // logo tile teal (dark surfaces)
  static const slate = Color(0xFF12403F);
  static const mist = Color(0xFFFBF6EC); // logo cream (light background)
  static const cloud = Color(0xFFEFE6D3);

  static const aurora = Color(0xFFE8B04F); // primary — the gold ring of the mark
  static const iris = Color(0xFF2FA89A); // secondary — teal glow
  static const ember = Color(0xFFEE8A5B); // accent — energy, urges
  static const bloom = Color(0xFFE58BA0); // accent — self-compassion
  static const success = Color(0xFF58C891);
  static const danger = Color(0xFFF07B6F);

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
    colors: [Color(0xFFF3CD7E), Color(0xFFD9963A)],
  );

  static const tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF145650), midnight],
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

  // Typography: Fraunces (a serif echoing the wordmark) for display,
  // Inter for body.
  static TextTheme textTheme(Color onSurface) {
    final display = GoogleFonts.frauncesTextTheme();
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

/// Logo assets (1x/2x/3x variants are picked automatically per device).
abstract final class BrandAssets {
  static const mark = 'assets/brand/logo_mark.png';
  static String horizontal(Brightness b) =>
      'assets/brand/logo_horizontal_${b == Brightness.dark ? 'dark' : 'light'}.png';
  static String stacked(Brightness b) => 'assets/brand/logo_stacked_${b == Brightness.dark ? 'dark' : 'light'}.png';
}
