// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

class AppLockUnavailablePage extends StatefulWidget {
  const AppLockUnavailablePage({required this.onRetry, super.key});

  final Future<void> Function() onRetry;

  static Widget app({required Future<void> Function() onRetry}) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    builder: (context, child) => Theme(
      data: FluffyThemes.buildTheme(context, Brightness.light),
      child: child!,
    ),
    home: AppLockUnavailablePage(onRetry: onRetry),
  );

  @override
  State<AppLockUnavailablePage> createState() => _AppLockUnavailablePageState();
}

class _AppLockUnavailablePageState extends State<AppLockUnavailablePage> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.appLockUnavailable,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.appLockUnavailableBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _retry,
                    child: Text(l10n.tryAgain),
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
