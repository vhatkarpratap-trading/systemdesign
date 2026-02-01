import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import 'level_select_screen.dart';
import 'community_screen.dart';


/// Home/Landing screen for the app
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {


    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.background,
              const Color(0xFF0F0F24),
              const Color(0xFF151530),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [

              Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 48), // Added top spacing for scrollable content
                          
                          // Logo/Icon
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.architecture,
                              size: 64,
                              color: Colors.white,
                            ),
                          ).animate()
                              .fadeIn(duration: 600.ms)
                              .scale(begin: const Offset(0.8, 0.8)),
  
                          const SizedBox(height: 32),
  
                          // Title
                          const Text(
                            'System Design\nSimulator',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                          )
                              .animate()
                              .fadeIn(delay: 200.ms, duration: 600.ms)
                              .slideY(begin: 0.2, end: 0),
  
                          const SizedBox(height: 16),
  
                          // Subtitle
                          const Text(
                            'Learn to build scalable systems\nthrough interactive simulation',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          )
                              .animate()
                              .fadeIn(delay: 400.ms, duration: 600.ms),
  
                          const SizedBox(height: 48),
  
                          // Features list
                          _FeatureRow(
                            icon: Icons.widgets_outlined,
                            text: 'Drag & drop system components',
                          )
                              .animate()
                              .fadeIn(delay: 500.ms)
                              .slideX(begin: -0.2),
                          const SizedBox(height: 12),
                          _FeatureRow(
                            icon: Icons.play_circle_outline,
                            text: 'Watch your system handle traffic',
                          )
                              .animate()
                              .fadeIn(delay: 600.ms)
                              .slideX(begin: -0.2),
                          const SizedBox(height: 12),
                          _FeatureRow(
                            icon: Icons.warning_amber_outlined,
                            text: 'See failures and fix bottlenecks',
                          )
                              .animate()
                              .fadeIn(delay: 700.ms)
                              .slideX(begin: -0.2),
                          const SizedBox(height: 12),
                          _FeatureRow(
                            icon: Icons.emoji_events_outlined,
                            text: 'Score and improve your design',
                          )
                              .animate()
                              .fadeIn(delay: 800.ms)
                              .slideX(begin: -0.2),
  
                          const SizedBox(height: 48),
  
                          // Start button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LevelSelectScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: AppTheme.background,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Start Learning',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_rounded),
                                ],
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(delay: 900.ms)
                              .slideY(begin: 0.3),
  
                          const SizedBox(height: 16),
  
                          // Community button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const CommunityScreen(),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(color: AppTheme.primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.public_rounded, size: 20),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Explore Community Designs',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(delay: 1000.ms)
                              .slideY(begin: 0.3),
  
                          const SizedBox(height: 24),
  
                          // Version
                          const Text(
                            'v1.0.0',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: AppTheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
