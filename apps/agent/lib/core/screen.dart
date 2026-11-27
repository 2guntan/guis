import 'package:flutter/services.dart';

const _channel = MethodChannel('guis/ecran');

/// Garde l'écran allumé (tour du champ) ou rend la mise en veille normale. Sans effet hors Android.
Future<void> keepScreenOn(bool on) async {
  try {
    await _channel.invokeMethod<void>('garderAllume', on);
  } catch (_) {
    /* plateforme sans ce canal (tests, autre système) */
  }
}
