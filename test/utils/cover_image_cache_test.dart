import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/cover_image_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String> getTemporaryPath() async => path;

  @override
  Future<String> getApplicationSupportPath() async => path;

  @override
  Future<String> getApplicationDocumentsPath() async => path;
}

class _LocalNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

class _ImageServer {
  _ImageServer(this.server) {
    server.listen((request) {
      requests.add(request);
      remotePorts.add(request.connectionInfo!.remotePort);
      unawaited(handler(request));
    });
  }

  final HttpServer server;
  final requests = <HttpRequest>[];
  final remotePorts = <int>[];
  final sockets = <Socket>[];
  final timers = <Timer>[];
  final started = <String, Completer<void>>{};
  final disconnected = <String, Completer<void>>{};
  late Future<void> Function(HttpRequest) handler;

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<void> waitForStart(String path) =>
      started.putIfAbsent(path, Completer<void>.new).future;

  Future<void> waitForDisconnect(String path) => disconnected
      .putIfAbsent(path, Completer<void>.new)
      .future
      .timeout(const Duration(seconds: 2));

  Future<void> stall(
    HttpRequest request, {
    bool sendHeaders = true,
    int status = 200,
    bool drip = false,
  }) async {
    final path = request.uri.path;
    final socket = await request.response.detachSocket(writeHeaders: false);
    sockets.add(socket);
    Timer? timer;
    void finish() {
      timer?.cancel();
      final done = disconnected.putIfAbsent(path, Completer<void>.new);
      if (!done.isCompleted) done.complete();
    }

    socket.listen(
      (_) {},
      onDone: finish,
      onError: (Object error, StackTrace stackTrace) => finish(),
      cancelOnError: true,
    );
    if (sendHeaders) {
      socket.add(
        utf8.encode(
          'HTTP/1.1 $status Test\r\n'
          'Content-Type: image/jpeg\r\n'
          'ETag: "original"\r\n'
          'Cache-Control: max-age=120\r\n'
          'Transfer-Encoding: chunked\r\n\r\n',
        ),
      );
    }
    if (drip) {
      timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
        socket.add(utf8.encode('1\r\nx\r\n'));
      });
      timers.add(timer);
    }
    started.putIfAbsent(path, Completer<void>.new).complete();
  }

  Future<void> respond(HttpRequest request) async {
    request.response.headers
      ..contentType = ContentType('image', 'jpeg')
      ..set(HttpHeaders.etagHeader, '"original"')
      ..set(HttpHeaders.cacheControlHeader, 'max-age=120');
    request.response.contentLength = 3;
    request.response.add([1, 2, 3]);
    await request.response.close();
  }

  Future<void> close() async {
    for (final timer in timers) {
      timer.cancel();
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late PathProviderPlatform previousPaths;
  late HttpOverrides? previousOverrides;
  late _ImageServer server;
  final services = <CoverImageFileService>[];
  final managers = <CacheManager>[];

  CoverImageFileService service({
    Duration idle = const Duration(milliseconds: 300),
    Duration total = const Duration(seconds: 3),
  }) {
    final result = CoverImageFileService(
      idleTimeout: idle,
      totalTimeout: total,
    );
    services.add(result);
    return result;
  }

  CacheManager manager(FileService fileService, String key) {
    final result = CacheManager(
      Config(
        key,
        repo: JsonCacheInfoRepository.withFile(
          File('${temporary.path}/$key.json'),
        ),
        fileService: fileService,
      ),
    );
    managers.add(result);
    return result;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('kira-cover-cache-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temporary.path);
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _LocalNetwork();
    server = _ImageServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
  });

  tearDown(() async {
    for (final value in services) {
      value.close();
    }
    for (final value in managers) {
      await value.dispose();
    }
    services.clear();
    managers.clear();
    await server.close();
    HttpOverrides.global = previousOverrides;
    PathProviderPlatform.instance = previousPaths;
    await temporary.delete(recursive: true);
  });

  test('normal response preserves metadata and pooled connection', () async {
    server.handler = server.respond;
    final fetcher = service(total: const Duration(milliseconds: 500));
    final first = await fetcher.get(server.url('/first'));
    expect(first.statusCode, 200);
    expect(first.contentLength, 3);
    expect(first.eTag, '"original"');
    expect(first.fileExtension, '.jpg');
    expect(
      first.validTill.difference(DateTime.now()).inSeconds,
      inInclusiveRange(118, 120),
    );
    expect(await first.content.expand((chunk) => chunk).toList(), [1, 2, 3]);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final second = await fetcher.get(server.url('/second'));
    await second.content.drain<void>();
    expect(server.remotePorts[0], server.remotePorts[1]);
  });

  for (final sendHeaders in [false, true]) {
    test(
      'stalled ${sendHeaders ? 'body' : 'headers'} cancels socket',
      () async {
        server.handler = (request) =>
            server.stall(request, sendHeaders: sendHeaders);
        final fetcher = service();
        final request = () async {
          final response = await fetcher.get(server.url('/idle'));
          await response.content.drain<void>();
        }();
        await expectLater(
          request,
          throwsA(
            isA<DioException>().having(
              (e) => e.type,
              'type',
              DioExceptionType.receiveTimeout,
            ),
          ),
        );
        await server.waitForDisconnect('/idle');
      },
    );
  }

  test('total deadline cancels a body that keeps producing chunks', () async {
    server.handler = (request) => server.stall(request, drip: true);
    final fetcher = service(total: const Duration(milliseconds: 900));
    final response = await fetcher.get(server.url('/drip'));
    await expectLater(
      response.content.drain<void>(),
      throwsA(isA<TimeoutException>()),
    );
    await server.waitForDisconnect('/drip');
  });

  test(
    'cancelling a consumer waiting for the first chunk closes the socket',
    () async {
      server.handler = server.stall;
      final response = await service().get(server.url('/cancel'));
      final subscription = response.content.listen((_) {});
      await subscription.cancel();
      await server.waitForDisconnect('/cancel');
    },
  );

  for (final status in [404]) {
    test('$status body is released even when content is never read', () async {
      server.handler = (request) => server.stall(request, status: status);
      final response = await service().get(server.url('/status'));
      expect(response.statusCode, status);
      expect(response.eTag, '"original"');
      await server.waitForDisconnect('/status');
    });
  }

  test(
    '304 leaves no deadline and permits reuse without reading content',
    () async {
      server.handler = (request) async {
        if (request.uri.path == '/304') {
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(HttpHeaders.etagHeader, '"original"');
          await request.response.close();
        } else {
          await server.respond(request);
        }
      };
      final fetcher = service(total: const Duration(milliseconds: 500));
      final response = await fetcher.get(server.url('/304'));
      expect(response.statusCode, HttpStatus.notModified);
      expect(response.eTag, '"original"');
      // A legitimate 304 has no body. Its idle pooled connection is reusable,
      // rather than being forcibly closed by a forgotten deadline timer.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final next = await fetcher.get(server.url('/fast'));
      expect(await next.content.expand((chunk) => chunk).toList(), [1, 2, 3]);
      expect(server.remotePorts[0], server.remotePorts[1]);
    },
  );

  test('a stalled image releases its queue slot for the next image', () async {
    server.handler = (request) => request.uri.path == '/slow'
        ? server.stall(request)
        : server.respond(request);
    final fetcher = service()..concurrentFetches = 1;
    final cache = manager(fetcher, 'queue');
    final slow = cache.getSingleFile(server.url('/slow'));
    final slowFailure = expectLater(slow, throwsA(isA<DioException>()));
    await server.waitForStart('/slow');
    final fast = cache.getSingleFile(server.url('/fast'));
    await slowFailure;
    final file = await fast.timeout(const Duration(seconds: 2));
    expect(await file.readAsBytes(), [1, 2, 3]);
    await server.waitForDisconnect('/slow');
  });

  test(
    'existing default-cache files survive a manager restart without downloading',
    () async {
      server.handler = server.respond;
      final old = manager(service(), DefaultCacheManager.key);
      final url = server.url('/cached');
      final file = await old.putFile(
        url,
        Uint8List.fromList([7, 8, 9]),
        maxAge: const Duration(hours: 1),
      );
      await old.dispose();
      managers.remove(old);
      final updated = manager(service(), DefaultCacheManager.key);
      final restored = await updated.getSingleFile(url);
      expect(restored.path, file.path);
      expect(await restored.readAsBytes(), [7, 8, 9]);
      expect(server.requests, isEmpty);
    },
  );

  test(
    'conditional 304 keeps the original file and refreshes its expiry',
    () async {
      server.handler = (request) async {
        if (request.headers.value(HttpHeaders.ifNoneMatchHeader) ==
            '"original"') {
          request.response.statusCode = HttpStatus.notModified;
          request.response.headers.set(
            HttpHeaders.cacheControlHeader,
            'max-age=120',
          );
          await request.response.close();
        } else {
          request.response.headers
            ..set(HttpHeaders.etagHeader, '"original"')
            ..set(HttpHeaders.cacheControlHeader, 'max-age=0')
            ..contentType = ContentType('image', 'jpeg');
          request.response.add([4, 5, 6]);
          await request.response.close();
        }
      };
      final cache = manager(service(), 'conditional');
      final url = server.url('/revalidate');
      final first = await cache.getSingleFile(url);
      final second = await cache.getSingleFile(url);
      expect(await second.readAsBytes(), [4, 5, 6]);
      expect(second.path, first.path);
      expect(server.requests, hasLength(2));
      expect(
        (await cache.getFileFromCache(url))!.validTill.isAfter(DateTime.now()),
        isTrue,
      );
    },
  );
}
