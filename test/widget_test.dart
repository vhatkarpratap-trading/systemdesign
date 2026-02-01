
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:system_design_simulator/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Set a larger screen size for testing
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: SystemDesignSimulatorApp(),
      ),
    );
    
    // Wait for animations and providers (especially the 300ms validation debounce) to settle
    await tester.pump(const Duration(seconds: 1));

    // Verify that the login screen is NOT shown anymore on launch
    expect(find.text('Welcome Back'), findsNothing);
    
    // Verify that the GameScreen (Simulator) is shown
    expect(find.text('Design Your Systems'), findsOneWidget); // Default problem title
    
    // Dismiss the app to clear any remaining timers
    await tester.pumpWidget(const SizedBox());
  });
}
