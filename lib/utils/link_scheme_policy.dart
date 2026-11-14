// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

enum LinkSchemeAction { web, geo, launch, confirm, block }

const _launchSchemes = {'mailto', 'tel', 'sms'};

const _blockedSchemes = {
  'file',
  'intent',
  'javascript',
  'vbscript',
  'data',
  'blob',
  'content',
  'about',
  'jar',
  'smb',
  'search-ms',
  'android-app',
  'shell',
  'view-source',
  'filesystem',
  'res',
  'ie',
  'microsoft-edge',
  'itms-services',
  'hcp',
  'mk',
  'mhtml',
  'jnlp',
};

const _mailtoQueryKeys = {'subject', 'body', 'cc', 'bcc', 'to'};

bool _isPlainMailto(Uri uri) {
  try {
    return uri.queryParametersAll.keys.every(
      (k) => _mailtoQueryKeys.contains(k.toLowerCase()),
    );
  } catch (_) {
    return false;
  }
}

LinkSchemeAction linkSchemeAction(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return LinkSchemeAction.web;
  if (scheme == 'geo') return LinkSchemeAction.geo;
  if (scheme == 'mailto' && !_isPlainMailto(uri)) {
    return LinkSchemeAction.confirm;
  }
  if (_launchSchemes.contains(scheme)) return LinkSchemeAction.launch;
  // A single letter is a Windows drive (C:\x.exe), never a real URL scheme.
  if (scheme.length <= 1 ||
      scheme.startsWith('ms-') ||
      _blockedSchemes.contains(scheme)) {
    return LinkSchemeAction.block;
  }
  return LinkSchemeAction.confirm;
}
