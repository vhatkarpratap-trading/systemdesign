import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/game_screen.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://uvbvgyepzrfaqpsqphjl.supabase.co',
    anonKey: 'sb_publishable_0LB-X57NyXJdRmkfr8N-Zw_zbvHvZWz',
  );
  
  // Set system UI style (only on mobile)
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
      ),
    );

    // Lock to portrait mode for mobile only
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(
    const ProviderScope(
      child: SystemDesignSimulatorApp(),
    ),
  );
}

class SystemDesignSimulatorApp extends ConsumerWidget {
  const SystemDesignSimulatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Map<String, dynamic>? initialDesign;
    String? initialDesignId;
    if (kIsWeb) {
      final encoded = Uri.base.queryParameters['design'];
      if (encoded != null && encoded.isNotEmpty) {
        try {
          final jsonStr = utf8.decode(base64Url.decode(encoded));
          initialDesign = jsonDecode(jsonStr) as Map<String, dynamic>;
        } catch (_) {
          initialDesign = null;
        }
      }
      final idParam = Uri.base.queryParameters['designId'];
      if (idParam != null && idParam.isNotEmpty) {
        initialDesignId = idParam;
      }
    }

    return MaterialApp(
      title: 'System Design Simulator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: GameScreen(
        initialCommunityDesign: initialDesign,
        sharedDesignId: initialDesignId,
      ),
    );
  }
}
