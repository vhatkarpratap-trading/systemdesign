// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

class AdPopupPlatform extends StatefulWidget {
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
  State<AdPopupPlatform> createState() => _AdPopupPlatformState();
}

class _AdPopupPlatformState extends State<AdPopupPlatform> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'adsense-popup-${widget.adSlotId}-${DateTime.now().microsecondsSinceEpoch}';
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = html.DivElement()
        ..style.width = '${widget.width}px'
        ..style.height = '${widget.height}px'
        ..style.display = 'block'
        ..style.overflow = 'hidden';

      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '${widget.width}px'
        ..style.height = '${widget.height}px'
        ..setAttribute('data-ad-client', widget.adClientId)
        ..setAttribute('data-ad-slot', widget.adSlotId)
        ..setAttribute('data-ad-format', 'rectangle')
        ..setAttribute('data-full-width-responsive', 'false');

      container.append(ins);

      final script = html.ScriptElement()
        ..text = '(adsbygoogle = window.adsbygoogle || []).push({});';
      container.append(script);
      return container;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
