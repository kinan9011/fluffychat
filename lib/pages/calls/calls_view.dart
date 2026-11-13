// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/design_constants.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/calls/calls_page.dart';
import 'package:fluffychat/utils/server_capabilities/server_capabilities.dart';
import 'package:material_ui/material_ui.dart';

class CallsView extends StatelessWidget {
  final CallsController controller;

  const CallsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final tokens = AppTokens.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: Text(l10n.calls)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.s,
              AppSpacing.xl,
              AppSpacing.s,
            ),
            child: Text(
              l10n.ongoingGroupCalls,
              style: theme.textTheme.labelLarge?.copyWith(color: tokens.acc),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surf2,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: FutureBuilder<ServerCapabilities>(
                future: controller.capabilities,
                builder: (context, snapshot) {
                  final unsupported =
                      snapshot.data?[ServerFeature.groupCalls] ==
                      FeatureSupport.unsupported;
                  return Text(
                    unsupported
                        ? l10n.groupCallsNotSupported
                        : l10n.noOngoingGroupCalls,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.mut,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
