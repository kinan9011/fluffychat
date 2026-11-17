// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/status/status_sheet.dart';
import 'package:fluffychat/utils/status/status_policy.dart';
import 'package:material_ui/material_ui.dart';

class StatusSheetView extends StatelessWidget {
  const StatusSheetView(this.controller, {super.key});

  final StatusSheetController controller;

  static IconData suggestionIcon(StatusSuggestion value) => switch (value) {
    StatusSuggestion.meeting => Icons.event_busy_rounded,
    StatusSuggestion.commuting => Icons.directions_bus_rounded,
    StatusSuggestion.focusing => Icons.do_not_disturb_on_rounded,
    StatusSuggestion.sick => Icons.sick_rounded,
  };

  static String suggestionLabel(L10n l10n, StatusSuggestion value) =>
      switch (value) {
        StatusSuggestion.meeting => l10n.statusSuggestMeeting,
        StatusSuggestion.commuting => l10n.statusSuggestCommuting,
        StatusSuggestion.focusing => l10n.statusSuggestFocusing,
        StatusSuggestion.sick => l10n.statusSuggestSick,
      };

  static String clearLabel(L10n l10n, StatusClearAfter value) =>
      switch (value) {
        StatusClearAfter.hour => l10n.statusClearHour,
        StatusClearAfter.today => l10n.statusClearToday,
        StatusClearAfter.week => l10n.statusClearWeek,
        StatusClearAfter.never => l10n.statusClearNever,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final suggestion = controller.suggestion;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.only(
                  start: 16,
                  top: 10,
                  end: 16,
                  bottom: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: AppSchedule.sheetHandleWidth,
                        height: AppSchedule.sheetHandleHeight,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: tokens.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 4,
                        end: 4,
                        bottom: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.setStatus,
                              style: TextStyle(
                                color: tokens.fg,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('status_clear'),
                            onPressed: controller.clear,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              foregroundColor: tokens.acc,
                            ),
                            child: Text(
                              l10n.statusClear,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minHeight: 54),
                      padding: const EdgeInsetsDirectional.only(
                        start: 6,
                        top: 6,
                        end: 8,
                        bottom: 6,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surf2,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: tokens.acc, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: tokens.surf,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              suggestion == null
                                  ? Icons.edit_rounded
                                  : suggestionIcon(suggestion),
                              color: tokens.acc,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('status_field'),
                              controller: controller.text,
                              onChanged: controller.onTextChanged,
                              maxLength: maxStatusLength,
                              maxLines: 2,
                              minLines: 1,
                              textInputAction: TextInputAction.done,
                              style: TextStyle(color: tokens.fg, fontSize: 16),
                              buildCounter:
                                  (
                                    _, {
                                    required currentLength,
                                    required isFocused,
                                    required maxLength,
                                  }) => null,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                filled: false,
                                hintText: l10n.statusExampleMessage,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 6,
                        top: 6,
                        end: 6,
                        bottom: 8,
                      ),
                      child: Text(
                        l10n.leaveEmptyToClearStatus,
                        style: TextStyle(color: tokens.mut, fontSize: 12.5),
                      ),
                    ),
                    for (final value in StatusSheetController.suggestionKeys)
                      Semantics(
                        button: true,
                        label: suggestionLabel(l10n, value),
                        excludeSemantics: true,
                        onTap: () => controller.pickSuggestion(
                          value,
                          suggestionLabel(l10n, value),
                        ),
                        child: InkWell(
                          key: ValueKey('status_suggestion_${value.name}'),
                          onTap: () => controller.pickSuggestion(
                            value,
                            suggestionLabel(l10n, value),
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 46),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Row(
                                spacing: 12,
                                children: [
                                  Icon(
                                    suggestionIcon(value),
                                    size: 22,
                                    color: tokens.mut,
                                  ),
                                  Expanded(
                                    child: Text(
                                      suggestionLabel(l10n, value),
                                      style: TextStyle(
                                        color: tokens.fg,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    _Label(l10n.statusClearAfter),
                    Row(
                      spacing: 6,
                      children: [
                        for (final value in StatusClearAfter.values)
                          Expanded(
                            child: _Chip(
                              key: ValueKey('status_clear_${value.name}'),
                              label: clearLabel(l10n, value),
                              selected: controller.clearAfter == value,
                              onTap: () => controller.setClearAfter(value),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 6,
                        top: 6,
                        end: 6,
                        bottom: 14,
                      ),
                      child: Text(
                        l10n.statusClearNote,
                        style: TextStyle(color: tokens.mut, fontSize: 12.5),
                      ),
                    ),
                    _Label(l10n.statusPresenceSection),
                    Container(
                      decoration: BoxDecoration(
                        color: tokens.surf2,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          for (final (i, value)
                              in StatusPresenceChoice.values.indexed) ...[
                            if (i > 0)
                              Container(
                                height: 1,
                                margin: const EdgeInsetsDirectional.only(
                                  start: 38,
                                ),
                                color: tokens.line,
                              ),
                            _PresenceRow(
                              key: ValueKey('status_presence_${value.name}'),
                              label: switch (value) {
                                StatusPresenceChoice.online =>
                                  l10n.presenceOnline,
                                StatusPresenceChoice.away => l10n.presenceAway,
                                StatusPresenceChoice.appearOffline =>
                                  l10n.appearOffline,
                              },
                              dot: switch (value) {
                                StatusPresenceChoice.online => tokens.ok,
                                StatusPresenceChoice.away => tokens.warn,
                                StatusPresenceChoice.appearOffline =>
                                  tokens.mut,
                              },
                              selected: controller.presence == value,
                              onTap: () => controller.choosePresence(value),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (controller.showsSharingNote)
                      Padding(
                        key: const ValueKey('status_sharing_note'),
                        padding: const EdgeInsetsDirectional.only(
                          start: 6,
                          top: 8,
                          end: 6,
                        ),
                        child: Text(
                          l10n.statusSharesPresenceNote,
                          style: TextStyle(color: tokens.warn, fontSize: 12.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: 16,
                top: 8,
                end: 16,
                bottom: 14,
              ),
              child: SizedBox(
                width: double.infinity,
                height: AppSchedule.primaryButton,
                child: FilledButton(
                  key: const ValueKey('status_save'),
                  onPressed: controller.save,
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.acc,
                    foregroundColor: tokens.onacc,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l10n.statusSave),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 6, end: 6, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppTokens.of(context).mut,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.48,
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          child: Container(
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? tokens.accs : tokens.surf2,
              borderRadius: BorderRadius.circular(18),
              border: selected
                  ? Border.all(color: tokens.acc, width: 1.5)
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? tokens.acc : tokens.fg,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresenceRow extends StatelessWidget {
  const _PresenceRow({
    required this.label,
    required this.dot,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final Color dot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? tokens.acc : tokens.mut,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
