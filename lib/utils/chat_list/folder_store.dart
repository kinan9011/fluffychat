// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:math';

import 'package:fluffychat/utils/matrix_room_id.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum FolderChatType {
  dm,
  group;

  bool matches(Room room) => switch (this) {
    dm => room.isDirectChat,
    group => !room.isDirectChat,
  };
}

@immutable
class UserFolder {
  final String id;
  final String name;
  final Set<FolderChatType> types;
  final List<String> rooms;
  final bool excludeMuted;
  final bool excludeRead;

  UserFolder({
    required this.id,
    required this.name,
    this.types = const {},
    this.rooms = const [],
    this.excludeMuted = false,
    this.excludeRead = false,
  }) : _roomSet = rooms.toSet();

  final Set<String> _roomSet;

  UserFolder copyWith({
    String? name,
    Set<FolderChatType>? types,
    List<String>? rooms,
    bool? excludeMuted,
    bool? excludeRead,
  }) => UserFolder(
    id: id,
    name: name ?? this.name,
    types: types ?? this.types,
    rooms: rooms ?? this.rooms,
    excludeMuted: excludeMuted ?? this.excludeMuted,
    excludeRead: excludeRead ?? this.excludeRead,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'types': [
      for (final type in FolderChatType.values)
        if (types.contains(type)) type.name,
    ],
    'rooms': rooms,
    'exclude_muted': excludeMuted,
    'exclude_read': excludeRead,
  };

  bool matches(Room room) {
    if (!_roomSet.contains(room.id) && !types.any((t) => t.matches(room))) {
      return false;
    }
    if (excludeMuted && room.pushRuleState != PushRuleState.notify) {
      return false;
    }
    return !(excludeRead && !room.isUnreadOrInvited);
  }
}

@immutable
class FolderDocument {
  static const empty = FolderDocument(folders: [], readOnly: false);

  final List<UserFolder> folders;
  final bool readOnly;
  final bool unreadable;

  const FolderDocument({
    required this.folders,
    required this.readOnly,
    this.unreadable = false,
  });

  Map<String, Object?> toJson() => {
    'version': FolderStore.version,
    'folders': [for (final folder in folders) folder.toJson()],
  };
}

class FolderTooLargeException implements Exception {
  const FolderTooLargeException();

  @override
  String toString() => 'Folders are too large to sync';
}

abstract class FolderStore {
  static const accountDataType = 'im.fluffychat.folders';
  static const version = 1;
  static const maxFolders = 30;
  static const maxRoomsPerFolder = 500;
  static const maxNameLength = 64;
  static const maxBytes = 65536;
  static const maxClusterUnits = 16;

  static final _idPattern = RegExp(r'^[a-z0-9_-]{1,32}$');
  static final _unsafeName = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u061C\u180E\u200B\u200E\u200F'
    r'\u2028\u2029\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF'
    r'\u{E0000}-\u{E007F}]',
    unicode: true,
  );
  static const _unreadable = FolderDocument(
    folders: [],
    readOnly: true,
    unreadable: true,
  );
  static final _cache = Expando<FolderDocument>('FolderStore');

  static bool _isRoomId(String id) =>
      isMatrixRoomId(id) && !_unsafeName.hasMatch(id);

  static bool isValidId(String? id) => id != null && _idPattern.hasMatch(id);

  static String sanitizeName(String name) => name
      .replaceAll(_unsafeName, '')
      .trim()
      .characters
      .where((cluster) => cluster.length <= maxClusterUnits)
      .take(maxNameLength)
      .toString();

  static FolderDocument parse(Object? content) {
    if (content == null) return FolderDocument.empty;
    if (content is! Map<String, Object?>) return _unreadable;
    if (content.isEmpty) return FolderDocument.empty;
    final cached = _cache[content];
    if (cached != null) return cached;
    return _cache[content] = _parse(content);
  }

  static bool _fits(Object? json) {
    try {
      return utf8.encode(jsonEncode(json)).length <= maxBytes;
    } catch (_) {
      return false;
    }
  }

  static FolderDocument _parse(Map<String, Object?> content) {
    if (!_fits(content)) {
      Logs().w('[Folders] ignored: too large');
      return _unreadable;
    }
    final docVersion = content['version'];
    if (docVersion is! int || docVersion < 1) return _unreadable;
    if (docVersion > version) {
      return const FolderDocument(folders: [], readOnly: true);
    }
    final rawFolders = content['folders'];
    if (rawFolders is! List) return _unreadable;
    final folders = <UserFolder>[];
    final seen = <String>{};
    var lossy = rawFolders.length > maxFolders;
    for (final raw in rawFolders.take(maxFolders)) {
      lossy |=
          raw is Map &&
          raw['rooms'] is List &&
          (raw['rooms'] as List).length > maxRoomsPerFolder;
      final folder = _parseFolder(raw);
      if (folder == null || !seen.add(folder.id)) continue;
      folders.add(folder);
    }
    return FolderDocument(folders: folders, readOnly: lossy, unreadable: lossy);
  }

  static UserFolder? _parseFolder(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final rawName = raw['name'];
    if (id is! String || !_idPattern.hasMatch(id) || rawName is! String) {
      return null;
    }
    final name = sanitizeName(rawName);
    if (name.isEmpty) return null;
    final rawTypes = raw['types'];
    final rawRooms = raw['rooms'];
    return UserFolder(
      id: id,
      name: name,
      types: rawTypes is List
          ? {
              for (final type in FolderChatType.values)
                if (rawTypes.contains(type.name)) type,
            }
          : const {},
      rooms: rawRooms is List
          ? rawRooms
                .whereType<String>()
                .where(_isRoomId)
                .toSet()
                .take(maxRoomsPerFolder)
                .toList(growable: false)
          : const [],
      excludeMuted: raw['exclude_muted'] == true,
      excludeRead: raw['exclude_read'] == true,
    );
  }

  static FolderDocument of(Client client) =>
      parse(client.accountData[accountDataType]?.content);

  static Future<void> save(Client client, List<UserFolder> folders) async {
    if (of(client).readOnly) {
      throw StateError('Folders were written by a newer version');
    }
    if (folders.length > maxFolders) {
      throw StateError('Too many folders');
    }
    final checked = <UserFolder>[];
    for (final folder in folders) {
      if (!isValidId(folder.id) || sanitizeName(folder.name).isEmpty) {
        throw StateError('Invalid folder');
      }
      checked.add(
        folder.copyWith(
          name: sanitizeName(folder.name),
          rooms: folder.rooms
              .where(_isRoomId)
              .toSet()
              .take(maxRoomsPerFolder)
              .toList(),
        ),
      );
    }
    final json = FolderDocument(folders: checked, readOnly: false).toJson();
    if (!_fits(json)) throw const FolderTooLargeException();
    await client.setAccountData(client.userID!, accountDataType, json);
  }

  static String newId([Random? random]) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = random ?? Random.secure();
    return String.fromCharCodes(
      List.generate(8, (_) => alphabet.codeUnitAt(rng.nextInt(36))),
    );
  }
}
