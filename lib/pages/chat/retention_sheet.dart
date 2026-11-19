// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/adaptive_bottom_sheet.dart';
import 'package:odango/utils/retention/retention_labels.dart';
import 'package:odango/utils/retention/retention_policy.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';
import 'package:odango/widgets/future_loading_dialog.dart';
import 'package:odango/widgets/matrix.dart';

Future<void> showRetentionSheet(BuildContext context, Room room) {
  final support = Matrix.of(
    context,
  ).serverCapabilities.cached(room.client)[ServerFeature.retention];
  return showAdaptiveBottomSheet<void>(
    context: context,
    maxHeight: AppSchedule.sheetMaxHeight,
    builder: (context) => RetentionSheet(room: room, serverSupport: support),
  );
}

class RetentionSheet extends StatefulWidget {
  const RetentionSheet({
    required this.room,
    required this.serverSupport,
    super.key,
  });

  final Room room;
  final FeatureSupport serverSupport;

  @override
  State<RetentionSheet> createState() => RetentionSheetController();
}

class RetentionSheetController extends State<RetentionSheet> {
  static const minDays = 1;
  static const maxDays = 365;

  late final Duration? initial;
  late final bool elsewhere;
  late Duration? selected;
  var unset = false;
  late bool custom;
  late int customDays;

  Room get room => widget.room;

  bool get canChange => room.canChangeStateEvent(RetentionPolicy.eventType);

  bool get changed => !unset && (elsewhere || selected != initial);

  Map<String, Object?>? get _existing =>
      room.getState(RetentionPolicy.eventType)?.content;

  FeatureSupport get serverSupport => widget.serverSupport;

  @override
  void initState() {
    super.initState();
    initial = RetentionPolicy.fromContent(_existing)?.maxLifetime;
    elsewhere = RetentionPolicy.stateOf(_existing) == RetentionState.elsewhere;
    unset = elsewhere;
    selected = initial;
    final wanted = initial;
    custom = wanted != null && !RetentionPolicy.presets.contains(wanted);
    customDays = custom
        ? wanted!.inDays.clamp(minDays, maxDays)
        : RetentionPolicy.presets.first.inDays;
  }

  void select(Duration? lifetime) => setState(() {
    unset = false;
    custom = false;
    selected = lifetime;
  });

  void selectCustom() => setState(() {
    unset = false;
    custom = true;
    selected = Duration(days: customDays);
  });

  void setCustomDays(int days) => setState(() {
    unset = false;
    customDays = days.clamp(minDays, maxDays);
    custom = true;
    selected = Duration(days: customDays);
  });

  void close() => Navigator.of(context).pop();

  Future<void> save() async {
    final lifetime = selected;
    if (!canChange || !changed) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room.client.setRoomStateWithKey(
        room.id,
        RetentionPolicy.eventType,
        '',
        RetentionPolicy.contentFor(lifetime, existing: _existing),
      ),
    );
    if (!mounted || result.error != null) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => RetentionSheetView(this);
}

class RetentionSheetView extends StatelessWidget {
  const RetentionSheetView(this.controller, {super.key});

  final RetentionSheetController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    final serverNote = retentionServerNote(l10n, c.serverSupport);
    return Material(
      color: tokens.surf,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 16,
            end: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: AppSchedule.sheetHandleWidth,
                  height: AppSchedule.sheetHandleHeight,
                  margin: const EdgeInsetsDirectional.only(top: 10, bottom: 12),
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
                      l10n.disappearingMessages,
                      style: TextStyle(
                        color: tokens.fg,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('retention_close'),
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
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Material(
                        color: tokens.surf2,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _Option(
                              key: const ValueKey('retention_off'),
                              label: l10n.retentionOff,
                              selected: c.selected == null && !c.unset,
                              enabled: c.canChange,
                              onTap: () => c.select(null),
                            ),
                            for (final preset in RetentionPolicy.presets)
                              _Option(
                                key: ValueKey('retention_${preset.inDays}'),
                                label: formatRetention(l10n, preset),
                                selected: !c.custom && c.selected == preset,
                                enabled: c.canChange,
                                onTap: () => c.select(preset),
                              ),
                            _Option(
                              key: const ValueKey('retention_custom'),
                              label: l10n.retentionCustom,
                              selected: c.custom,
                              enabled: c.canChange,
                              onTap: c.selectCustom,
                              last: !c.custom,
                            ),
                            if (c.custom) _Stepper(c),
                          ],
                        ),
                      ),
                      if (c.elsewhere)
                        _Note(
                          icon: Icons.rule_rounded,
                          text: l10n.retentionElsewhereNote,
                          key: const ValueKey('retention_elsewhere_note'),
                        ),
                      _Note(
                        icon: Icons.info_outline_rounded,
                        text: l10n.retentionHonestNote,
                      ),
                      _Note(
                        icon: Icons.dns_outlined,
                        text: serverNote,
                        key: const ValueKey('retention_server_note'),
                      ),
                      _Note(
                        icon: Icons.visibility_outlined,
                        text: l10n.retentionOffNote,
                      ),
                      if (!c.canChange)
                        _Note(
                          icon: Icons.lock_outline_rounded,
                          text: l10n.retentionNoPermission,
                          key: const ValueKey('retention_no_permission'),
                        ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              if (c.canChange)
                Semantics(
                  button: true,
                  enabled: c.changed,
                  label: l10n.save,
                  excludeSemantics: true,
                  onTap: c.changed ? c.save : null,
                  child: Material(
                    color: c.changed ? tokens.acc : tokens.surf2,
                    borderRadius: BorderRadius.circular(
                      AppSchedule.primaryButton / 2,
                    ),
                    child: InkWell(
                      key: const ValueKey('retention_save'),
                      onTap: c.changed ? c.save : null,
                      borderRadius: BorderRadius.circular(
                        AppSchedule.primaryButton / 2,
                      ),
                      child: SizedBox(
                        height: AppSchedule.primaryButton,
                        child: Center(
                          child: Text(
                            l10n.save,
                            style: TextStyle(
                              color: c.changed ? tokens.onacc : tokens.mut,
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

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.last = false,
    super.key,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsetsDirectional.only(start: 16, end: 14),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: tokens.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: enabled ? tokens.fg : tokens.mut,
                    fontSize: 15.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_rounded, size: 22, color: tokens.acc),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(this.controller);

  final RetentionSheetController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final c = controller;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${l10n.retentionCustomDays}: ${c.customDays}',
              key: const ValueKey('retention_days'),
              style: TextStyle(color: tokens.fg, fontSize: 15.5),
            ),
          ),
          IconButton(
            key: const ValueKey('retention_minus'),
            tooltip: l10n.retentionDaysFewer,
            onPressed:
                c.canChange && c.customDays > RetentionSheetController.minDays
                ? () => c.setCustomDays(c.customDays - 1)
                : null,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.remove_rounded),
          ),
          IconButton(
            key: const ValueKey('retention_plus'),
            tooltip: l10n.retentionDaysMore,
            onPressed:
                c.canChange && c.customDays < RetentionSheetController.maxDays
                ? () => c.setCustomDays(c.customDays + 1)
                : null,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, end: 4, top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.m,
        children: [
          Icon(icon, size: 19, color: tokens.mut),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: tokens.mut, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
