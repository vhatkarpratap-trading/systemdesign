import 'package:flutter/widgets.dart';

/// Responsive breakpoint definitions
enum ScreenSize {
  compact,  // < 600px (mobile)
  medium,   // 600-900px (tablet)
  expanded, // > 900px (desktop/web)
}

/// Responsive layout utilities
class ResponsiveLayout {
  /// Get the current screen size based on width
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return getScreenSizeFromWidth(width);
  }

  /// Get screen size from a specific width value
  static ScreenSize getScreenSizeFromWidth(double width) {
    if (width < 600) {
      return ScreenSize.compact;
    } else if (width < 900) {
      return ScreenSize.medium;
    } else {
      return ScreenSize.expanded;
    }
  }

  /// Check if current screen is compact (mobile)
  static bool isCompact(BuildContext context) {
    return getScreenSize(context) == ScreenSize.compact;
  }

  /// Check if current screen is medium (tablet)
  static bool isMedium(BuildContext context) {
    return getScreenSize(context) == ScreenSize.medium;
  }

  /// Check if current screen is expanded (desktop/web)
  static bool isExpanded(BuildContext context) {
    return getScreenSize(context) == ScreenSize.expanded;
  }

  /// Check if screen should use sidebar layout (medium or expanded)
  static bool shouldUseSidebar(BuildContext context) {
    final size = getScreenSize(context);
    return size == ScreenSize.medium || size == ScreenSize.expanded;
  }

  /// Get sidebar width based on screen size
  static double getSidebarWidth(BuildContext context) {
    final size = getScreenSize(context);
    switch (size) {
      case ScreenSize.compact:
        return 0;
      case ScreenSize.medium:
        return 200;
      case ScreenSize.expanded:
        return 260;
    }
  }
}
