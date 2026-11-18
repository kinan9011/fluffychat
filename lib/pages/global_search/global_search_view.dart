// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/global_search/global_search.dart';
import 'package:fluffychat/pages/global_search/search_result_widgets.dart';
import 'package:fluffychat/utils/search/search_sections.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class GlobalSearchView extends StatelessWidget {
  final GlobalSearchController controller;

  const GlobalSearchView(this.controller, {super.key});

  static const fieldKey = ValueKey('global_search_field');
  static const filtersKey = ValueKey('global_search_filters');
  static const cancelKey = ValueKey('global_search_cancel');
  static const resultsKey = ValueKey('global_search_results');

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final activeFilters = controller.filter.activeCount;
    return Scaffold(
      backgroundColor: tokens.bg,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSettingsLayout.maxWidth,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 4),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: TextField(
                          key: fieldKey,
                          controller: controller.searchController,
                          focusNode: controller.focusNode,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: controller.onChanged,
                          style: TextStyle(color: tokens.fg, fontSize: 15.5),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: tokens.surf2,
                            hintText: l10n.searchHint,
                            hintStyle: TextStyle(color: tokens.mut),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 21,
                              color: tokens.mut,
                            ),
                            suffixIcon: controller.searchController.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: l10n.clear,
                                    onPressed: controller.clearQuery,
                                    icon: Icon(
                                      Icons.cancel_rounded,
                                      size: 19,
                                      color: tokens.mut,
                                    ),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide(
                                color: tokens.acc,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: activeFilters == 0
                            ? l10n.searchFilters
                            : l10n.searchFiltersActive(activeFilters),
                        excludeSemantics: true,
                        onTap: controller.openFilters,
                        child: GestureDetector(
                          key: filtersKey,
                          behavior: HitTestBehavior.opaque,
                          onTap: controller.openFilters,
                          child: SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: Badge(
                                isLabelVisible: activeFilters > 0,
                                label: Text('$activeFilters'),
                                backgroundColor: tokens.acc,
                                textColor: tokens.onacc,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: tokens.accs,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    size: 22,
                                    color: tokens.acc,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      TextButton(
                        key: cancelKey,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 48),
                          foregroundColor: tokens.acc,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/rooms'),
                        child: Text(
                          l10n.cancel,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SearchChipsBar(
                  selected: controller.section,
                  onSelect: controller.selectSection,
                ),
                Expanded(child: SearchResultsList(controller)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SearchResultsList extends StatelessWidget {
  final GlobalSearchController controller;

  const SearchResultsList(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final messages = c.messages;
    final loading =
        c.serverStatus == SourceStatus.loading ||
        c.peopleStatus == SourceStatus.loading ||
        c.publicStatus == SourceStatus.loading;
    final nothing =
        (c.hasSearch || c.browsesPublic) &&
        !loading &&
        !c.publicPending &&
        (!c.showsMessages || messages.isEmpty) &&
        (!c.showsChats || c.chats.isEmpty) &&
        (!c.showsPeople || c.people.isEmpty) &&
        (!c.showsPublicRooms || c.publicRooms.isEmpty);
    return ListView(
      key: GlobalSearchView.resultsKey,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (!c.hasSearch && !c.browsesPublic) ...[
          SearchNote(l10n.searchHint),
          if (c.chats.isNotEmpty) ...[
            SearchSectionHeader(l10n.chats),
            ChatStrip(chats: c.chats, nameOf: c.chatName, onTap: c.openChat),
          ],
        ],
        if (c.hasSearch && c.showsChats && c.chats.isNotEmpty) ...[
          SearchSectionHeader(l10n.chats),
          ChatStrip(chats: c.chats, nameOf: c.chatName, onTap: c.openChat),
        ],
        if (c.hasSearch && c.showsPeople && c.people.isNotEmpty) ...[
          SearchSectionHeader(l10n.users),
          for (final profile in c.people)
            PersonTile(profile: profile, onTap: () => c.openPerson(profile)),
        ],
        if (c.hasSearch && c.showsMessages) ...[
          SearchSectionHeader(l10n.searchMessagesCount(messages.length)),
          for (final note in c.notices(l10n)) SearchNote(note),
          for (final hit in messages)
            MessageHitTile(
              hit: hit,
              senderName: c.senderName(hit),
              chatName: c.chatName(hit.message.roomId),
              room: c.roomOf(hit.message.roomId),
              onTap: () => c.openMessage(hit),
            ),
          if (c.serverStatus == SourceStatus.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          if (c.serverStatus == SourceStatus.error)
            SearchRetryRow(onTap: c.retryServer),
          if (c.canLoadMoreServer)
            Center(
              child: TextButton(
                onPressed: c.loadMoreServer,
                child: Text(l10n.loadMore),
              ),
            ),
        ],
        if (c.wantsPublicRooms) ...[
          SearchSectionHeader(l10n.publicRooms),
          if (c.section == SearchSection.publicRooms) ...[
            Semantics(
              button: true,
              label: l10n.searchServerRow(c.serverLabel),
              excludeSemantics: true,
              onTap: c.changeServer,
              child: InkWell(
                onTap: c.changeServer,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            l10n.searchServerRow(c.serverLabel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: tokens.mut, fontSize: 13),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            l10n.changeTheHomeserver,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.acc,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (c.directoryNotice(l10n) case final notice?) SearchNote(notice),
          ],
          if (c.publicStatus == SourceStatus.error)
            SearchRetryRow(onTap: c.retryPublic),
          for (final chunk in c.publicChats)
            PublicRoomTile(chunk: chunk, onTap: () => c.openPublicRoom(chunk)),
          if (c.publicSpaces.isNotEmpty) ...[
            SearchSectionHeader(l10n.publicSpaces),
            for (final chunk in c.publicSpaces)
              PublicRoomTile(
                chunk: chunk,
                onTap: () => c.openPublicRoom(chunk),
              ),
          ],
          if (c.publicStatus == SourceStatus.loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
          if (c.canLoadMorePublic)
            Center(
              child: TextButton(
                onPressed: c.loadMorePublic,
                child: Text(l10n.loadMore),
              ),
            ),
        ],
        if (nothing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              spacing: 12,
              children: [
                Icon(Icons.search_off_rounded, size: 56, color: tokens.mut),
                Text(
                  l10n.nothingFound,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.mut, fontSize: 15),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
