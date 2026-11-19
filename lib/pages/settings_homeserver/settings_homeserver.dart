// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/l10n/l10n.dart';
import 'package:odango/pages/settings_homeserver/settings_homeserver_view.dart';
import 'package:odango/utils/bounded_body.dart';
import 'package:odango/utils/server_capabilities/homeserver_report.dart';
import 'package:odango/utils/server_capabilities/server_capabilities.dart';
import 'package:odango/widgets/matrix.dart';
import 'package:share_plus/share_plus.dart';

class SettingsHomeserver extends StatefulWidget {
  const SettingsHomeserver({super.key});

  @override
  SettingsHomeserverController createState() => SettingsHomeserverController();
}

class SettingsHomeserverController extends State<SettingsHomeserver> {
  ServerCapabilities caps = ServerCapabilities.unknown;
  HomeserverInfo? info;
  bool loading = true;
  late Client _client;

  bool get _same => mounted && identical(Matrix.of(context).client, _client);

  /// The server answered at least one of the capability questions.
  bool get online => homeserverFeatureOrder.any(
    (feature) => caps[feature] != FeatureSupport.unknown,
  );

  @override
  void initState() {
    super.initState();
    _client = Matrix.of(context).client;
    caps = Matrix.of(context).serverCapabilities.cached(_client);
    unawaited(refresh());
  }

  Future<void> refresh({bool force = false}) async {
    final asked = _client;
    final matrix = Matrix.of(context);
    if (mounted) setState(() => loading = true);
    final results = await Future.wait<Object?>([
      matrix.serverCapabilities.load(asked, force: force),
      _fetchInfo(asked),
    ]);
    if (!_same || !identical(asked, _client)) return;
    setState(() {
      caps = results.first! as ServerCapabilities;
      info = results[1] as HomeserverInfo?;
      loading = false;
    });
  }

  Future<HomeserverInfo> _fetchInfo(Client client) async {
    final userDomain = client.userID?.domain ?? client.homeserver?.host ?? '';
    final software = await _federationVersion(client, userDomain);
    int? upload;
    try {
      upload = (await client.getConfig()).mUploadSize;
    } catch (_) {
      upload = null;
    }
    return HomeserverInfo(
      domain: userDomain,
      software: software?.name,
      version: software?.version,
      uploadLimitBytes: upload,
    );
  }

  Future<({String name, String version})?> _federationVersion(
    Client client,
    String domain,
  ) async {
    if (domain.isEmpty) return null;
    var base = Uri(scheme: 'https', host: domain, port: 8448);
    try {
      final body = await readBoundedBody(
        client.httpClient,
        Uri.https(domain, '/.well-known/matrix/server'),
      );
      final declared = (jsonDecode(body!) as Map)['m.server'];
      final parsed = declared is String && declared.length < 270
          ? Uri.tryParse('https://$declared')
          : null;
      if (parsed != null && parsed.hasAuthority && parsed.host.isNotEmpty) {
        base = parsed.hasPort ? parsed : parsed.replace(port: 8448);
      }
    } catch (_) {
      Logs().v('[Homeserver] no server well-known, using the default port');
    }
    if (!isTrustedFederationHost(
      base.host,
      userDomain: domain,
      homeserverHost: client.homeserver?.host,
    )) {
      Logs().w('[Homeserver] the declared federation host is not asked');
      return null;
    }
    try {
      final body = await readBoundedBody(
        client.httpClient,
        base.resolveUri(Uri(path: '/_matrix/federation/v1/version')),
      );
      return parseServerVersion(jsonDecode(body!));
    } catch (_) {
      return null;
    }
  }

  String report() => buildAdminReport(
    info: info ?? HomeserverInfo(domain: _client.userID?.domain ?? ''),
    caps: caps,
    appName: AppSettings.applicationName.value,
    l10n: L10n.of(context),
  );

  Future<void> shareWithAdmin() async {
    final text = report();
    final subject = L10n.of(context).adminReportTitle;
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  @override
  Widget build(BuildContext context) => SettingsHomeserverView(this);
}
