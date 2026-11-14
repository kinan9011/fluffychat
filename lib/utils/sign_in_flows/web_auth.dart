// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/launch_web_url.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart';

export 'package:flutter_web_auth_2/flutter_web_auth_2.dart'
    show FlutterWebAuth2Options;

class UnsafeAuthUrlException implements Exception {
  const UnsafeAuthUrlException();

  @override
  String toString() => 'UnsafeAuthUrlException';
}

typedef WebAuthenticate =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
      required FlutterWebAuth2Options options,
    });

Future<String> _authenticate({
  required String url,
  required String callbackUrlScheme,
  required FlutterWebAuth2Options options,
}) => FlutterWebAuth2.authenticate(
  url: url,
  callbackUrlScheme: callbackUrlScheme,
  options: options,
);

/// The address comes from the server (OIDC metadata, SSO redirect). On Windows
/// and Linux the plugin hands it to the operating system unchecked, so only
/// http(s) addresses with a host may reach it.
Future<String> authenticateInBrowser({
  required String url,
  required String callbackUrlScheme,
  FlutterWebAuth2Options options = const FlutterWebAuth2Options(),
  @visibleForTesting WebAuthenticate authenticate = _authenticate,
}) async {
  if (!isLaunchableWebUrl(url)) {
    Logs().w('Refused a sign-in address that is not a web address');
    throw const UnsafeAuthUrlException();
  }
  return await authenticate(
    url: url,
    callbackUrlScheme: callbackUrlScheme,
    options: options,
  );
}
