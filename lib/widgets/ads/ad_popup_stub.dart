import 'package:flutter/material.dart';

class AdPopupPlatform extends StatelessWidget {
  final String adClientId;
  final String adSlotId;
  final double width;
  final double height;

  const AdPopupPlatform({
    super.key,
    required this.adClientId,
    required this.adSlotId,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
