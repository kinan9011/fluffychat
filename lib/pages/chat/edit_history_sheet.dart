// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/message_action_runner.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/chat/display_text.dart';
import 'package:fluffychat/utils/chat/edit_history.dart';
import 'package:fluffychat/utils/chat/message_actions.dart';
import 'package:fluffychat/utils/chat/word_diff.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

Future<void> showEditHistorySheet(
  BuildContext context,
  ChatController controller,
  Event event,
) async {
  if (event.redacted) return;
  await showAdaptiveBottomSheet<void>(
    context: context,
    builder: (context) =>
        EditHistorySheet(controller: controller, event: event),
  );
}

/// Loads the versions of [event]: the edits the timeline already holds, then
/// one page from the homeserver.
class EditHistorySheet extends StatefulWidget {
  const EditHistorySheet({
    required this.controller,
    required this.event,
    super.key,
  });

  final ChatController controller;
  final Event event;

  @override
  State<EditHistorySheet> createState() => _EditHistorySheetState();
}

class _EditHistorySheetState extends State<EditHistorySheet> {
  EditHistory? _history;
  var _loading = true;
  var _started = false;
  StreamSubscription<SyncUpdate>? _syncs;

  Event get _event => widget.event;

  String _originalText(BuildContext context) =>
      _event.calcLocalizedBodyFallback(
        MatrixLocals(L10n.of(context)),
        withSenderNamePrefix: false,
        hideReply: true,
      );

  List<Event> get _local {
    final timeline = widget.controller.timeline;
    return timeline == null
        ? const []
        : _event.aggregatedEvents(timeline, RelationshipTypes.edit).toList();
  }

  @override
  void initState() {
    super.initState();
    _syncs = widget.controller.room.client.onSync.stream.listen(
      (_) => _closeIfRedacted(),
    );
  }

  @override
  void dispose() {
    _syncs?.cancel();
    super.dispose();
  }

  bool _closeIfRedacted() {
    if (!_event.redacted) return false;
    final route = ModalRoute.of(context);
    if (mounted && route != null) Navigator.of(context).removeRoute(route);
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_event.redacted) {
      _loading = false;
      return;
    }
    _history = buildEditHistory(
      original: _event,
      originalText: _originalText(context),
      candidates: _local,
    );
    _load(_originalText(context));
  }

  Future<void> _load(String originalText) async {
    final remote = await fetchEditEvents(widget.controller.room, _event);
    if (!mounted || _closeIfRedacted()) return;
    setState(() {
      _history = buildEditHistory(
        original: _event,
        originalText: originalText,
        candidates: [..._local, ...remote],
      );
      _loading = false;
    });
  }

  void _run(MessageAction action) {
    Navigator.of(context).pop();
    runMessageAction(widget.controller, action, _event);
  }

  @override
  Widget build(BuildContext context) {
    final actions = messageActionContext(widget.controller, _event);
    return EditHistoryView(
      history: _history,
      loading: _loading,
      onClose: Navigator.of(context).pop,
      onEditAgain: actions.canEdit ? () => _run(MessageAction.edit) : null,
      onDelete: actions.canRedact ? () => _run(MessageAction.delete) : null,
    );
  }
}

class EditHistoryView extends StatelessWidget {
  const EditHistoryView({
    required this.history,
    required this.loading,
    required this.onClose,
    this.onEditAgain,
    this.onDelete,
    super.key,
  });

  final EditHistory? history;
  final bool loading;
  final VoidCallback onClose;
  final VoidCallback? onEditAgain;
  final VoidCallback? onDelete;

  static String _clean(String text) =>
      safeDisplayText(text, maxGraphemes: RichLimits.maxEditUnits);

  static final _diffs = Expando<List<List<DiffSegment>>>();

