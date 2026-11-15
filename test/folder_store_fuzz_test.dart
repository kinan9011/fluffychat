// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/utils/chat_list/folder_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show StringCharacters;

Object? randomTree(Random random, int depth) {
  final kind = random.nextInt(depth <= 0 ? 6 : 9);
  switch (kind) {
    case 0:
      return null;
    case 1:
      return random.nextBool();
    case 2:
      return random.nextInt(2000) - 1000;
    case 3:
      return random.nextDouble() * 100;
    case 4:
      return randomString(random);
    case 5:
      return randomRoomId(random);
    case 6:
    case 7:
      final length = random.nextInt(depth >= 4 ? 5 : (depth >= 2 ? 12 : 50));
      return [for (var i = 0; i < length; i++) randomTree(random, depth - 1)];
    default:
      final length = random.nextInt(depth >= 4 ? 5 : 12);
      return {
        for (var i = 0; i < length; i++)
          randomKey(random): randomTree(random, depth - 1),
      };
  }
}

String randomString(Random random) {
  final pool = [
    'a',
    'Work',
    '\u0000',
    '\u0007',
    '\u202E',
    '\u2066',
    '\u200F',
    '\u200E',
    '\u061C',
    '\u2028',
    '\u200B',
    '\uFEFF',
    'a${'\u0301' * 40}',
    ' ',
    '\u{1F468}‍\u{1F469}‍\u{1F467}',
    'x' * 40,
    '!',
    ':',
  ];
  final length = random.nextInt(80);
  return [
    for (var i = 0; i < length; i++) pool[random.nextInt(pool.length)],
  ].join();
}

String randomRoomId(Random random) => '!r${random.nextInt(100000)}:example.org';

String randomKey(Random random) {
  const keys = [
    'version',
    'folders',
    'id',
    'name',
    'types',
    'rooms',
    'exclude_muted',
    'exclude_read',
    'x',
  ];
  return keys[random.nextInt(keys.length)];
}

int biased(Random random, int small, int largeBase, int largeSpread) =>
    random.nextInt(40) == 0
    ? largeBase + random.nextInt(largeSpread)
    : random.nextInt(small);

Map<String, Object?> wellFormed(
  Random random, {
  required int folders,
  required int rooms,
}) => {
  'version': 1,
  'folders': [
    for (var f = 0; f < folders; f++)
      {
        'id': 'g$f',
        'name': 'Folder $f ${randomString(random)}',
        'types': ['dm'],
        'rooms': [
          for (var r = 0; r < rooms; r++) '!${f}x$r${'a' * 16}:matrix.org',
        ],
        'exclude_muted': random.nextBool(),
        'exclude_read': random.nextBool(),
      },
  ],
};

Map<String, Object?> randomFolder(Random random) => {
  if (random.nextInt(8) != 0)
    'id': random.nextBool() ? 'f${random.nextInt(40)}' : randomTree(random, 2),
  if (random.nextInt(8) != 0)
    'name': random.nextBool() ? randomString(random) : randomTree(random, 2),
  if (random.nextInt(4) != 0)
    'types': random.nextBool()
        ? ['dm', 'group', 'bot', 'x']
        : randomTree(random, 2),
  if (random.nextInt(4) != 0)
    'rooms': random.nextBool()
        ? [
            for (var i = 0, n = biased(random, 60, 500, 200); i < n; i++)
              randomRoomId(random),
          ]
        : randomTree(random, 3),
  'exclude_muted': randomTree(random, 1),
  'exclude_read': randomTree(random, 1),
};

final unsafe = RegExp(
  '[\u0000-\u001F\u007F-\u009F\u061C\u180E\u200B\u200E\u200F\u2028\u2029'
  '\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF\u{E0000}-\u{E007F}]',
  unicode: true,
);

void check(FolderDocument document) {
  if (document.unreadable) expect(document.readOnly, isTrue);
  expect(document.folders.length, lessThanOrEqualTo(FolderStore.maxFolders));
  final ids = <String>{};
  for (final folder in document.folders) {
    expect(FolderStore.isValidId(folder.id), isTrue);
    expect(ids.add(folder.id), isTrue);
    expect(folder.name, isNotEmpty);
    expect(
      folder.name.characters.length,
      lessThanOrEqualTo(FolderStore.maxNameLength),
    );
    expect(folder.name, isNot(matches(unsafe)));
    for (final cluster in folder.name.characters) {
      expect(cluster.length, lessThanOrEqualTo(FolderStore.maxClusterUnits));
    }
    expect(
      folder.rooms.length,
      lessThanOrEqualTo(FolderStore.maxRoomsPerFolder),
    );
    expect(folder.rooms.toSet().length, folder.rooms.length);
  }
}

void main() {
  test('parse never throws and always respects the caps (2000 cases)', () {
    final random = Random(42);
    var thirtyFolders = 0;
    var fiveHundredRooms = 0;
    for (var i = 0; i < 2000; i++) {
      final root = randomTree(random, 6);
      check(FolderStore.parse(root));
      final folderCount = random.nextInt(8);
      final rooted = i % 100 == 0
          ? wellFormed(random, folders: 30 + random.nextInt(15), rooms: 3)
          : i % 100 == 1
          ? wellFormed(random, folders: 2, rooms: 500 + random.nextInt(200))
          : i % 100 == 2
          ? wellFormed(random, folders: 4, rooms: 500)
          : <String, Object?>{
              'version': random.nextInt(8) == 0 ? randomTree(random, 1) : 1,
              'folders': random.nextInt(8) == 0
                  ? randomTree(random, 4)
                  : [
                      for (var f = 0; f < folderCount; f++)
                        random.nextInt(10) == 0
                            ? randomTree(random, 3)
                            : randomFolder(random),
                    ],
            };
      final document = FolderStore.parse(rooted);
      check(document);
      if (document.folders.length == FolderStore.maxFolders) thirtyFolders++;
      if (document.folders.any(
        (f) => f.rooms.length == FolderStore.maxRoomsPerFolder,
      )) {
        fiveHundredRooms++;
      }
      if (i % 100 == 2) {
        expect(document.unreadable, isTrue, reason: 'over the byte cap');
      }
    }
    expect(thirtyFolders, greaterThan(0), reason: 'the 30 folder cap is hit');
    expect(fiveHundredRooms, greaterThan(0), reason: 'the 500 room cap is hit');
  });
}
