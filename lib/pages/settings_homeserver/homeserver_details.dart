// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import 'homeserver_details_view.dart';

class HomeserverDetails extends StatefulWidget {
  const HomeserverDetails({super.key});

  @override
  HomeserverDetailsController createState() => HomeserverDetailsController();
}

class HomeserverDetailsController extends State<HomeserverDetails> {
  @override
  Widget build(BuildContext context) => HomeserverDetailsView(this);
}
