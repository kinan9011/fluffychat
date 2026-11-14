// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class DatabaseKeyErrorPage extends StatefulWidget {
  final VoidCallback onRetry;
  final Future<void> Function() onReset;

  /// True when the system key store failed, false when the database itself
  /// could not be opened (full disk, another process, I/O error).
  final bool keyProblem;

  const DatabaseKeyErrorPage({
    super.key,
    required this.onRetry,
    required this.onReset,
    this.keyProblem = true,
  });

  static Widget app({
    required VoidCallback onRetry,
    required Future<void> Function() onReset,
    bool keyProblem = true,
  }) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    builder: (context, child) => Theme(
      data: FluffyThemes.buildTheme(context, Brightness.light),
      child: child!,
    ),
    home: DatabaseKeyErrorPage(
      onRetry: onRetry,
      onReset: onReset,
      keyProblem: keyProblem,
    ),
  );

  @override
  State<DatabaseKeyErrorPage> createState() => _DatabaseKeyErrorPageState();
}

class _DatabaseKeyErrorPageState extends State<DatabaseKeyErrorPage> {
  bool _busy = false;

  Future<void> _confirmReset() async {
    if (_busy) return;
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.databaseKeyResetAction,
      message: l10n.databaseKeyResetConfirm,
      okLabel: l10n.databaseKeyResetAction,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onReset();
    } catch (e, s) {
      Logs().e('Unable to reset local data', e, s);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.databaseKeyUnavailableTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    widget.keyProblem
                        ? l10n.databaseKeyUnavailableBody
                        : l10n.databaseOpenFailedBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : widget.onRetry,
                    child: Text(l10n.tryAgain),
                  ),
                  if (_busy)
                    Semantics(
                      liveRegion: true,
                      child: Column(
                        spacing: 8,
                        children: [
                          const CircularProgressIndicator.adaptive(),
                          Text(
                            l10n.databaseKeyResetting,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _busy ? null : _confirmReset,
                    child: Text(l10n.databaseKeyResetAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
