import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'ad_popup_stub.dart' if (dart.library.html) 'ad_popup_web.dart';

/// A styled popup container that shows a Google AdSense rectangle on web.
/// Replace [adClientId]/[adSlotId] with your real values.
class AdPopup extends StatelessWidget {
  final String adClientId;
  final String adSlotId;
  final double width;
  final double height;

  const AdPopup({
    super.key,
    this.adClientId = 'ca-pub-9089121621385642',
    this.adSlotId = '0000000000',
    this.width = 336,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AdPopupPlatform(
        adClientId: adClientId,
        adSlotId: adSlotId,
        width: width,
        height: height,
      ),
    );
  }
}
