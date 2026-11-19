// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';
import 'package:odango/config/themes.dart';

/// Page frame of every settings screen: 44 px round back button, 22 px title,
/// scrolling column of cards, optional pinned bottom widget.
class SettingsScaffold extends StatelessWidget {
  @visibleForTesting
  static const backKey = ValueKey('settings_back');

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;
  final List<Widget>? actions;
  final bool largeTitle;

  const SettingsScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.bottom,
    this.actions,
    this.largeTitle = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final columnMode = FluffyThemes.isColumnMode(context);
    final subtitle = this.subtitle;
    final bottom = this.bottom;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: columnMode || !canPop ? AppSpacing.xxxl : 0,
        leading: columnMode || !canPop
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: Center(
                  child: Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).backButtonTooltip,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      child: InkResponse(
                        key: backKey,
                        onTap: () => Navigator.of(context).maybePop(),
                        radius: 24,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: tokens.surf2,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 23,
                            color: tokens.fg,
                            textDirection: Directionality.of(context),
                            semanticLabel: null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        leadingWidth: columnMode || !canPop ? 0 : 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.fg,
                fontSize: largeTitle ? 26 : 22,
                fontWeight: FontWeight.w700,
                letterSpacing: largeTitle ? -0.52 : -0.22,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tokens.mut, fontSize: 12.5),
              ),
          ],
        ),
        actions: actions,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSettingsLayout.maxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSettingsLayout.sideMargin,
                      0,
                      AppSettingsLayout.sideMargin,
                      AppSpacing.huge,
                    ),
                    children: children,
                  ),
                ),
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}
