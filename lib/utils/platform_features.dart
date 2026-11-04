import 'package:flutter/foundation.dart';

/// Capabilities implemented by the platform integrations in this application.
abstract final class PlatformFeatures {
  static bool get volumeKeyPageTurn =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // A directory picker grants only temporary access on iOS. Downloads must
  // remain in Documents until native security-scoped bookmarks are supported.
  static bool get customDownloadDirectory =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
