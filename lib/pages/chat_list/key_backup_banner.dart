// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/crypto_identity.dart' as crypto_identity;

class KeyBackupBanner extends StatefulWidget {
  final Client client;

  const KeyBackupBanner({required this.client, super.key});

  static final Set<String> _dismissed = {};
  static final Map<String, bool> _needsSetupByClient = {};

  static void forget(String clientName) {
    _dismissed.remove(clientName);
    _needsSetupByClient.remove(clientName);
  }

  @visibleForTesting
  static void resetForTest() {
    _dismissed.clear();
    _needsSetupByClient.clear();
  }

  @override
  State<KeyBackupBanner> createState() => _KeyBackupBannerState();
}

class _KeyBackupBannerState extends State<KeyBackupBanner> {
  bool _needsSetup = false;

  @override
  void initState() {
    super.initState();
    crypto_identity.cryptoIdentityRevision.addListener(_recheck);
    final known = KeyBackupBanner._needsSetupByClient[widget.client.clientName];
    _needsSetup = known ?? false;
    if (known == null) unawaited(_check());
  }

  @override
  void dispose() {
    crypto_identity.cryptoIdentityRevision.removeListener(_recheck);
    super.dispose();
  }

  void _recheck() => unawaited(_check());

  @override
  void didUpdateWidget(KeyBackupBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.client, widget.client)) return;
    final known = KeyBackupBanner._needsSetupByClient[widget.client.clientName];
    _needsSetup = known ?? false;
    if (known == null) unawaited(_check());
  }

  Future<void> _check() async {
    final client = widget.client;
    bool? connected;
    try {
      connected = await crypto_identity.cryptoIdentityConnected(client);
    } catch (_) {
      Logs().w('[KeyBackup] state check failed');
    }
    KeyBackupBanner._needsSetupByClient[client.clientName] = connected == false;
    if (!mounted || !identical(widget.client, client)) return;
    setState(() => _needsSetup = connected == false);
  }

  Future<void> _setUp() => context.push('/backup');

  @override
  Widget build(BuildContext context) {
    if (!_needsSetup ||
        KeyBackupBanner._dismissed.contains(widget.client.clientName)) {
      return const SizedBox.shrink();
    }
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    final big = MediaQuery.textScalerOf(context).scale(16) > 20.8;
    final pill = Material(
      color: tokens.acc,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _setUp,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                l10n.setUp,
                style: TextStyle(
                  color: tokens.onacc,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      child: Container(
        margin: const EdgeInsetsDirectional.only(start: 12, end: 12, bottom: 6),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: tokens.warnS,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          spacing: 12,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.key_rounded, size: 24, color: tokens.warn),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    l10n.keyBackupBannerTitle,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    l10n.keyBackupBannerSubtitle,
                    style: TextStyle(color: tokens.mut, fontSize: 12.5),
                  ),
                  if (big)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 6),
                      child: pill,
                    ),
                ],
              ),
            ),
            if (!big) pill,
            IconButton(
              tooltip: l10n.closeKeyBackupReminder,
              icon: Icon(Icons.close_rounded, size: 20, color: tokens.mut),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => setState(
                () => KeyBackupBanner._dismissed.add(widget.client.clientName),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
