@JS()
library;

import 'dart:js_interop';

@JS('gtag')
external void _gtag(JSString command, JSString target, [JSAny? parameters]);

void trackEvent(String name, Map<String, Object?> parameters) {
  final payload = <String, Object?>{};
  for (final entry in parameters.entries) {
    final value = entry.value;
    if (value == null) continue;
    payload[entry.key] = _normalizeValue(value);
  }

  try {
    _gtag('event'.toJS, name.toJS, payload.jsify());
  } catch (_) {
    // Ignore analytics failures to avoid impacting UX.
  }
}

Object _normalizeValue(Object value) {
  if (value is String || value is num || value is bool) return value;
  if (value is Enum) return value.name;
  return value.toString();
}
