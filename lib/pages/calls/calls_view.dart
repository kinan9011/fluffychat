// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/calls/calls_page.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';

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
        padding: EdgeInsetsDirectional.fromSTEB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
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
                        : l10n.groupCallsComingLater,
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
