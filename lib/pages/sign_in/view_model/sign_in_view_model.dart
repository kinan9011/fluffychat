// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:odango/config/setting_keys.dart';
import 'package:odango/pages/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:odango/pages/sign_in/view_model/sign_in_state.dart';
import 'package:odango/utils/branding/repo_links.dart';
import 'package:odango/widgets/matrix.dart';

class SignInViewModel extends ValueNotifier<SignInState> {
  final MatrixState matrixService;
  final bool signUp;
  final TextEditingController filterTextController = TextEditingController();

  SignInViewModel(this.matrixService, {required this.signUp})
    : super(SignInState()) {
    refreshPublicHomeservers();
    filterTextController.addListener(_filterHomeservers);
  }

  @override
  void dispose() {
    filterTextController.removeListener(_filterHomeservers);
    filterTextController.dispose();
    super.dispose();
  }

  void _filterHomeservers() {
    final filterText = filterTextController.text.trim().toLowerCase();
    final filteredPublicHomeservers =
        value.publicHomeservers.data
            ?.where(
              (homeserver) =>
                  homeserver.name?.toLowerCase().contains(filterText) ?? false,
            )
            .toList() ??
        [];
    if (filterText.length >= 3 &&
        (filterText.contains('.') || filterText.endsWith('localhost')) &&
        Uri.tryParse(filterText) != null &&
        !filteredPublicHomeservers.any(
          (homeserver) => homeserver.name == filterText,
        )) {
      filteredPublicHomeservers.add(PublicHomeserverData(name: filterText));
    }
    value.filteredPublicHomeservers = filteredPublicHomeservers;
    notifyListeners();
  }

  Future<void> refreshPublicHomeservers() async {
    notifyListeners();
    value.publicHomeservers = AsyncSnapshot.waiting();
    final defaultHomeserverData = PublicHomeserverData(
      name: AppSettings.defaultHomeserver.value,
    );
    List<PublicHomeserverData>? publicHomeservers;
    try {
      final repo = RepoLinks.confirmed();
      if (repo != null) {
        final client = await matrixService.getLoginClient();
        publicHomeservers = await fetchPublicHomeservers(
          client.httpClient,
          repo,
        );
      }
    } catch (e, s) {
      Logs().w('Unable to fetch public homeservers...', e, s);
    }

    if (publicHomeservers == null) {
      value.selectedHomeserver = defaultHomeserverData;
      value.publicHomeservers = AsyncSnapshot.withData(ConnectionState.done, [
        defaultHomeserverData,
      ]);
      notifyListeners();
      _filterHomeservers();
      return;
    }

    if (signUp) {
      publicHomeservers.removeWhere((server) => server.regMethod == null);
    }

    final defaultServer = publicHomeservers.singleWhereOrNull(
      (server) => server.name == AppSettings.defaultHomeserver.value,
    );

    if (defaultServer == null) {
      publicHomeservers.insert(0, defaultHomeserverData);
    }

    value.selectedHomeserver =
        value.selectedHomeserver ?? publicHomeservers.first;
    value.publicHomeservers = AsyncSnapshot.withData(
      ConnectionState.done,
      publicHomeservers,
    );
    notifyListeners();
    _filterHomeservers();
  }

  void selectHomeserver(PublicHomeserverData? publicHomeserverData) {
    value.selectedHomeserver = publicHomeserverData;
    notifyListeners();
  }

  void setLoginLoading(AsyncSnapshot<bool> loginLoading) {
    value.loginLoading = loginLoading;
    notifyListeners();
  }
}

/// Reads the recommended homeserver list of the confirmed repository. Without
/// one nothing is requested and the caller keeps the default homeserver.
@visibleForTesting
Future<List<PublicHomeserverData>?> fetchPublicHomeservers(
  http.Client client,
  RepoLinks? repo,
) async {
  if (repo == null) return null;
  final response = await client.get(repo.homeserverList);
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return (json['public_servers'] as List)
      .map((json) => PublicHomeserverData.fromJson(json))
      .toList();
}
