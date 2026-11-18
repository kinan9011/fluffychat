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

  /// Returns false when some local data could not be removed.
  final Future<bool> Function() onReset;

  /// Moves only the account that cannot be opened aside. Null hides the
  /// button (key problems, the web).
  final Future<bool> Function()? onSetAside;

  /// The confirmed reset may also remove the app lock PIN (Android repairs a
  /// broken keystore by wiping it), and the confirmation says so.
  final bool resetMayRemovePin;

  /// True when the system key store failed, false when the database itself
  /// could not be opened (full disk, another process, I/O error).
  final bool keyProblem;

  const DatabaseKeyErrorPage({
    super.key,
    required this.onRetry,
    required this.onReset,
    this.onSetAside,
    this.resetMayRemovePin = false,
    this.keyProblem = true,
  });

  static Widget app({
    required VoidCallback onRetry,
    required Future<bool> Function() onReset,
    Future<bool> Function()? onSetAside,
    bool resetMayRemovePin = false,
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
      onSetAside: onSetAside,
      resetMayRemovePin: resetMayRemovePin,
      keyProblem: keyProblem,
    ),
  );

  @override
  State<DatabaseKeyErrorPage> createState() => _DatabaseKeyErrorPageState();
}

class _DatabaseKeyErrorPageState extends State<DatabaseKeyErrorPage> {
  bool _busy = false;
  String? _problem;
  String _busyLabel = '';

  Future<void> _run(
    Future<bool> Function() action,
    String Function(L10n l10n) busy,
    String Function(L10n l10n) failure,
  ) async {
    final l10n = L10n.of(context);
    setState(() {
      _busyLabel = busy(l10n);
      _busy = true;
      _problem = null;
    });
    var done = false;
    try {
      done = await action();
    } catch (e) {
      Logs().e('Local data action failed', e.runtimeType);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = done ? null : failure(l10n);
    });
  }

  Future<void> _confirmSetAside() async {
    final onSetAside = widget.onSetAside;
    if (_busy || onSetAside == null) return;
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.databaseSetAsideAction,
      message: l10n.databaseSetAsideConfirm,
      okLabel: l10n.databaseSetAsideAction,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok || !mounted) return;
    await _run(
      onSetAside,
      (l10n) => l10n.databaseSetAsideBusy,
      (l10n) => l10n.databaseSetAsideFailed,
    );
  }

  Future<void> _confirmReset() async {
    if (_busy) return;
    final l10n = L10n.of(context);
    final result = await showOkCancelAlertDialog(
      context: context,
      title: l10n.databaseKeyResetAction,
      message: widget.resetMayRemovePin
          ? '${l10n.databaseKeyResetConfirm}\n\n${l10n.databaseKeyResetPinNote}'
          : l10n.databaseKeyResetConfirm,
      okLabel: l10n.databaseKeyResetAction,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (result != OkCancelResult.ok || !mounted) return;
    await _run(
      widget.onReset,
      (l10n) => l10n.databaseKeyResetting,
      (l10n) => l10n.databaseResetIncomplete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                    if (_problem case final problem?)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          problem,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
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
                            Text(_busyLabel, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    if (widget.onSetAside != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _busy ? null : _confirmSetAside,
                        child: Text(l10n.databaseSetAsideAction),
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
      ),
    );
  }
}
