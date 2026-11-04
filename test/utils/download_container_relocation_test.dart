import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/comic.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late Directory oldRoot;
  late Directory newRoot;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sandbox = await Directory.systemTemp.createTemp('kira_container_');
    oldRoot = Directory(
      p.join(sandbox.path, 'old-container', 'comic_downloads'),
    );
    newRoot = Directory(
      p.join(sandbox.path, 'new-container', 'comic_downloads'),
    );
  });

  tearDown(() async {
    await sandbox.delete(recursive: true);
  });

  Future<void> seed({String chapterParent = 'chapter'}) async {
    final chapter = Directory(p.join(oldRoot.path, 'comic', 'chapter'));
    await chapter.create(recursive: true);
    await File(p.join(chapter.path, '000.jpg')).writeAsBytes([1, 2, 3]);
    final cover = p.join(oldRoot.path, 'comic', 'cover.jpg');
    await File(cover).writeAsBytes([4, 5, 6]);
    await File(p.join(chapter.path, 'chapter.json')).writeAsString(
      jsonEncode(
        ChapterDetail(
          uuid: 'chapter',
          index: 1,
          name: '离线章节',
          contents: [p.join(oldRoot.path, 'comic', chapterParent, '000.jpg')],
        ).toDownloadJson(),
      ),
    );
    await File(p.join(oldRoot.path, 'comic', 'comic.json')).writeAsString(
      jsonEncode(
        LocalComicInfo(
          comic: Comic(name: '离线漫画', pathWord: 'comic', cover: cover),
          coverPath: cover,
          updatedAt: DateTime(2026),
        ).toJson(),
      ),
    );
    await File(p.join(oldRoot.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'comics': {
          'comic': {
            'chapter': DownloadedChapterSummary(
              chapterUuid: 'chapter',
              chapterName: '离线章节',
              pageCount: 1,
              savedAt: DateTime(2026),
            ).toJson(),
          },
        },
      }),
    );
    await newRoot.parent.create(recursive: true);
    await oldRoot.rename(newRoot.path);
  }

  test('offline pages and cover survive an app container relocation', () async {
    await seed();
    final manager = DownloadManager.forTesting(rootDirectory: newRoot);
    addTearDown(manager.dispose);
    await manager.init();

    final detail = await manager.getDownloadedChapterDetail('comic', 'chapter');
    expect(detail, isNotNull);
    expect(detail!.contents, [
      p.join(newRoot.path, 'comic', 'chapter', '000.jpg'),
    ]);
    expect(manager.isDownloaded('comic', 'chapter'), isTrue);
    final info = manager.getLocalComicInfo('comic')!;
    expect(info.coverPath, p.join(newRoot.path, 'comic', 'cover.jpg'));
    expect(info.comic.cover, info.coverPath);
    expect(await File(detail.contents.single).readAsBytes(), [1, 2, 3]);
  });

  test(
    'does not substitute a same-named page from a different chapter',
    () async {
      await seed(chapterParent: 'other-chapter');
      final manager = DownloadManager.forTesting(rootDirectory: newRoot);
      addTearDown(manager.dispose);
      await manager.init();

      expect(
        await manager.getDownloadedChapterDetail('comic', 'chapter'),
        isNull,
      );
      expect(manager.isDownloaded('comic', 'chapter'), isFalse);
    },
  );
}
