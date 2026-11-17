// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_appearance/settings_appearance_view.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/appearance/chat_appearance.dart';
import 'package:fluffychat/utils/appearance/chat_appearance_scope.dart';
import 'package:fluffychat/utils/appearance/wallpaper_ingest.dart';
import 'package:fluffychat/utils/appearance/wallpaper_store.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/oklch.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum AppearanceScope { all, room }

class SettingsAppearance extends StatefulWidget {
  const SettingsAppearance({this.roomId, super.key});

  final String? roomId;

  @override
  SettingsAppearanceController createState() => SettingsAppearanceController();
}

class SettingsAppearanceController extends State<SettingsAppearance> {
  /// Test seams: where the custom photo is stored and how it is picked.
  @visibleForTesting
  static LocalWallpaperStore? storeOverride;
  @visibleForTesting
  static Future<Uint8List?> Function(BuildContext context)? pickPhotoOverride;

  static const minFontSize = 12;
  static const maxFontSize = 30;
  static const baseFontSize = 16;

  static List<Color> accentSwatches(Color? system) => [
    ?system,
    AppConfig.chatColor,
    ...Colors.primaries,
  ].where((color) => accentHueOf(color) != null).toList();

  static int? checkedSwatch(List<Color> swatches, int currentHue) {
    final index = swatches.indexWhere(
      (color) => accentHueOf(color)?.toInt() == currentHue,
    );
    return index < 0 ? null : index;
  }

  late AppearanceScope scope;
  RoomAppearance? _roomOverride;
  bool _hasRoomOverride = false;
  StreamSubscription<SyncUpdate>? _sync;
  bool _closing = false;

  LocalWallpaperStore get store => storeOverride ?? LocalWallpaperStore();

  Room? get room {
    final id = widget.roomId;
    if (id == null) return null;
    return Matrix.of(context).client.getRoomById(id);
  }

  RoomAppearance? get roomAppearance {
    if (_hasRoomOverride) return _roomOverride;
    final room = this.room;
    return room == null ? null : readRoomAppearance(room);
  }

  GlobalAppearance get global => readGlobalAppearance();

  ResolvedAppearance get resolved => resolveAppearance(
    global: global,
    room: scope == AppearanceScope.room ? roomAppearance : null,
  );

  @override
  void initState() {
    super.initState();
    scope = widget.roomId == null ? AppearanceScope.all : AppearanceScope.room;
    final roomId = widget.roomId;
    if (roomId == null) return;
    _sync = Matrix.of(context).client.onSync.stream
        .where(
          (update) =>
              update.rooms?.join?[roomId]?.accountData?.any(
                (event) => event.type == RoomAppearance.type,
              ) ??
              false,
        )
        .listen((_) {
          if (!mounted) return;
          setState(() => _hasRoomOverride = false);
        });
  }

  @override
  void dispose() {
    unawaited(_sync?.cancel());
    super.dispose();
  }

