import 'analytics_service_stub.dart'
    if (dart.library.js_interop) 'analytics_service_web.dart'
    as analytics_impl;

/// Lightweight analytics facade used across the app.
///
/// On web, this forwards events to Google Analytics via gtag.
/// On non-web platforms, it is a no-op.
class AnalyticsService {
  static void event(String name, {Map<String, Object?> parameters = const {}}) {
    analytics_impl.trackEvent(name, parameters);
  }
}
