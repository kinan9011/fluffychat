// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/chat/trust_user_key_dialog.dart';
import 'package:odango/utils/adaptive_bottom_sheet.dart';
import 'package:odango/utils/localized_exception_extension.dart';
import 'package:odango/utils/topics/topic.dart';

/// Resolves with the id of the new topic root, or null when closed.
Future<String?> showTopicCreateSheet(BuildContext context, Room room) =>
    showAdaptiveBottomSheet<String>(
      context: context,
      maxHeight: AppSchedule.sheetMaxHeight,
      builder: (context) => TopicCreateSheet(room: room),
    );

class TopicCreateSheet extends StatefulWidget {
  const TopicCreateSheet({required this.room, super.key});

  final Room room;

  @override
  State<TopicCreateSheet> createState() => TopicCreateController();
}

class TopicCreateController extends State<TopicCreateSheet> {
  final title = TextEditingController();
  var icon = TopicIcons.fallback;
  var sending = false;
  String? _txid;
  String? _txidContent;

  String get cleanTitle => TopicParser.sanitizeTitle(title.text);

  bool get canCreate => !sending && cleanTitle.isNotEmpty;

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  void changed([_]) => setState(() {});

  void selectIcon(String key) => setState(() => icon = key);

  void close() => Navigator.of(context).pop();

  Future<void> create() async {
    if (!canCreate) return;
    final name = cleanTitle;
    final content = <String, Object?>{
      'msgtype': MessageTypes.Text,
      'body': name,
      topicContentKey: {'title': name, 'icon': icon},
    };
    setState(() => sending = true);
    final proceed = await showTrustUserInRoomDialog(context, widget.room);
    if (!mounted) return;
    if (!proceed) return setState(() => sending = false);
    try {
      final fingerprint = jsonEncode(content);
      if (_txidContent != fingerprint) {
        _txidContent = fingerprint;
        _txid = widget.room.client.generateUniqueTransactionId();
      }
      final id = await widget.room.sendEvent(content, txid: _txid);
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e, s) {
      Logs().w('Unable to create a topic', e, s);
      if (!mounted) return;
      setState(() => sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    }
  }

  @override
  Widget build(BuildContext context) => TopicCreateView(this);
}

class TopicCreateView extends StatelessWidget {
  const TopicCreateView(this.controller, {super.key});

  final TopicCreateController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    return Material(
      color: tokens.bg,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 14,
            end: 14,
            bottom: 14 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: AppSchedule.sheetHandleWidth,
                  height: AppSchedule.sheetHandleHeight,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.newTopic,
                      style: TextStyle(
                        color: tokens.fg,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('topic_close'),
                    tooltip: l10n.close,
                    onPressed: c.close,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Container(
                      width: AppSchedule.closeButton,
                      height: AppSchedule.closeButton,
                      decoration: BoxDecoration(
                        color: tokens.surf2,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: tokens.surf,
                        borderRadius: BorderRadius.circular(18),
                        child: TextField(
                          key: const ValueKey('topic_title_field'),
                          controller: c.title,
                          onChanged: c.changed,
                          maxLength: TopicParser.titleMax,
                          style: TextStyle(
                            color: tokens.fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.topicNameHint,
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 18,
                          top: 16,
                          bottom: 6,
                        ),
                        child: Text(
                          l10n.topicIconLabel.toUpperCase(),
                          style: TextStyle(
                            color: tokens.mut,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.48,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: AppSpacing.s,
                        runSpacing: AppSpacing.s,
                        children: [
                          for (final entry in TopicIcons.allowed.entries)
                            _IconChoice(
                              key: ValueKey('topic_icon_${entry.key}'),
                              name: entry.key,
                              icon: entry.value,
                              selected: c.icon == entry.key,
                              onTap: () => c.selectIcon(entry.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              Semantics(
                button: true,
                enabled: c.canCreate,
                label: l10n.createTopic,
                excludeSemantics: true,
                onTap: c.canCreate ? c.create : null,
                child: Material(
                  color: c.canCreate ? tokens.acc : tokens.surf2,
                  borderRadius: BorderRadius.circular(
                    AppSchedule.primaryButton / 2,
                  ),
                  child: InkWell(
                    key: const ValueKey('topic_create'),
                    onTap: c.canCreate ? c.create : null,
                    borderRadius: BorderRadius.circular(
                      AppSchedule.primaryButton / 2,
                    ),
                    child: SizedBox(
                      height: AppSchedule.primaryButton,
                      child: Center(
                        child: Text(
                          l10n.createTopic,
                          style: TextStyle(
                            color: c.canCreate ? tokens.onacc : tokens.mut,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.name,
    required this.icon,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String name;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: L10n.of(context).topicIconName(name),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? tokens.accs : tokens.surf,
        borderRadius: BorderRadius.circular(AppTopics.iconTileRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTopics.iconTileRadius),
          child: Container(
            width: AppTopics.iconTile,
            height: AppTopics.iconTile,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTopics.iconTileRadius),
              border: Border.all(
                color: selected ? tokens.acc : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              size: AppTopics.iconSize,
              color: selected ? tokens.acc : tokens.fg,
            ),
          ),
        ),
      ),
    );
  }
}
