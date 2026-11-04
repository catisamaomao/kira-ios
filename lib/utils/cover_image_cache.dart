import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'image_file_service.dart';

/// Reuses the existing cover/avatar database and files, with bounded downloads.
class CoverImageCacheManager extends CacheManager with ImageCacheManager {
  static final CoverImageCacheManager instance = CoverImageCacheManager._();

  CoverImageCacheManager._()
    : super(
        Config(
          DefaultCacheManager.key,
          fileService: BoundedImageFileService(source: 'cover_image'),
        ),
      );

  /// Call after NetworkProxy.init, before any image widgets are mounted.
  static void install() {
    CachedNetworkImageProvider.defaultCacheManager = instance;
  }
}
