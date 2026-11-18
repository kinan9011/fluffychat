// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/search/chat_matcher.dart';
import 'package:fluffychat/utils/search/local_search.dart';
import 'package:fluffychat/utils/search/search_sections.dart';
import 'package:fluffychat/utils/search/snippet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A 34 px pill with a 44 px tap area (DESIGN 7.2, WCAG target size).
class SearchChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final VoidCallback? onClose;
  final bool filled;

  const SearchChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.onClose,
    this.filled = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final background = filled && selected
        ? tokens.acc
        : selected
        ? tokens.accs
        : tokens.surf2;
    final foreground = filled && selected
        ? tokens.onacc
        : selected
        ? tokens.acc
        : tokens.fg;
    final leading = this.leading;
    final icon = this.icon;
    final onClose = this.onClose;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: _AddedChipMotion(
              enabled: onClose != null,
              duration: duration,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                height: 34,
                padding: EdgeInsetsDirectional.only(
                  start: leading == null ? 12 : 4,
                  end: onClose == null ? 12 : 8,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(17),
                  border: selected && !filled
                      ? Border.all(color: tokens.acc, width: 1.5)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    ?leading,
                    if (icon != null) Icon(icon, size: 17, color: foreground),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onClose != null)
                      InkResponse(
                        onTap: onClose,
                        radius: 14,
                        child: Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: foreground,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip that is added scales up and fades in (Telegram: 220 ms). Chips
/// that are only selected keep their place and change colour instead.
class _AddedChipMotion extends StatelessWidget {
  final bool enabled;
  final Duration duration;
  final Widget child;

  const _AddedChipMotion({
    required this.enabled,
    required this.duration,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOut,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: 0.8 + 0.2 * value, child: child),
      ),
    );
  }
}

class SearchChipsBar extends StatelessWidget {
  final SearchSection selected;
  final ValueChanged<SearchSection> onSelect;

  const SearchChipsBar({
    required this.selected,
    required this.onSelect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final labels = <SearchSection, String>{
      SearchSection.all: l10n.all,
      SearchSection.chats: l10n.chats,
      SearchSection.messages: l10n.messages,
      SearchSection.media: l10n.searchSectionMedia,
      SearchSection.files: l10n.files,
      SearchSection.links: l10n.searchSectionLinks,
      SearchSection.publicRooms: l10n.publicRooms,
    };
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: SearchChip(
                label: entry.value,
                selected: entry.key == selected,
                filled: true,
                onTap: () => onSelect(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class SearchSectionHeader extends StatelessWidget {
  final String text;

  const SearchSectionHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(
          start: 16,
          top: 12,
          end: 16,
          bottom: 6,
        ),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: tokens.mut,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.48,
          ),
        ),
      ),
    );
  }
}

class SearchNote extends StatelessWidget {
  final String text;

  const SearchNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: tokens.mut,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tokens.mut, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class SearchRetryRow extends StatelessWidget {
  final VoidCallback onTap;

  const SearchRetryRow({required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final text = L10n.of(context).searchError;
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 10,
              children: [
                Icon(Icons.refresh_rounded, color: tokens.red, size: 20),
                Expanded(
                  child: Text(text, style: TextStyle(color: tokens.fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatStrip extends StatelessWidget {
  final List<ChatMatch> chats;
  final String Function(String roomId) nameOf;
  final ValueChanged<Room> onTap;

  const ChatStrip({
    required this.chats,
    required this.nameOf,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    const nameLines = 12 * 1.2 * 2;
    return SizedBox(
      height:
          98 - nameLines + MediaQuery.textScalerOf(context).scale(nameLines),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chats.length,
        itemBuilder: (context, i) {
          final item = chats[i];
          final name = nameOf(item.room.id);
          return Semantics(
            button: true,
            label: name,
            excludeSemantics: true,
            onTap: () => onTap(item.room),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTap(item.room),
              child: Container(
                width: 72,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  spacing: 5,
                  children: [
                    Avatar(
                      mxContent: item.room.avatar,
                      name: name,
                      size: 54,
                      colorSeed: item.room.id,
                      client: item.room.client,
                      borderRadius: item.room.isSpace
                          ? BorderRadius.circular(16)
                          : null,
                    ),
                    Text(
                      name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MessageHitTile extends StatelessWidget {
  final SearchHit hit;
  final String senderName;
  final String chatName;
  final Room? room;
  final VoidCallback? onTap;

  const MessageHitTile({
    required this.hit,
    required this.senderName,
    required this.chatName,
    required this.room,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final snippet = Snippet.of(hit.message.text, hit.highlights);
    final time = DateTime.fromMillisecondsSinceEpoch(
      hit.message.timestamp,
    ).localizedTimeShort(context);
    final title = chatName.isEmpty ? senderName : '$chatName · $senderName';
    final room = this.room;
    return Semantics(
      button: onTap != null,
      label: '$title, $time, ${snippet.text}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Avatar(
                  mxContent: room?.avatar,
                  name: chatName.isEmpty ? senderName : chatName,
                  size: 44,
                  colorSeed: hit.message.roomId,
                  client: room?.client,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.fg,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            time,
                            style: TextStyle(color: tokens.mut, fontSize: 12.5),
                          ),
                        ],
                      ),
                      Text.rich(
                        highlighted(snippet, tokens),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.mut,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @visibleForTesting
  static TextSpan highlighted(Snippet snippet, AppTokens tokens) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final range in snippet.highlights) {
      if (range.start > at) {
        spans.add(TextSpan(text: snippet.text.substring(at, range.start)));
      }
      spans.add(
        TextSpan(
          text: snippet.text.substring(range.start, range.end),
          style: TextStyle(backgroundColor: tokens.accs, color: tokens.fg),
        ),
      );
      at = range.end;
    }
    if (at < snippet.text.length) {
      spans.add(TextSpan(text: snippet.text.substring(at)));
    }
    return TextSpan(children: spans);
  }
}

class PersonTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;

  const PersonTile({required this.profile, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final name = safeDisplayText(
      profile.displayName ?? profile.userId.localpart ?? profile.userId,
    );
    return Semantics(
      button: true,
      label: name,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              spacing: 12,
              children: [
                Avatar(
                  mxContent: profile.avatarUrl,
                  name: name,
                  size: 40,
                  colorSeed: profile.userId,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        profile.userId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: tokens.mut,
                          fontSize: 12,
                          fontFamily: AppTypography.monoFamily,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PublicRoomTile extends StatelessWidget {
  final PublishedRoomsChunk chunk;
  final VoidCallback onTap;

  const PublicRoomTile({required this.chunk, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final name = safeDisplayText(
      chunk.name ?? chunk.canonicalAlias ?? l10n.emptyChat,
    );
    final alias = chunk.canonicalAlias;
    return Semantics(
      button: true,
      label: '$name, ${l10n.join}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              spacing: 12,
              children: [
                Avatar(
                  mxContent: chunk.avatarUrl,
                  name: name,
                  size: 44,
                  colorSeed: chunk.roomId,
                  borderRadius: chunk.roomType == 'm.space'
                      ? BorderRadius.circular(14)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (alias != null)
                        Text(
                          safeDisplayText(alias, maxGraphemes: 255),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: tokens.mut,
                            fontSize: 12,
                            fontFamily: AppTypography.monoFamily,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accs,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    l10n.join,
                    style: TextStyle(
                      color: tokens.acc,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
