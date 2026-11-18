// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Shown only when the server supports signing in with a QR code. This
/// version cannot scan one, and says so: it points to the account page.
class LinkDeviceCard extends StatelessWidget {
  const LinkDeviceCard({required this.onOpenAccountPage, super.key});

  final VoidCallback? onOpenAccountPage;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final onOpen = onOpenAccountPage;
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xxl),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surf,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        spacing: 8,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: tokens.accs,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.devices_rounded, size: 34, color: tokens.acc),
          ),
          Text(
            l10n.linkDevice,
            style: TextStyle(
              color: tokens.fg,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            l10n.linkDeviceUnsupportedBody(AppSettings.applicationName.value),
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.mut, fontSize: 13.5, height: 1.4),
          ),
          if (onOpen != null)
            Text(
              l10n.linkDeviceAccountPageHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.mut, fontSize: 13.5, height: 1.4),
            ),
          if (onOpen != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: FilledButton(
                key: const ValueKey('link_device_open_account'),
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.acc,
                  foregroundColor: tokens.onacc,
                  minimumSize: const Size(44, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(l10n.openAccountPage),
              ),
            ),
        ],
      ),
    );
  }
}
