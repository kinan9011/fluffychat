// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';
import 'package:odango/config/app_tokens.dart';
import 'package:odango/config/design_constants.dart';

/// Two or three way switch on a `--surf2` track (mockup scope switch).
class SettingsSegmented<T> extends StatelessWidget {
  static ValueKey<String> segmentKey(Object value) =>
      ValueKey('settings_segment_$value');

  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  const SettingsSegmented({
    required this.items,
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xl),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: tokens.surf2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (item, label) in items)
            Expanded(
              child: Semantics(
                button: true,
                selected: item == value,
                label: label,
                excludeSemantics: true,
                onTap: () => onChanged(item),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(item),
                  child: Container(
                    key: segmentKey(item as Object),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    constraints: const BoxConstraints(minHeight: 36),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: item == value
                        ? BoxDecoration(
                            color: tokens.surf,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: tokens.shadow,
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          )
                        : null,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: item == value ? tokens.fg : tokens.mut,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
