// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/global_search/search_result_widgets.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/search/search_filter.dart';
import 'package:fluffychat/utils/search/search_kind.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings/settings_segmented.dart';
import 'package:fluffychat/widgets/settings/settings_toggle_row.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

Future<MessageSearchFilter?> showSearchFilterSheet(
  BuildContext context, {
  required MessageSearchFilter initial,
  required List<String> suggestions,
}) => showAdaptiveBottomSheet<MessageSearchFilter>(
  context: context,
  maxHeight: 720,
  builder: (_) => SearchFilterSheet(initial: initial, suggestions: suggestions),
);

class SearchFilterSheet extends StatefulWidget {
  final MessageSearchFilter initial;
  final List<String> suggestions;

  const SearchFilterSheet({
    required this.initial,
    required this.suggestions,
    super.key,
  });

  static const resetKey = ValueKey('search_filter_reset');
  static const applyKey = ValueKey('search_filter_apply');

  @override
  State<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends State<SearchFilterSheet> {
  late MessageSearchFilter draft = widget.initial;

  static const _typeIcons = <SearchType, IconData>{
    SearchType.photos: Icons.image_outlined,
    SearchType.videos: Icons.videocam_outlined,
    SearchType.files: Icons.description_outlined,
    SearchType.links: Icons.link_rounded,
    SearchType.voice: Icons.mic_none_rounded,
    SearchType.polls: Icons.ballot_outlined,
  };

  String _typeLabel(L10n l10n, SearchType type) => switch (type) {
    SearchType.photos => l10n.searchTypePhotos,
    SearchType.videos => l10n.searchTypeVideos,
    SearchType.files => l10n.searchTypeFiles,
    SearchType.links => l10n.searchTypeLinks,
    SearchType.voice => l10n.searchTypeVoice,
    SearchType.polls => l10n.searchTypePolls,
  };

  void _toggleFrom(String id) {
    final next = {...draft.fromIds};
    if (!next.remove(id)) next.add(id);
    setState(() => draft = draft.copyWith(fromIds: next));
  }

  void _toggleType(SearchType type) {
    final next = {...draft.types};
    if (!next.remove(type)) next.add(type);
    setState(() => draft = draft.copyWith(types: next));
  }

  Future<void> _addChat() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const _RoomPickerDialog(),
    );
    if (id == null || !mounted) return;
    setState(() => draft = draft.copyWith(inRoomIds: {...draft.inRoomIds, id}));
  }

  void _removeChat(String id) => setState(
    () => draft = draft.copyWith(inRoomIds: {...draft.inRoomIds}..remove(id)),
  );

  Future<void> _setDate(DatePreset preset) async {
    if (preset != DatePreset.custom) {
      setState(() => draft = draft.copyWith(date: preset, clearCustom: true));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (range == null || !mounted) return;
    final window = MessageSearchFilter.window(range.start, range.end);
    if (window == null) return;
    setState(
      () => draft = draft.copyWith(date: DatePreset.custom, custom: window),
    );
  }

  String _personName(String id) =>
      safeDisplayText(id.localpart ?? id, maxGraphemes: 24);

  String _roomName(String id) {
    final client = Matrix.of(context).client;
    final room = client.getRoomById(id);
    if (room == null) return id;
    return safeDisplayText(
      room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
      maxGraphemes: 24,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final people = {...widget.suggestions, ...draft.fromIds}.toList();
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: insets),
      child: Material(
        color: tokens.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 8, bottom: 4),
                        decoration: BoxDecoration(
                          color: tokens.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          20,
                          4,
                          12,
                          8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.searchFilters,
                                style: TextStyle(
                                  color: tokens.fg,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.close,
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(Icons.close_rounded, color: tokens.fg),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: tokens.surf,
                          borderRadius: BorderRadius.circular(AppRadius.menu),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 8,
                          children: [
                            _Label(l10n.searchFromLabel),
                            Wrap(
                              spacing: 6,
                              children: [
                                SearchChip(
                                  label: l10n.searchAnyone,
                                  selected: draft.fromIds.isEmpty,
                                  icon: Icons.groups_rounded,
                                  onTap: () => setState(
                                    () => draft = draft.copyWith(
                                      fromIds: const {},
                                    ),
                                  ),
                                ),
                                for (final id in people)
                                  SearchChip(
                                    label: _personName(id),
                                    selected: draft.fromIds.contains(id),
                                    leading: Avatar(
                                      name: _personName(id),
                                      size: 26,
                                      colorSeed: id,
                                    ),
                                    onTap: () => _toggleFrom(id),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _Label(l10n.searchInLabel),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final id in draft.inRoomIds)
                                  SearchChip(
                                    label: _roomName(id),
                                    selected: true,
                                    onTap: () => _removeChat(id),
                                    onClose: () => _removeChat(id),
                                  ),
                                SearchChip(
                                  label: l10n.searchAddChat,
                                  selected: false,
                                  icon: Icons.add_rounded,
                                  onTap: _addChat,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _Label(l10n.searchDateLabel),
                            SettingsSegmented<DatePreset>(
                              items: [
                                (DatePreset.any, l10n.searchAny),
                                (DatePreset.today, l10n.today),
                                (DatePreset.week, l10n.searchWeek),
                                (DatePreset.month, l10n.searchMonth),
                                (DatePreset.custom, l10n.custom),
                              ],
                              value: draft.effectiveDate,
                              onChanged: _setDate,
                            ),
                            _Label(l10n.searchTypeLabel),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final type in SearchType.values)
                                  SearchChip(
                                    label: _typeLabel(l10n, type),
                                    icon: _typeIcons[type],
                                    selected: draft.types.contains(type),
                                    onTap: () => _toggleType(type),
                                  ),
                              ],
                            ),
                            Divider(color: tokens.line, height: 24),
                            SettingsToggleRow(
                              title: l10n.searchMentionsMe,
                              value: draft.mentionsMe,
                              onChanged: (value) => setState(
                                () => draft = draft.copyWith(mentionsMe: value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  spacing: 8,
                  children: [
                    TextButton(
                      key: SearchFilterSheet.resetKey,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        backgroundColor: tokens.surf2,
                        foregroundColor: tokens.fg,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () =>
                          setState(() => draft = MessageSearchFilter.none),
                      child: Text(
                        l10n.reset,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        key: SearchFilterSheet.applyKey,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor: tokens.acc,
                          foregroundColor: tokens.onacc,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => Navigator.of(context).pop(draft),
                        child: Text(
                          l10n.searchShowResults,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: tokens.mut,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.48,
        ),
      ),
    );
  }
}

class _RoomPickerDialog extends StatefulWidget {
  const _RoomPickerDialog();

  @override
  State<_RoomPickerDialog> createState() => _RoomPickerDialogState();
}

class _RoomPickerDialogState extends State<_RoomPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final locals = MatrixLocals(l10n);
    final needle = _controller.text.trim().toLowerCase();
    final rooms = Matrix.of(context).client.rooms
        .where((room) => room.membership == Membership.join && !room.isSpace)
        .where(
          (room) => room
              .getLocalizedDisplayname(locals)
              .toLowerCase()
              .contains(needle),
        )
        .take(50)
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.searchChatsRooms,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  final name = safeDisplayText(
                    room.getLocalizedDisplayname(locals),
                  );
                  return ListTile(
                    leading: Avatar(
                      mxContent: room.avatar,
                      name: name,
                      size: 36,
                      colorSeed: room.id,
                      client: room.client,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(room.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
