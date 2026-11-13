// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_tokens.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/glass_surface.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/golden.dart';

class _TokenSheet extends StatelessWidget {
  const _TokenSheet();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final swatches = {
      'bg': t.bg,
      'surf': t.surf,
      'surf2': t.surf2,
      'line': t.line,
      'fg': t.fg,
      'mut': t.mut,
      'acc': t.acc,
      'accs': t.accs,
      'ok': t.ok,
      'warn': t.warn,
      'warnS': t.warnS,
      'red': t.red,
      'mbad': t.mbad,
      'outS': t.outS,
      'out': t.out,
      'in': t.inBubble,
    };
    return DecoratedBox(
      decoration: BoxDecoration(gradient: t.wallG),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in swatches.entries)
                  Container(
                    width: 82,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.value,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      entry.key,
                      style: text.labelSmall!.copyWith(
                        color: entry.value.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GlassSurface(
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Chats', style: text.headlineMedium),
                    Text('Screen title', style: text.titleLarge),
                    Text('Anna Becker', style: text.titleMedium),
                    Text('Message body text 15.5', style: text.bodyLarge),
                    Text(
                      '@anna:example.org',
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        for (final id in ['@anna:x', '@kim:x', '@lukas:x'])
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 6),
                            child: CircleAvatar(
                              backgroundColor: id.avatarColor,
                              child: Text(
                                id.substring(1, 3).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'JetBrainsMono',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        Text(
                          'Kim',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: 'Kim'.nameColor(
                              Theme.of(context).brightness,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testGoldens('design tokens sheet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    await expectGoldenVariants(
      tester,
      'app_tokens_sheet',
      const _TokenSheet(),
      size: const Size(400, 420),
    );
  });
}
