// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

enum SpaceNavigationMode {
  tabs,
  switcher;

  static SpaceNavigationMode fromSetting(String value) =>
      value == 'switcher' ? switcher : tabs;
}

enum FolderKind { all, unread, personal, groups, tag, user }

@immutable
class FolderRef {
  static const all = FolderRef(FolderKind.all);
  static const unread = FolderRef(FolderKind.unread);
  static const personal = FolderRef(FolderKind.personal);
  static const groups = FolderRef(FolderKind.groups);

  static final _userId = RegExp(r'^[a-z0-9_-]{1,32}$');
  static const _userPrefix = 'folder:';
  static const _tagPrefix = 'u.';
  static const _maxTagLength = 255;

  final FolderKind kind;
  final String? value;

  const FolderRef(this.kind, [this.value]);

  String get storageKey => switch (kind) {
    FolderKind.all => 'allChats',
    FolderKind.unread => 'unread',
    FolderKind.personal => 'messages',
    FolderKind.groups => 'groups',
    FolderKind.tag => value ?? 'allChats',
    FolderKind.user => '$_userPrefix$value',
  };

  static FolderRef parse(String? raw) {
    if (raw == null || raw.isEmpty) return all;
    if (raw.startsWith(_tagPrefix) && raw.length <= _maxTagLength) {
      return FolderRef(FolderKind.tag, raw);
    }
    if (raw.startsWith(_userPrefix)) {
      final id = raw.substring(_userPrefix.length);
      return _userId.hasMatch(id) ? FolderRef(FolderKind.user, id) : all;
    }
    return switch (raw) {
      'unread' => unread,
      'messages' => personal,
      'groups' => groups,
      _ => all,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FolderRef && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

@immutable
class ChatListScope {
  final String? spaceId;
  final FolderRef folder;

  const ChatListScope({this.spaceId, this.folder = FolderRef.all});

  @override
  bool operator ==(Object other) =>
      other is ChatListScope &&
      other.spaceId == spaceId &&
      other.folder == folder;

  @override
  int get hashCode => Object.hash(spaceId, folder);
}
