// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';

class SettingsDivider extends StatelessWidget {
  final double inset;

  const SettingsDivider({
    this.inset = AppSettingsLayout.dividerInset,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: inset),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: AppTokens.of(context).line),
    ),
  );
}

/// A rounded card of rows with an optional uppercase header and a footer
/// (DESIGN.md 7.14).
class SettingsGroup extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> rows;
  final double dividerInset;

  const SettingsGroup({
    required this.rows,
    this.header,
    this.footer,
    this.dividerInset = AppSettingsLayout.dividerInset,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final header = this.header;
    final footer = this.footer;
    return Semantics(
      container: true,
      label: header,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 18,
                  end: 18,
                  bottom: 6,
                ),
                child: Text(
                  header.toUpperCase(),
                  style: TextStyle(
                    color: tokens.mut,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.48,
                  ),
                ),
              ),
            Material(
              color: tokens.surf,
              borderRadius: BorderRadius.circular(AppSettingsLayout.cardRadius),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) SettingsDivider(inset: dividerInset),
                    rows[i],
                  ],
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 18,
                  top: 8,
                  end: 18,
                ),
                child: Text(
                  footer,
                  style: TextStyle(
                    color: tokens.mut,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
