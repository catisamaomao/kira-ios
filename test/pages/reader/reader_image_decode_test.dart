import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/reader_page.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

class _ReaderApi extends Fake implements ApiClient {
  _ReaderApi(ChapterDetail chapter) : manga = _ReaderMangaApi(chapter);

  @override
  final MangaApi manga;
}

class _ReaderMangaApi extends Fake implements MangaApi {
  _ReaderMangaApi(this.chapter);

  final ChapterDetail chapter;

  @override
  Future<ChapterDetail> getChapterDetail(
    String pathWord,
    String chapterUuid, {
    bool forceRefresh = false,
  }) async => chapter;
}

Future<ImageInfo> _decode(WidgetTester tester, ImageProvider provider) async {
  final completed = Completer<ImageInfo>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      completed.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      completed.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  for (var attempt = 0; attempt < 100 && !completed.isCompleted; attempt++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  if (!completed.isCompleted) {
    stream.removeListener(listener);
    fail('Image did not decode');
  }
  return completed.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDirectory;
  late File fixture;
  late Uint8List fixtureBytes;
  late ApiClient originalApi;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'kira-reader-decode-',
    );
    fixture = File('${tempDirectory.path}/page.png');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 800, 1200),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(800, 1200);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    fixtureBytes = bytes!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    await fixture.writeAsBytes(fixtureBytes);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => tempDirectory.path,
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tempDirectory.delete(recursive: true);
  });

  setUp(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({
      'reader_keep_screen_on': false,
      'reader_volume_key': false,
      'image_retry_count': 0,
    });
    setupSecureCredentialStoreForTest();
    BookmarkStore().debugReset();
    originalApi = ApiClient();
    UserManager().reader.resetPrefsCache();
    await UserManager().reader.initFromPrefs(
      await SharedPreferences.getInstance(),
    );
    await UserManager().setCommentPreload(false);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  tearDown(() async {
    await ReadingHistory.flush();
    BookmarkStore().debugReset();
    ApiClient.setTestInstance(originalApi);
    teardownSecureCredentialStoreForTest();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  Future<void> openReader(WidgetTester tester, int direction) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    ApiClient.setTestInstance(
      _ReaderApi(
        ChapterDetail(
          uuid: 'chapter',
          index: 1,
          name: '图片解码测试',
          prev: 'previous',
          next: 'next',
          contents: [fixture.path],
          isDownloaded: true,
        ),
      ),
    );
    await UserManager().setReaderMode(0);
    await UserManager().setReaderScrollDirection(direction);
    await UserManager().setReaderContinuousReading(false);
    await tester.pumpWidget(
      wrapWithApp(
        const ReaderPage(
          pathWord: 'reader-decode',
          comicName: '测试漫画',
          group: 'default',
          chapterUuid: 'chapter',
          chapterName: '图片解码测试',
        ),
        wrapInScaffold: false,
      ),
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      if (find.byType(Image).evaluate().isNotEmpty) return;
    }
    fail('Reader image was not built');
  }

  for (final direction in [0, 2]) {
    final horizontal = direction == 0;
    testWidgets(
      'local ratio lookup does not decode a second full-size image, direction $direction',
      (tester) async {
        await openReader(tester, direction);
        final imageWidget = tester
            .widgetList<Image>(find.byType(Image))
            .firstWhere((image) => image.image is ResizeImage);
        final provider = imageWidget.image;
        final info = await _decode(tester, provider);
        expect(info.image.width / info.image.height, closeTo(2 / 3, 0.002));
        expect(
          horizontal ? info.image.height : info.image.width,
          horizontal ? 800 : 640,
        );
        info.dispose();
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        final rawKey = await FileImage(
          fixture,
        ).obtainKey(ImageConfiguration.empty);
        expect(
          PaintingBinding.instance.imageCache.statusForKey(rawKey).untracked,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
}
