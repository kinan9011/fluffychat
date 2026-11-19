// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/utils/chat/display_text.dart';

/// "‹Name› signed in on a new device · Verify" (DESIGN.md 9.18, mockup C8).
/// The name is one bounded line of its own, so it can never push the warning
/// out of view.
/// Verify only opens the existing encryption screen, which explains what
/// verifying means and asks first. This widget has no access to trust: it
/// cannot verify, block or start a verification itself.
class NewDeviceBanner extends StatelessWidget {
  final String name;
  final double height;
  final VoidCallback onVerify;
  final VoidCallback onDismiss;

  const NewDeviceBanner({
    required this.name,
    required this.height,
    required this.onVerify,
    required this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final l10n = L10n.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Container(
        height: height,
        padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
        decoration: BoxDecoration(
          color: tokens.warnS,
          borderRadius: BorderRadius.circular(AppRadius.banner),
        ),
        child: Row(
          spacing: 10,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.gpp_maybe_rounded,
                size: 22,
                color: tokens.warn,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRect(
                    child: Text(
                      isolatedDisplayText(name, maxGraphemes: 24),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.fg,
                        fontSize: 13.5,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    l10n.newDeviceBannerSubtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tokens.fg,
                      fontSize: 13.5,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: tokens.acc,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onVerify,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    minWidth: 44,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        l10n.verify,
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
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: l10n.close,
              color: tokens.mut,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
