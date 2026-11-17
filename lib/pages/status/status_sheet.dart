// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/status/status_sheet_view.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/privacy/presence_policy.dart';
import 'package:fluffychat/utils/status/status_clear_store.dart';
import 'package:fluffychat/utils/status/status_policy.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

enum StatusPresenceChoice { online, away, appearOffline }

Future<void> showStatusSheet(BuildContext context) =>
    showAdaptiveBottomSheet<void>(
      context: context,
      maxHeight: 760,
      builder: (_) => const StatusSheet(),
    );

class StatusSheet extends StatefulWidget {
  const StatusSheet({super.key});

  @override
  StatusSheetController createState() => StatusSheetController();
}

class StatusSheetController extends State<StatusSheet> {
  static const suggestionKeys = [
    StatusSuggestion.meeting,
    StatusSuggestion.commuting,
    StatusSuggestion.focusing,
    StatusSuggestion.sick,
  ];

  final text = TextEditingController();
  StatusClearAfter clearAfter = StatusClearAfter.never;
  late StatusPresenceChoice presence = currentChoice;
  StatusSuggestion? suggestion;
  bool _edited = false;
  late final Client _client;

  StatusPresenceChoice get currentChoice {
    final policy = PresencePolicy.fromSettings();
    if (!policy.visibleToOthers) return StatusPresenceChoice.appearOffline;
    return policy.away
        ? StatusPresenceChoice.away
        : StatusPresenceChoice.online;
  }

  bool get sharesNow => PresencePolicy.fromSettings().visibleToOthers;

  bool get showsSharingNote =>
      presence != StatusPresenceChoice.appearOffline && !sharesNow;

  @override
  void initState() {
    super.initState();
    _client = Matrix.of(context).client;
    unawaited(_loadCurrent());
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  bool get _sameClient =>
      mounted && identical(Matrix.of(context).client, _client);

  Future<void> _loadCurrent() async {
    final userId = _client.userID;
    if (userId == null) return;
    try {
      final current = await _client.getPresence(userId);
      if (!_sameClient || _edited) return;
      final message = current.statusMsg;
      if (message == null || message.isEmpty) return;
      text.text = sanitizeStatus(message) ?? '';
      setState(() {});
    } catch (e) {
      Logs().d('[Status] could not read the current status (${e.runtimeType})');
    }
  }

  void onTextChanged(String _) {
    _edited = true;
    if (suggestion == null) return;
    setState(() => suggestion = null);
  }

  void pickSuggestion(StatusSuggestion value, String label) {
    _edited = true;
    text.text = label;
    text.selection = TextSelection.collapsed(offset: label.length);
    setState(() => suggestion = value);
  }

  void setClearAfter(StatusClearAfter value) =>
      setState(() => clearAfter = value);

  void choosePresence(StatusPresenceChoice value) =>
      setState(() => presence = value);

  Future<void> _applyPresenceChoice() async {
    switch (presence) {
      case StatusPresenceChoice.online:
        await AppSettings.shareOnlineStatus.setItem(true);
        await AppSettings.appearOffline.setItem(false);
        await AppSettings.presenceAway.setItem(false);
      case StatusPresenceChoice.away:
        await AppSettings.shareOnlineStatus.setItem(true);
        await AppSettings.appearOffline.setItem(false);
        await AppSettings.presenceAway.setItem(true);
      case StatusPresenceChoice.appearOffline:
        await AppSettings.appearOffline.setItem(true);
    }
  }

  Future<void> _publish(String? message) async {
    final userId = _client.userID;
    if (userId == null) return;
    await _client.setPresence(
      userId,
      PresencePolicy.fromSettings().statusPresence,
      statusMsg: message ?? '',
    );
    final store = StatusClearStore();
    final at = message == null
        ? null
        : statusClearAt(clearAfter, DateTime.now());
    if (message == null || at == null) {
      await store.disarm(userId);
      return;
    }
    await store.arm(userId, message, at);
  }

  Future<void> save() async {
    final message = sanitizeStatus(text.text);
    await _applyPresenceChoice();
    if (!mounted || !identical(Matrix.of(context).client, _client)) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _publish(message),
    );
    if (!mounted || result.error != null) return;
    Navigator.of(context).pop();
  }

  Future<void> clear() async {
    text.clear();
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _publish(null),
    );
    if (!mounted || result.error != null) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => StatusSheetView(this);
}

enum StatusSuggestion { meeting, commuting, focusing, sick }
