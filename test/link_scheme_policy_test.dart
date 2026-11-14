// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/link_scheme_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('linkSchemeAction', () {
    const matrix = <String, LinkSchemeAction>{
      'https://example.org/path': LinkSchemeAction.web,
      'http://example.org': LinkSchemeAction.web,
      'HTTPS://EXAMPLE.ORG': LinkSchemeAction.web,
      'geo:52.5,13.4': LinkSchemeAction.geo,
      'mailto:someone@example.org': LinkSchemeAction.launch,
      'tel:+4912345': LinkSchemeAction.launch,
      'sms:+4912345': LinkSchemeAction.launch,
      'file:///etc/passwd': LinkSchemeAction.block,
      'FILE:///C:/Windows/System32/calc.exe': LinkSchemeAction.block,
      'intent://scan/#Intent;scheme=zxing;package=x;end':
          LinkSchemeAction.block,
      'javascript:alert(1)': LinkSchemeAction.block,
      'JaVaScRiPt:alert(1)': LinkSchemeAction.block,
      'vbscript:msgbox(1)': LinkSchemeAction.block,
      'data:text/html;base64,PHNjcmlwdD4=': LinkSchemeAction.block,
      'blob:https://example.org/uuid': LinkSchemeAction.block,
      'content://com.example.provider/secret': LinkSchemeAction.block,
      'about:blank': LinkSchemeAction.block,
      'jar:file:///x.jar!/': LinkSchemeAction.block,
      'smb://attacker.example/share': LinkSchemeAction.block,
      'ms-msdt:/id PCWDiagnostic': LinkSchemeAction.block,
      'search-ms:query=x': LinkSchemeAction.block,
      'ms-officecmd:x': LinkSchemeAction.block,
      'relative/path': LinkSchemeAction.block,
      'android-app://com.example/https/example.org': LinkSchemeAction.block,
      'ANDROID-APP://com.example': LinkSchemeAction.block,
      'shell:Startup': LinkSchemeAction.block,
      'view-source:https://example.org': LinkSchemeAction.block,
      'filesystem:https://example.org/temporary/x': LinkSchemeAction.block,
      'res://ieframe.dll/x': LinkSchemeAction.block,
      'ie:https://example.org': LinkSchemeAction.block,
      'microsoft-edge:https://example.org': LinkSchemeAction.block,
      'spotify:track:123': LinkSchemeAction.confirm,
      'zoommtg://zoom.us/join': LinkSchemeAction.confirm,
      'ftp://example.org/file': LinkSchemeAction.confirm,
      'custom-app://do/something': LinkSchemeAction.confirm,
      'mailto:a@b.c': LinkSchemeAction.launch,
      'mailto:a@b.c?subject=hi&body=x': LinkSchemeAction.launch,
      'mailto:a@b.c?SUBJECT=x': LinkSchemeAction.launch,
      'mailto:?attach=/home/u/.ssh/id_rsa': LinkSchemeAction.confirm,
      'mailto:a@b.c?Attach=x': LinkSchemeAction.confirm,
      'mailto:a@b.c?subject=hi&attachment=x': LinkSchemeAction.confirm,
      'mailto:a@b.c?%zz=1': LinkSchemeAction.confirm,
      'itms-services://?action=download-manifest&url=https://x.y/m.plist':
          LinkSchemeAction.block,
      'hcp://x': LinkSchemeAction.block,
      r'mk:@MSITStore:C:\x.chm': LinkSchemeAction.block,
      'mhtml:file://x': LinkSchemeAction.block,
      'jnlp://x/a.jnlp': LinkSchemeAction.block,
    };

    for (final entry in matrix.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        expect(linkSchemeAction(Uri.parse(entry.key)), entry.value);
      });
    }
  });

  group('scheme evasion never reaches launch or confirm', () {
    for (final url in [
      ' javascript:alert(1)',
      '\tjavascript:alert(1)',
      'java\tscript:alert(1)',
      'java\nscript:alert(1)',
      '%6Aavascript:alert(1)',
      'javascript%3Aalert(1)',
      '%66ile:///etc/passwd',
      ' file:///etc/passwd',
      '/etc/passwd',
      '//evil.example/x',
      '\\\\server\\share',
    ]) {
      test(url.replaceAll('\n', r'\n').replaceAll('\t', r'\t'), () {
        final uri = Uri.tryParse(url);
        expect(
          uri == null || linkSchemeAction(uri) == LinkSchemeAction.block,
          isTrue,
        );
      });
    }
  });

  group('single-letter schemes (Windows drive paths) are blocked', () {
    for (final url in [
      r'C:\Windows\System32\cmd.exe',
      r'c:\Users\Public\x.exe',
      'c:/x.exe',
      'C:/Windows/System32/calc.exe',
      r'Z:\a',
      'C:x',
      'a:b',
      'x:',
    ]) {
      test(url, () {
        final uri = Uri.tryParse(url);
        expect(uri, isNotNull);
        expect(uri!.scheme.length, 1);
        expect(linkSchemeAction(uri), LinkSchemeAction.block);
      });
    }
  });
}