  static List<List<DiffSegment>> _diffsOf(EditHistory history) =>
      _diffs[history] ??= [
        for (var i = 1; i <= history.edits.length; i++)
          wordDiff(
            _clean(i == 1 ? history.original.text : history.edits[i - 2].text),
            _clean(history.edits[i - 1].text),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final history = this.history;
    final versions = history == null
        ? const <EditVersion>[]
        : [history.original, ...history.edits];
    final current = versions.length < 2 ? null : versions.last;
    final diffs = history == null
        ? const <List<DiffSegment>>[]
        : _diffsOf(history);
    return Material(
      color: tokens.surf,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 16,
            end: 16,
            bottom: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsetsDirectional.only(top: 10, bottom: 12),
                  decoration: BoxDecoration(
                    color: tokens.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.editHistory,
                        style: TextStyle(
                          color: tokens.fg,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: l10n.close,
                      onTap: onClose,
                      excludeSemantics: true,
                      child: InkResponse(
                        key: const ValueKey('edit_history_close'),
                        onTap: onClose,
                        radius: 22,
                        child: SizedBox.square(
                          dimension: 44,
                          child: Center(
                            child: Container(
                              width: 34,
                              height: 34,
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (!loading && (history?.edits.isEmpty ?? true))
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          l10n.editHistoryEmpty,
                          style: TextStyle(color: tokens.mut, fontSize: 14),
                        ),
                      ),
                    if (current != null)
                      _VersionBlock(
                        key: const ValueKey('history_current'),
                        label: l10n.editHistoryCurrent(
                          current.time.localizedTimeOfDay(context),
                        ),
                        labelColor: tokens.acc,
                        fill: tokens.outS,
                        textColor: tokens.outFg,
                        text: _clean(current.text),
                        segments: null,
                      ),
                    for (var i = versions.length - 1; i >= 0; i--)
                      _VersionBlock(
                        key: ValueKey('history_$i'),
                        label: i == 0
                            ? l10n.editHistoryOriginal(
                                versions[i].time.localizedTimeOfDay(context),
                              )
                            : l10n.editHistoryEdited(
                                versions[i].time.localizedTimeOfDay(context),
                              ),
                        labelColor: tokens.mut,
                        fill: tokens.surf2,
                        textColor: tokens.fg,
                        text: _clean(versions[i].text),
                        segments: i == 0 ? null : diffs[i - 1],
                      ),
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          spacing: 10,
                          children: [
                            const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            Text(
                              l10n.editHistoryLoading,
                              style: TextStyle(color: tokens.mut, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (onEditAgain != null || onDelete != null)
                const SizedBox(height: 12),
              if (onEditAgain != null)
                _ActionPill(
                  key: const ValueKey('history_edit_again'),
                  icon: Icons.edit_rounded,
                  label: l10n.editAgain,
                  fill: tokens.surf2,
                  color: tokens.fg,
                  onTap: onEditAgain!,
                ),
              if (onEditAgain != null && onDelete != null)
                const SizedBox(height: 8),
              if (onDelete != null)
                _ActionPill(
                  key: const ValueKey('history_delete'),
                  icon: Icons.delete_rounded,
                  label: l10n.deleteForEveryone,
                  fill: tokens.red.withValues(alpha: .14),
                  color: tokens.fg,
                  iconColor: tokens.red,
                  onTap: onDelete!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionBlock extends StatelessWidget {
  const _VersionBlock({
    required this.label,
    required this.labelColor,
    required this.fill,
    required this.textColor,
    required this.text,
    required this.segments,
    super.key,
  });

  final String label;
  final Color labelColor;
  final Color fill;
  final Color textColor;
  final String text;
  final List<DiffSegment>? segments;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final style = TextStyle(color: textColor, fontSize: 15, height: 1.4);
    final shown = segments;
    final body = shown == null
        ? Text(text, style: style)
        : Semantics(
            label: [
              for (final segment in shown)
                switch (segment.kind) {
                  DiffKind.same => segment.text,
                  DiffKind.removed =>
                    '${l10n.editHistoryRemoved}: ${segment.text}',
                  DiffKind.added => '${l10n.editHistoryAdded}: ${segment.text}',
                },
            ].join(' '),
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  for (final segment in shown)
                    TextSpan(
                      text: segment.text,
                      style: switch (segment.kind) {
                        DiffKind.same => null,
                        DiffKind.removed => TextStyle(
                          backgroundColor: tokens.red.withValues(alpha: .22),
                          decoration: TextDecoration.lineThrough,
                        ),
                        DiffKind.added => TextStyle(
                          backgroundColor: tokens.ok.withValues(alpha: .25),
                          fontWeight: FontWeight.w600,
                        ),
                      },
                    ),
                ],
              ),
            ),
          );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(AppChat.historyBubbleRadius),
            ),
            child: body,
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.fill,
    required this.color,
    required this.onTap,
    this.iconColor,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color fill;
  final Color color;
  final Color? iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(26),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(icon, size: 20, color: iconColor ?? color),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
