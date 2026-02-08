import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Minimalist dark theme for System Design Simulator
class AppTheme {
  AppTheme._();

  // Color Palette - Cleaner, more muted
  static const Color background = Color(0xFF0A0A0F);
  static const Color surface = Color(0xFF14141C);
  static const Color surfaceLight = Color(0xFF1E1E28);
  static const Color primary = Color(0xFF3B82F6);  // Clean blue
  static const Color primaryMuted = Color(0xFF2563EB);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color success = Color(0xFFFF00FF); // Diagnostic: Magenta (was 0xFF22C55E)
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFF27272A);

  // Component Colors - Softer palette
  static const Color dnsColor = Color(0xFF6366F1);
  static const Color cdnColor = Color(0xFFF59E0B);
  static const Color loadBalancerColor = Color(0xFF00FFFF); // Diagnostic: Cyan (was 0xFF22C55E)
  static const Color apiGatewayColor = Color(0xFF8B5CF6);
  static const Color appServerColor = Color(0xFF3B82F6);
  static const Color workerColor = Color(0xFF71717A);
  static const Color serverlessColor = Color(0xFFEC4899);
  static const Color cacheColor = Color(0xFFEF4444);
  static const Color databaseColor = Color(0xFF14B8A6);
  static const Color objectStoreColor = Color(0xFFF97316);
  static const Color queueColor = Color(0xFFA855F7);
  static const Color pubsubColor = Color(0xFF06B6D4);
  static const Color streamColor = Color(0xFFA78BFA);
  static const Color llmGatewayColor = Color(0xFF0EA5E9); // Sky blue
  static const Color toolRegistryColor = Color(0xFFEAB308); // Amber
  static const Color memoryFabricColor = Color(0xFF34D399); // Mint/green
  static const Color agentOrchestratorColor = Color(0xFF6366F1); // Indigo
  static const Color safetyMeshColor = Color(0xFFFB7185); // Coral

  // Cyberpunk Palette
  static const Color neonCyan = Color(0xFF00FFFF);
  static const Color neonMagenta = Color(0xFFFF00FF);
  static const Color neonGreen = Color(0xFF00FF00); // Terminal Green
  static const Color cyberpunkBackground = Color(0xFF050510); // Deep Space
  static const Color cyberpunkSurface = Color(0xFF101020);

  // Minimal Glass Effect
  static BoxDecoration glassDecoration({
    Color color = surface,
    double opacity = 0.9,
    double borderRadius = 12,
    bool withBorder = true,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: withBorder
          ? Border.all(color: border, width: 1)
          : null,
    );
  }

  // Minimal card decoration
  static BoxDecoration cardDecoration({
    Color? borderColor,
    double borderRadius = 12,
  }) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? border,
        width: 1,
      ),
    );
  }

  // Status Decorations - Simpler
  static BoxDecoration statusDecoration(ComponentStatus status) {
    final color = switch (status) {
      ComponentStatus.healthy => success,
      ComponentStatus.warning => warning,
      ComponentStatus.critical => error,
      ComponentStatus.overloaded => error,
    };

    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: color.withValues(alpha: 0.6),
        width: 1.5,
      ),
    );
  }

  // Theme Data (Dark)
  static ThemeData get darkTheme => _buildTheme();

  static ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        surface: surface,
        error: error,
      ),
      textTheme: GoogleFonts.firaCodeTextTheme(
        const TextTheme(
          displayLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.5),
          displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.3),
          headlineLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary),
          headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: textPrimary),
          titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
          bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.normal, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: textSecondary),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: textMuted),
          labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textPrimary),
        iconTheme: IconThemeData(color: textSecondary, size: 20),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }
}

/// Component health status
enum ComponentStatus {
  healthy,
  warning,
  critical,
  overloaded,
}

/// Extension for status colors
extension ComponentStatusColor on ComponentStatus {
  Color get color => switch (this) {
        ComponentStatus.healthy => AppTheme.success,
        ComponentStatus.warning => AppTheme.warning,
        ComponentStatus.critical => AppTheme.error,
        ComponentStatus.overloaded => AppTheme.error,
      };

  String get label => switch (this) {
        ComponentStatus.healthy => 'Healthy',
        ComponentStatus.warning => 'Warning',
        ComponentStatus.critical => 'Critical',
        ComponentStatus.overloaded => 'Overloaded',
      };
}
