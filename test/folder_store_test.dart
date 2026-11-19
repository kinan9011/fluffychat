// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;
import 'package:matrix/matrix.dart';
import 'package:odango/utils/chat_list/folder_store.dart';

import 'utils/test_client.dart';

Map<String, Object?> doc(List<Object?> folders, {Object? version = 1}) => {
  'version': version,
  'folders': folders,
};

Map<String, Object?> folder({
  Object? id = 'k3x9a2b7',
  Object? name = 'Work',
  Object? types,
  Object? rooms,
  Object? excludeMuted,
  Object? excludeRead,
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'name': name,
  'types': ?types,
  'rooms': ?rooms,
  'exclude_muted': ?excludeMuted,
  'exclude_read': ?excludeRead,
  ...extra,
};

String roomId(int i) => '!r$i:example.org';

void main() {
  group('FolderStore.parse', () {
    test('a valid document keeps every field', () {
      final parsed = FolderStore.parse({
        'version': 1,
        'folders': [
          {
            'id': 'k3x9a2b7',
            'name': 'Work',
            'types': ['group'],
            'rooms': ['!abc:example.org', '!def:matrix.org'],
            'exclude_muted': true,
            'exclude_read': false,
          },
          {
            'id': 'm81qq0zz',
            'name': 'Family',
            'types': <Object?>[],
            'rooms': ['!fam:example.org'],
          },
        ],
      });
      expect(parsed.readOnly, isFalse);
      expect(parsed.folders, hasLength(2));
      final work = parsed.folders.first;
      expect(work.id, 'k3x9a2b7');
      expect(work.name, 'Work');
      expect(work.types, {FolderChatType.group});
      expect(work.rooms, ['!abc:example.org', '!def:matrix.org']);
      expect(work.excludeMuted, isTrue);
      expect(work.excludeRead, isFalse);
      final family = parsed.folders.last;
      expect(family.types, isEmpty);
      expect(family.rooms, ['!fam:example.org']);
      expect(family.excludeMuted, isFalse);
    });

    test('absent or cleared account data is empty and writable', () {
      for (final content in <Object?>[null, <String, Object?>{}]) {
        final parsed = FolderStore.parse(content);
        expect(parsed.folders, isEmpty);
        expect(parsed.readOnly, isFalse);
        expect(parsed.unreadable, isFalse);
      }
    });

    test('present content that is not a map is unreadable and read-only', () {
      for (final content in <Object?>[<Object?>[], 'x', 5, true]) {
        final parsed = FolderStore.parse(content);
        expect(parsed.folders, isEmpty);
        expect(parsed.readOnly, isTrue);
        expect(parsed.unreadable, isTrue);
      }
    });

    test('a bad version is unreadable and read-only, never writable', () {
      for (final version in <Object?>['1', 1.0, 0, -3, null]) {
        final parsed = FolderStore.parse(doc([folder()], version: version));
        expect(parsed.folders, isEmpty, reason: '$version');
        expect(parsed.readOnly, isTrue, reason: '$version');
        expect(parsed.unreadable, isTrue, reason: '$version');
      }
      final newer = FolderStore.parse(doc([folder()], version: 2));
      expect(newer.folders, isEmpty);
      expect(newer.readOnly, isTrue);
      expect(newer.unreadable, isFalse);
    });

    test('folders must be a list, otherwise unreadable and read-only', () {
      for (final content in <Map<String, Object?>>[
        {'version': 1, 'folders': 'x'},
        {'version': 1},
      ]) {
        final parsed = FolderStore.parse(content);
        expect(parsed.folders, isEmpty);
        expect(parsed.readOnly, isTrue);
        expect(parsed.unreadable, isTrue);
      }
    });

    test(
      'at most 30 folders are shown, and the document is then read-only',
      () {
        final folders = [
          for (var i = 0; i < 31; i++) folder(id: 'f$i', name: 'F$i'),
        ];
        final parsed = FolderStore.parse(doc(folders));
        expect(parsed.folders, hasLength(30));
        expect(parsed.folders.last.id, 'f29');
        expect(parsed.readOnly, isTrue);
        expect(
          FolderStore.parse(doc(folders.take(30).toList())).readOnly,
          isFalse,
        );
      },
    );

    test('invalid ids are skipped, duplicates keep the first', () {
      final parsed = FolderStore.parse(
        doc([
          folder(id: 'A B', name: 'bad'),
          folder(id: 'ok-1_', name: 'First'),
          folder(id: 'ok-1_', name: 'Second'),
          folder(id: 5, name: 'num'),
          folder(id: 'x' * 33, name: 'long'),
          'not a map',
          null,
        ]),
      );
      expect(parsed.folders.map((f) => f.name), ['First']);
    });

    test('names lose control and bidi characters and are trimmed', () {
      final parsed = FolderStore.parse(
        doc([folder(name: '  Work\u202E\u0007\u200F  ')]),
      );
      expect(parsed.folders.single.name, 'Work');
    });

    test('names are cut to 64 grapheme clusters', () {
      const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      final parsed = FolderStore.parse(doc([folder(name: family * 100)]));
      expect(parsed.folders.single.name.characters.length, 64);
      expect(parsed.folders.single.name, family * 64);
    });

    test(
      'line separators, Arabic letter mark and zero-width characters go',
      () {
        final parsed = FolderStore.parse(
          doc([
            folder(
              name:
                  'A\u2028B\u2029C\u061CD\u200BE\u2060F\u2064G\uFEFFH\u180EI'
                  '\u{E0067}J',
            ),
          ]),
        );
        expect(parsed.folders.single.name, 'ABCDEFGHIJ');
      },
    );

    test('joiners that emoji and Persian need are kept', () {
      expect(FolderStore.sanitizeName('a\u200Db\u200Cc'), 'a\u200Db\u200Cc');
    });

    test(
      'a combining-mark pile-up cluster is dropped, the name stays short',
      () {
        final zalgo = 'a${'\u0301' * 100}';
        expect(FolderStore.sanitizeName('Work$zalgo'), 'Work');
        final many = FolderStore.sanitizeName('x' * 5 + zalgo * 64);
        expect(many, 'xxxxx');
        expect(
          FolderStore.sanitizeName('a\u0301\u0302\u0303' * 100).length,
          lessThanOrEqualTo(
            FolderStore.maxNameLength * FolderStore.maxClusterUnits,
          ),
        );
      },
    );

    test('a name that is empty after cleaning skips the folder', () {
      final parsed = FolderStore.parse(
        doc([folder(name: ' \u202E\u0007 '), folder(id: 'b', name: 5)]),
      );
      expect(parsed.folders, isEmpty);
    });

    test('types keep only known values once', () {
      final parsed = FolderStore.parse(
        doc([
          folder(types: ['dm', 'x', 'dm', 'bot', 5]),
        ]),
      );
      expect(parsed.folders.single.types, {FolderChatType.dm});
      expect(
        FolderStore.parse(doc([folder(types: 'dm')])).folders.single.types,
        isEmpty,
      );
    });

    test('rooms keep 500 valid ids and drop the rest', () {
      final parsed = FolderStore.parse(
        doc([
          folder(
            rooms: [
              'not-a-room',
              5,
              '!no colon',
              for (var i = 0; i < 600; i++) roomId(i),
              roomId(0),
            ],
          ),
        ]),
      );
      final rooms = parsed.folders.single.rooms;
      expect(rooms, hasLength(500));
      expect(rooms.first, roomId(0));
      expect(rooms.last, roomId(499));
      expect(rooms, isNot(contains('not-a-room')));
      expect(parsed.readOnly, isTrue);
    });

    test('a folder with exactly 500 rooms stays writable', () {
      final parsed = FolderStore.parse(
        doc([
          folder(rooms: [for (var i = 0; i < 500; i++) roomId(i)]),
        ]),
      );
      expect(parsed.folders.single.rooms, hasLength(500));
      expect(parsed.readOnly, isFalse);
    });

    test('room ids with bidi or invisible characters are dropped', () {
      final parsed = FolderStore.parse(
        doc([
          folder(
            rooms: [
              '!ab\u202Ec:example.org',
              '!ab\u200Bc:example.org',
              '!abc:exam\u061Cple.org',
              '!abc:example.org',
            ],
          ),
        ]),
      );
      expect(parsed.folders.single.rooms, ['!abc:example.org']);
    });

    test('room version 12 ids (no server part) are kept', () {
      final v12 = '!${'a1_-' * 10}abc';
      final parsed = FolderStore.parse(
        doc([
          folder(rooms: [v12, '!${'a' * 42}', '!${'a' * 44}', roomId(1)]),
        ]),
      );
      expect(parsed.folders.single.rooms, [v12, roomId(1)]);
    });

    test('flags accept only real booleans', () {
      final parsed = FolderStore.parse(
        doc([folder(excludeMuted: 'yes', excludeRead: 1)]),
      );
      expect(parsed.folders.single.excludeMuted, isFalse);
      expect(parsed.folders.single.excludeRead, isFalse);
    });

    test('unknown fields are ignored and never written back', () {
      final parsed = FolderStore.parse(
        doc([
          folder(extra: {'secret': 'x', 'color': 'red'}),
        ]),
      );
      final json = parsed.folders.single.toJson();
      expect(json.keys, [
        'id',
        'name',
        'types',
        'rooms',
        'exclude_muted',
        'exclude_read',
      ]);
    });

    test(
      'a document over 64 KiB is unreadable, read-only and logs no content',
      () {
        Logs().outputEvents.clear();
        final big = doc([
          folder(
            rooms: [for (var i = 0; i < 400; i++) '!$i${'x' * 200}:y.org'],
          ),
          for (var i = 0; i < 29; i++)
            folder(
              id: 'f$i',
              name: 'F$i',
              rooms: [for (var j = 0; j < 12; j++) '!$j${'x' * 200}:y.org'],
            ),
        ]);
        expect(utf8.encode(jsonEncode(big)).length, greaterThan(65536));
        final parsed = FolderStore.parse(big);
        expect(parsed.folders, isEmpty);
        expect(parsed.readOnly, isTrue);
        expect(parsed.unreadable, isTrue);
        expect(
          Logs().outputEvents.map((e) => e.title),
          contains('[Folders] ignored: too large'),
        );
      },
    );

    test('a document just below the cap still parses', () {
      final ok = doc([
        folder(rooms: [for (var i = 0; i < 100; i++) '!$i${'x' * 100}:y.org']),
      ]);
      expect(utf8.encode(jsonEncode(ok)).length, lessThan(65536));
      expect(FolderStore.parse(ok).folders, hasLength(1));
    });

    test('toJson then parse round-trips', () {
      final parsed = FolderStore.parse(
        doc([
          folder(
            types: ['dm', 'group'],
            rooms: [roomId(1), roomId(2)],
            excludeMuted: true,
            excludeRead: true,
          ),
          folder(id: 'b', name: 'Other'),
        ]),
      );
      final again = FolderStore.parse(parsed.toJson());
      expect(jsonEncode(again.toJson()), jsonEncode(parsed.toJson()));
      expect(parsed.toJson()['version'], 1);
    });

    test('the same content map is parsed once', () {
      final content = doc([folder()]);
      expect(
        identical(FolderStore.parse(content), FolderStore.parse(content)),
        isTrue,
      );
    });
  });

  group('FolderStore ids and names', () {
    test('newId is 8 characters of [a-z0-9] and valid', () {
      final ids = {for (var i = 0; i < 50; i++) FolderStore.newId(Random(i))};
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9]{8}$')));
        expect(FolderStore.isValidId(id), isTrue);
      }
      expect(FolderStore.newId(), hasLength(8));
    });

    test('isValidId', () {
      expect(FolderStore.isValidId('a-b_9'), isTrue);
      expect(FolderStore.isValidId(null), isFalse);
      expect(FolderStore.isValidId(''), isFalse);
      expect(FolderStore.isValidId('A'), isFalse);
      expect(FolderStore.isValidId('a b'), isFalse);
    });
  });

  group('FolderStore per client', () {
    late Client a;
    late Client b;
    final apis = <Client, FakeMatrixApi>{};

    setUpAll(() async {
      a = await prepareTestClient(clientName: 'folder client a');
      apis[a] = FakeMatrixApi.currentApi!;
      FakeMatrixApi.client = a;
      b = await prepareTestClient(clientName: 'folder client b');
      apis[b] = FakeMatrixApi.currentApi!;
      FakeMatrixApi.client = b;
      a.accountData[FolderStore.accountDataType] = BasicEvent(
        type: FolderStore.accountDataType,
        content: doc([folder(name: 'Only A')]),
      );
      b.accountData[FolderStore.accountDataType] = BasicEvent(
        type: FolderStore.accountDataType,
        content: doc([folder(id: 'bbbb', name: 'Only B')]),
      );
    });

    String? putPath(Client client) {
      FakeMatrixApi.currentApi = apis[client];
      return FakeMatrixApi.calledEndpoints.keys
          .where(
            (path) =>
                path.endsWith('/account_data/${FolderStore.accountDataType}'),
          )
          .firstOrNull;
    }

    void clearCalls() {
      for (final client in [a, b]) {
        FakeMatrixApi.currentApi = apis[client];
        FakeMatrixApi.calledEndpoints.clear();
      }
    }

    test('of reads only the given client', () {
      expect(FolderStore.of(a).folders.single.name, 'Only A');
      expect(FolderStore.of(b).folders.single.name, 'Only B');
    });

    test('save writes through the client it was given', () async {
      clearCalls();
      await FolderStore.save(a, [UserFolder(id: 'zz', name: 'New')]);
      expect(putPath(b), isNull);
      final path = putPath(a);
      expect(path, isNotNull);
      expect(
        path,
        contains('/user/${Uri.encodeComponent(a.userID!)}/account_data/'),
      );
      final body = jsonDecode(FakeMatrixApi.calledEndpoints[path]!.single);
      expect(body['version'], 1);
      expect(body['folders'].single['name'], 'New');
    });

    test('a newer document is never overwritten', () async {
      final readOnly = await prepareTestClient(clientName: 'folder client c');
      apis[readOnly] = FakeMatrixApi.currentApi!;
      readOnly.accountData[FolderStore.accountDataType] = BasicEvent(
        type: FolderStore.accountDataType,
        content: doc([folder()], version: 2),
      );
      FakeMatrixApi.currentApi = apis[readOnly];
      FakeMatrixApi.calledEndpoints.clear();
      await expectLater(
        FolderStore.save(readOnly, [UserFolder(id: 'zz', name: 'New')]),
        throwsStateError,
      );
      expect(putPath(readOnly), isNull);
    });

    test('more than 30 folders are refused before any request', () async {
      clearCalls();
      await expectLater(
        FolderStore.save(a, [
          for (var i = 0; i < 31; i++) UserFolder(id: 'f$i', name: 'F$i'),
        ]),
        throwsStateError,
      );
      expect(putPath(a), isNull);
    });

    test('invalid folders are refused before any request', () async {
      clearCalls();
      for (final bad in [
        UserFolder(id: 'A B', name: 'x'),
        UserFolder(id: 'ok', name: ' \u202E '),
      ]) {
        await expectLater(FolderStore.save(a, [bad]), throwsStateError);
      }
      expect(putPath(a), isNull);
    });

    UserFolder bigFolder(String id, int count, [int offset = 0]) => UserFolder(
      id: id,
      name: id,
      rooms: [
        for (var i = 0; i < count; i++)
          '!${(offset + i).toString().padLeft(18, 'a')}:matrix.org',
      ],
    );

    test(
      'about 2000 typical room ids exceed the cap and are refused before any request',
      () async {
        clearCalls();
        final folders = [
          for (var i = 0; i < 4; i++) bigFolder('big$i', 500, i * 500),
        ];
        final json = FolderDocument(folders: folders, readOnly: false).toJson();
        expect(utf8.encode(jsonEncode(json)).length, greaterThan(65536));
        expect(FolderStore.parse(json).unreadable, isTrue);
        await expectLater(
          FolderStore.save(a, folders),
          throwsA(isA<FolderTooLargeException>()),
        );
        expect(putPath(a), isNull);
      },
    );

    test('a document just under the cap is still written', () async {
      clearCalls();
      final folders = [
        for (var i = 0; i < 3; i++) bigFolder('big$i', 500, i * 500),
      ];
      final json = FolderDocument(folders: folders, readOnly: false).toJson();
      expect(utf8.encode(jsonEncode(json)).length, lessThan(65536));
      await FolderStore.save(a, folders);
      expect(putPath(a), isNotNull);
    });

    for (final entry in <String, Map<String, Object?>>{
      'over 64 KiB': {
        'version': 1,
        'folders': [
          folder(
            rooms: [for (var i = 0; i < 400; i++) '!$i${'x' * 200}:y.org'],
          ),
          for (var i = 0; i < 29; i++)
            folder(
              id: 'f$i',
              rooms: [for (var j = 0; j < 12; j++) '!$j${'x' * 200}:y.org'],
            ),
        ],
      },
      'a float version': doc([folder()], version: 1.0),
      'folders not a list': {'version': 1, 'folders': 'x'},
      'more than 30 folders': doc([
        for (var i = 0; i < 31; i++) folder(id: 'f$i'),
      ]),
      'more than 500 rooms in a folder': doc([
        folder(rooms: [for (var i = 0; i < 501; i++) roomId(i)]),
      ]),
    }.entries) {
      test(
        'a present but unreadable document (${entry.key}) is never overwritten',
        () async {
          final broken = await prepareTestClient(
            clientName: 'folder client broken ${entry.key}',
          );
          apis[broken] = FakeMatrixApi.currentApi!;
          broken.accountData[FolderStore.accountDataType] = BasicEvent(
            type: FolderStore.accountDataType,
            content: entry.value,
          );
          expect(FolderStore.of(broken).readOnly, isTrue);
          FakeMatrixApi.currentApi = apis[broken];
          FakeMatrixApi.calledEndpoints.clear();
          await expectLater(
            FolderStore.save(broken, [UserFolder(id: 'zz', name: 'New')]),
            throwsStateError,
          );
          expect(putPath(broken), isNull);
        },
      );
    }

    test('save drops bad and duplicate room ids', () async {
      FakeMatrixApi.currentApi = apis[a];
      FakeMatrixApi.calledEndpoints.clear();
      await FolderStore.save(a, [
        UserFolder(
          id: 'zz',
          name: 'Rooms',
          rooms: [
            roomId(1),
            'not a room',
            roomId(1),
            '!x\u202Ey:example.org',
            roomId(2),
          ],
        ),
      ]);
      final body = jsonDecode(
        FakeMatrixApi.calledEndpoints[putPath(a)]!.single,
      );
      expect(body['folders'].single['rooms'], [roomId(1), roomId(2)]);
    });

    test('save keeps a room version 12 id', () async {
      FakeMatrixApi.currentApi = apis[a];
      FakeMatrixApi.calledEndpoints.clear();
      final v12 = '!${'a1_-' * 10}abc';
      await FolderStore.save(a, [
        UserFolder(id: 'zz', name: 'Rooms', rooms: [v12, roomId(1)]),
      ]);
      final body = jsonDecode(
        FakeMatrixApi.calledEndpoints[putPath(a)]!.single,
      );
      expect(body['folders'].single['rooms'], [v12, roomId(1)]);
    });

    test('save cleans the name and caps the rooms', () async {
      FakeMatrixApi.currentApi = apis[a];
      FakeMatrixApi.calledEndpoints.clear();
      await FolderStore.save(a, [
        UserFolder(
          id: 'zz',
          name: '  Hi\u202E  ',
          rooms: [for (var i = 0; i < 600; i++) roomId(i)],
        ),
      ]);
      final body = jsonDecode(
        FakeMatrixApi.calledEndpoints[putPath(a)]!.single,
      );
      expect(body['folders'].single['name'], 'Hi');
      expect(body['folders'].single['rooms'], hasLength(500));
    });
  });
}
