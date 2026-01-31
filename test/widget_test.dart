
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

    // Verify that the home screen is shown
    expect(find.text('System Design\nSimulator'), findsOneWidget);
    expect(find.text('Start Learning'), findsOneWidget);
  });
}