  void closeIfRoomGone() {
    if (_closing || widget.roomId == null || room != null) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(Navigator.of(context).maybePop());
    });
  }

  void setScope(AppearanceScope value) => setState(() => scope = value);

  ThemeMode get currentTheme => ThemeController.of(context).themeMode;

  void switchTheme(ThemeMode mode) {
    ThemeController.of(context).setThemeMode(mode);
    setState(() {});
  }

  Future<void> _writeRoom(RoomAppearance? next) async {
    final id = widget.roomId;
    final client = Matrix.of(context).client;
    final userId = client.userID;
    if (id == null || userId == null || room == null) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.setAccountDataPerRoom(
        userId,
        id,
        RoomAppearance.type,
        next?.toContent() ?? <String, Object?>{},
      ),
    );
    if (!mounted || result.error != null) return;
    setState(() {
      _roomOverride = next;
      _hasRoomOverride = true;
    });
  }

  RoomAppearance get _currentRoom => roomAppearance ?? const RoomAppearance();

  Future<void> setAccentHue(int hue) async {
    if (scope == AppearanceScope.room) {
      return _writeRoom(_currentRoom.copyWith(accentHue: hue));
    }
    await ThemeController.of(context).setAccentHue(hue);
    if (mounted) setState(() {});
  }

  Future<void> setChatColor(Color color) async {
    final hue = accentHueOf(color);
    if (hue == null) return;
    await setAccentHue(hue.toInt());
  }

  Future<void> setBubbleCorners(BubbleCorners corners) async {
    if (scope == AppearanceScope.room) {
      return _writeRoom(_currentRoom.copyWith(corners: corners));
    }
    await AppSettings.bubbleCorners.setItem(corners.name);
    if (mounted) setState(() {});
  }

  Future<void> setWallpaperPreset(String id) async {
    if (!isWallpaperPresetId(id)) return;
    if (scope == AppearanceScope.room) {
      return _writeRoom(_currentRoom.copyWith(preset: id));
    }
    await removeImages();
    await AppSettings.chatWallpaperPreset.setItem(id);
    if (mounted) setState(() {});
  }

  Future<void> useGlobalSettings() => _writeRoom(null);

  bool get hasImageWallpaper =>
      AppSettings.chatWallpaperLocal.value ||
      Matrix.of(context).client.applicationAccountConfig.wallpaperUrl != null;

  Future<void> removeImages() async {
    await store.clear();
    await AppSettings.chatWallpaperLocal.setItem(false);
    if (!mounted) return;
    final client = Matrix.of(context).client;
    if (client.applicationAccountConfig.wallpaperUrl == null) return;
    await client.setApplicationAccountConfig(
      const ApplicationAccountConfig(wallpaperUrl: null, wallpaperBlur: null),
    );
  }

  Future<void> removeWallpaper() async {
    await showFutureLoadingDialog(context: context, future: removeImages);
    if (mounted) setState(() {});
  }

  Future<Uint8List?> _pickPhoto() async {
    final custom = pickPhotoOverride;
    if (custom != null) return custom(context);
    final picked = await selectFiles(context, type: FileType.image);
    final file = picked.firstOrNull;
    if (file == null) return null;
    final length = await file.length();
    if (length > WallpaperIngest.maxInputBytes) {
      throw const WallpaperRejected(WallpaperRejection.tooLarge);
    }
    return file.readAsBytes();
  }

  Future<void> pickCustomWallpaper() async {
    if (!LocalWallpaperStore.supported || scope != AppearanceScope.all) return;
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Uint8List? bytes;
    try {
      bytes = await _pickPhoto();
    } on WallpaperRejected {
      messenger.showSnackBar(SnackBar(content: Text(l10n.wallpaperTooLarge)));
      return;
    }
    if (bytes == null || !mounted) return;
    try {
      final processed = await WallpaperIngest.process(bytes);
      await store.save(processed);
      await AppSettings.chatWallpaperLocal.setItem(true);
    } on WallpaperRejected catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.reason == WallpaperRejection.notAnImage
                ? l10n.wallpaperNotAnImage
                : l10n.wallpaperTooLarge,
          ),
        ),
      );
      return;
    }
    if (mounted) setState(() {});
  }

  double get wallpaperOpacity =>
      _wallpaperOpacity ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperOpacity ??
      0.5;
  double? _wallpaperOpacity;

  Future<void> saveWallpaperOpacity(double opacity) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperOpacity: opacity),
      ),
    );
    if (result.isValue || !mounted) return;
    setState(() {
      _wallpaperOpacity = client.applicationAccountConfig.wallpaperOpacity;
    });
  }

  void updateWallpaperOpacity(double opacity) =>
      setState(() => _wallpaperOpacity = opacity);

  double get wallpaperBlur =>
      _wallpaperBlur ??
      Matrix.of(context).client.applicationAccountConfig.wallpaperBlur ??
      0.5;
  double? _wallpaperBlur;

  Future<void> saveWallpaperBlur(double blur) async {
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => client.updateApplicationAccountConfig(
        ApplicationAccountConfig(wallpaperBlur: blur),
      ),
    );
    if (result.isValue || !mounted) return;
    setState(() {
      _wallpaperBlur = client.applicationAccountConfig.wallpaperBlur;
    });
  }

  void updateWallpaperBlur(double blur) =>
      setState(() => _wallpaperBlur = blur);

  int get fontSize => (AppSettings.fontSizeFactor.value * baseFontSize)
      .round()
      .clamp(minFontSize, maxFontSize);

  Future<void> changeFontSize(int sp) async {
    final clamped = sp.clamp(minFontSize, maxFontSize);
    await AppSettings.fontSizeFactor.setItem(clamped / baseFontSize);
    if (mounted) setState(() {});
  }

  double get currentAccentHue => resolved.accentHue;

  @override
  Widget build(BuildContext context) {
    closeIfRoomGone();
    return SettingsAppearanceView(this);
  }
}
