import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional import for web
// We use a internal helper to avoid compilation errors on non-web platforms
import 'file_utils_stub.dart' if (dart.library.html) 'file_utils_web.dart';

class FileSaver {
  static void saveJson(String json, String fileName) {
    if (kIsWeb) {
      saveFileWeb(json, fileName);
    } else {
      print("JSON Export ($fileName):/n$json");
    }
  }

  static Future<String?> pickJson() async {
    if (kIsWeb) {
      return pickFileWeb();
    }
    return null; // Not implemented for mobile yet
  }
}
