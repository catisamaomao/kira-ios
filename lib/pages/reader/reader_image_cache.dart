part of '../reader_page.dart';

class _ReaderImageFileService extends FileService {
  _ReaderImageFileService(Duration timeout)
    : _fileService = BoundedImageFileService(
        source: 'reader_image',
        idleTimeout: timeout,
        // Full manga pages need more transfer time than small cover images.
        totalTimeout: timeout * 4,
      );

  final BoundedImageFileService _fileService;

  static const _defaultHeaders = {
    'user-agent':
        'Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/110.0.5481.154 Mobile Safari/537.36',
    'accept':
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'x-requested-with': 'com.manga2020.app',
    'sec-fetch-site': 'cross-site',
    'sec-fetch-mode': 'no-cors',
    'sec-fetch-dest': 'image',
    'accept-encoding': 'gzip, deflate',
    'accept-language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final stopwatch = Stopwatch()..start();
    // 命中缓存不会走到这里；只有真实网络请求才有归属，供阅读统计埋点反查。
    final statsOwner = _statsImageOwnerByUrl[url];
    final response = await _fileService.get(
      url,
      headers: {
        ..._defaultHeaders,
        if (headers != null)
          for (final header in headers.entries)
            header.key.toLowerCase(): header.value,
      },
    );
    return _ReaderImageFileServiceResponse(response, stopwatch, statsOwner);
  }
}

class _ReaderImageFileServiceResponse implements FileServiceResponse {
  _ReaderImageFileServiceResponse(
    this._response,
    this._stopwatch,
    this._statsOwner,
  );

  final FileServiceResponse _response;
  final Stopwatch _stopwatch;

  /// 该图片 URL 登记的归属（漫画 + 章节）。未登记（非章节图/异常）为 null。
  final ({String pathWord, String chapterUuid})? _statsOwner;

  bool _recorded = false;

  @override
  Stream<List<int>> get content {
    return _response.content.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleDone: (sink) {
          if (!_recorded &&
              (statusCode == HttpStatus.ok ||
                  statusCode == HttpStatus.accepted)) {
            _recorded = true;
            _stopwatch.stop();
            ImageLoadStats().record(_stopwatch.elapsed);
            // 阅读统计：与 ImageLoadStats 同口径，仅真实网络请求计入。
            final owner = _statsOwner;
            if (owner != null) {
              final meta = _statsComicMetaByPath[owner.pathWord];
              unawaited(
                ReadingStats.recordImageLoad(
                  pathWord: owner.pathWord,
                  chapterUuid: owner.chapterUuid,
                  comicName: meta?.name,
                  tags: meta?.tags,
                ),
              );
            }
          }
          sink.close();
        },
        handleError: (error, stackTrace, sink) {
          _recorded = true;
          _stopwatch.stop();
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  @override
  int? get contentLength => _response.contentLength;

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill => _response.validTill;

  @override
  String? get eTag => _response.eTag;

  @override
  String get fileExtension => _response.fileExtension;
}
