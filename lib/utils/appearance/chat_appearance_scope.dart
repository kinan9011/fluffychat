// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/config/themes.dart';
import 'package:odango/utils/appearance/chat_appearance.dart';

GlobalAppearance readGlobalAppearance() => GlobalAppearance(
  preset: isWallpaperPresetId(AppSettings.chatWallpaperPreset.value)
      ? AppSettings.chatWallpaperPreset.value
      : 'default',
  accentHue: FluffyThemes.accentHue(),
  corners:
      BubbleCorners.byName(AppSettings.bubbleCorners.value) ??
      BubbleCorners.standard,
);

RoomAppearance? readRoomAppearance(Room room) =>
    RoomAppearance.tryParse(room.roomAccountData[RoomAppearance.type]?.content);

ResolvedAppearance resolveRoomAppearance(Room room) => resolveAppearance(
  global: readGlobalAppearance(),
  room: readRoomAppearance(room),
);

/// The appearance of the open chat, for bubbles and the wallpaper.
class ChatAppearanceScope extends InheritedWidget {
  const ChatAppearanceScope({
    required this.appearance,
    required super.child,
    super.key,
  });

  final ResolvedAppearance appearance;

  static ResolvedAppearance? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ChatAppearanceScope>()
      ?.appearance;

  static BubbleCorners cornersOf(BuildContext context) =>
      maybeOf(context)?.corners ?? BubbleCorners.standard;

  @override
  bool updateShouldNotify(ChatAppearanceScope oldWidget) =>
      oldWidget.appearance.preset != appearance.preset ||
      oldWidget.appearance.accentHue != appearance.accentHue ||
      oldWidget.appearance.corners != appearance.corners;
}

/// Provides the [ChatAppearanceScope] of [room] and, when the chat has its own
/// accent, a theme with that accent. Rebuilds when the room account data or a
/// global appearance setting changes.
class ChatAppearanceHost extends StatefulWidget {
  const ChatAppearanceHost({
    required this.room,
    required this.child,
    super.key,
  });

  final Room room;
  final Widget child;

  @override
  State<ChatAppearanceHost> createState() => _ChatAppearanceHostState();
}

class _ChatAppearanceHostState extends State<ChatAppearanceHost> {
  StreamSubscription<SyncUpdate>? _sync;

  static final _settings = [
    AppSettings.chatWallpaperPreset,
    AppSettings.bubbleCorners,
    AppSettings.accentHue,
  ];

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _listen() {
    final roomId = widget.room.id;
    _sync = widget.room.client.onSync.stream
        .where(
          (update) =>
              update.rooms?.join?[roomId]?.accountData?.any(
                (event) => event.type == RoomAppearance.type,
              ) ??
              false,
        )
        .listen((_) => _refresh());
  }

  @override
  void initState() {
    super.initState();
    for (final setting in _settings) {
      setting.listenable.addListener(_refresh);
    }
    _listen();
  }

  @override
  void didUpdateWidget(ChatAppearanceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id == widget.room.id) return;
    unawaited(_sync?.cancel());
    _listen();
  }

  @override
  void dispose() {
    for (final setting in _settings) {
      setting.listenable.removeListener(_refresh);
    }
    unawaited(_sync?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appearance = resolveRoomAppearance(widget.room);
    final roomHue = readRoomAppearance(widget.room)?.accentHue;
    final scoped = ChatAppearanceScope(
      appearance: appearance,
      child: widget.child,
    );
    if (roomHue == null) return scoped;
    return Theme(
      data: FluffyThemes.buildTheme(
        context,
        Theme.of(context).brightness,
        hueOverride: roomHue.toDouble(),
      ),
      child: scoped,
    );
  }
}
