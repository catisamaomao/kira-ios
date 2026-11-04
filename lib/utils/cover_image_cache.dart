import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_dio.dart';
import 'app_logger.dart';

/// Reuses the existing cover/avatar database and files, with bounded downloads.
class CoverImageCacheManager extends CacheManager with ImageCacheManager {
  static final CoverImageCacheManager instance = CoverImageCacheManager._();

  CoverImageCacheManager._()
    : super(
        Config(DefaultCacheManager.key, fileService: CoverImageFileService()),
      );

  /// Call after NetworkProxy.init, before any image widgets are mounted.
  static void install() {
    CachedNetworkImageProvider.defaultCacheManager = instance;
  }
}

/// The pool is shared; cancelling one slow image leaves other downloads alone.
class CoverImageFileService extends FileService {
  CoverImageFileService({
    Duration idleTimeout = const Duration(seconds: 15),
    this.totalTimeout = const Duration(seconds: 30),
  }) : _dio = AppDio.create(
         source: 'cover_image',
         enableRateLimit: false,
         options: BaseOptions(
           connectTimeout: idleTimeout,
           sendTimeout: idleTimeout,
           receiveTimeout: idleTimeout,
           responseType: ResponseType.stream,
           validateStatus: (_) => true,
         ),
       );

  final Duration totalTimeout;
  final Dio _dio;
  final Set<_CoverRequest> _active = {};

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final request = _CoverRequest(totalTimeout, _active.remove);
    _active.add(request);
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(headers: headers),
        cancelToken: request.token,
      );
      final body = response.data;
      if (body == null) throw StateError('Image response has no body: $url');

      final Stream<List<int>> content;
      if (body.statusCode == HttpStatus.ok ||
          body.statusCode == HttpStatus.accepted) {
        content = _boundedContent(body.stream, request);
      } else {
        // CacheManager does not consume 304/error bodies. Do not leave their
        // sockets or deadline timers alive, and do not wait for a stalled body.
        await body.stream.listen(null).cancel();
        request.cancel(
          'Image response body is not needed (${body.statusCode})',
        );
        content = const Stream.empty();
      }
      return _CoverFileServiceResponse(body, content);
    } catch (error, stackTrace) {
      request.cancel(error);
      Error.throwWithStackTrace(request.timeoutError ?? error, stackTrace);
    }
  }

  Stream<List<int>> _boundedContent(
    Stream<Uint8List> source,
    _CoverRequest request,
  ) {
    StreamSubscription<Uint8List>? subscription;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            request.cancel(error);
            controller.addError(request.timeoutError ?? error, stackTrace);
            unawaited(controller.close());
          },
          onDone: () {
            request.finish();
            unawaited(controller.close());
          },
          cancelOnError: true,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        // Dio's response stream does not forward consumer cancellation to its
        // socket. The token does, including while waiting for the next chunk.
        request.cancel('Image response consumer cancelled');
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  void close() {
    for (final request in _active.toList()) {
      request.cancel('Image file service closed');
    }
    _dio.close(force: true);
  }
}

class _CoverRequest {
  _CoverRequest(Duration timeout, this._onFinished) {
    _timer = Timer(timeout, () {
      timeoutError = TimeoutException(
        'Image download deadline exceeded',
        timeout,
      );
      cancel(timeoutError);
    });
  }

  final CancelToken token = CancelToken();
  final void Function(_CoverRequest) _onFinished;
  Timer? _timer;
  bool _finished = false;
  TimeoutException? timeoutError;

  void finish() {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _onFinished(this);
  }

  void cancel(Object? reason) {
    if (_finished) return;
    if (!token.isCancelled) token.cancel(reason);
    finish();
  }
}

class _CoverFileServiceResponse implements FileServiceResponse {
  _CoverFileServiceResponse(this._body, this.content);

  final ResponseBody _body;
  final DateTime _receivedTime = DateTime.now();

  @override
  final Stream<List<int>> content;

  String? _header(String name) => _body.headers[name]?.join(',');

  @override
  int get statusCode => _body.statusCode;

  @override
  int? get contentLength {
    final length = int.tryParse(_header(HttpHeaders.contentLengthHeader) ?? '');
    return length != null && length >= 0 ? length : null;
  }

  @override
  String? get eTag => _header(HttpHeaders.etagHeader);

  @override
  DateTime get validTill {
    var age = const Duration(days: 7);
    final directives = (_header(HttpHeaders.cacheControlHeader) ?? '')
        .toLowerCase()
        .split(',')
        .map((part) => part.trim());
    if (directives.contains('no-cache') || directives.contains('no-store')) {
      return _receivedTime;
    }
    for (final directive in directives) {
      final match = RegExp(r'^max-age\s*=\s*"?(\d+)"?$').firstMatch(directive);
      final seconds = int.tryParse(match?.group(1) ?? '');
      if (seconds != null) age = Duration(seconds: seconds);
    }
    return _receivedTime.add(age);
  }

  @override
  String get fileExtension {
    final raw = _header(HttpHeaders.contentTypeHeader);
    if (raw == null) return '';
    try {
      final type = ContentType.parse(raw);
      return const {
            'image/jpeg': '.jpg',
            'image/png': '.png',
            'image/gif': '.gif',
            'image/webp': '.webp',
            'image/avif': '.avif',
            'image/bmp': '.bmp',
            'image/svg+xml': '.svg',
            'image/tiff': '.tiff',
            'image/vnd.microsoft.icon': '.ico',
            'application/octet-stream': '.bin',
          }[type.mimeType] ??
          '.${type.subType}';
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stackTrace,
          source: 'cover_image.content_type',
        ),
      );
      return '';
    }
  }
}
