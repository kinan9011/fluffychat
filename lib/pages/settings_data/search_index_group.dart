// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/search/index_feeder.dart';
import 'package:odango/utils/search/message_index.dart';
import 'package:odango/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:odango/widgets/matrix.dart';
import 'package:odango/widgets/settings/settings_group.dart';
import 'package:odango/widgets/settings/settings_row.dart';

/// What the local search index holds on this device, and the way to empty it.
class SearchIndexGroup extends StatefulWidget {
  const SearchIndexGroup({super.key});

  static const rowKey = ValueKey('search_index_row');

  @override
  State<SearchIndexGroup> createState() => _SearchIndexGroupState();
}

class _SearchIndexGroupState extends State<SearchIndexGroup> {
  List<Client> get _clients => Matrix.of(
    context,
  ).widget.clients.where((client) => client.isLogged()).toList();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    for (final client in _clients) {
      await MessageIndex.of(client).ready;
    }
    if (mounted) setState(() {});
  }

  Future<void> _clear() async {
    final l10n = L10n.of(context);
    final clients = _clients;
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.searchIndexClear,
      message: l10n.searchIndexClearConfirm,
      okLabel: l10n.searchIndexClear,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok) return;
    for (final client in clients) {
      IndexFeeder.of(client).markCaughtUp();
    }
    await Future.wait(clients.map((client) => MessageIndex.of(client).wipe()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final indexes = _clients.map(MessageIndex.of).toList();
    final count = indexes.fold<int>(0, (sum, index) => sum + index.length);
    final persistent = indexes.every((index) => index.persistent);
    return SettingsGroup(
      header: l10n.searchIndexTitle,
      rows: [
        SettingsRow(
          key: SearchIndexGroup.rowKey,
          icon: Icons.manage_search_rounded,
          title: l10n.searchIndexClear,
          subtitle: persistent
              ? l10n.searchIndexCount(count)
              : l10n.searchIndexMemoryOnly,
          destructive: true,
          showChevron: false,
          onTap: _clear,
        ),
      ],
    );
  }
}
