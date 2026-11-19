<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Privacy

Odango is a client for the Matrix network. This is what it does and does not do with your data. The legal privacy policy of this build is at <https://odango.swovo.de/privacy>.

- **Your messages and account** go only to the homeserver you sign in to. Odango has no server of its own. What your homeserver and the servers of the people you talk to do with your data is up to them.
- **No analytics and no tracking.** Odango includes no analytics or advertising code.
- **No automatic crash reports.** Reports are off by default and, if you turn them on, still only open a prefilled issue on the project repository when you tap *Report*.
- **Requests to the project repository on GitHub** are off until the owner of this build confirms the repository (`repositoryConfirmed`, see the README). The built-in repository address is only assumed, so a fresh build makes none of them. Once confirmed, GitHub sees these requests like any other website visit:
  - the sign-in and sign-up page loads the list of recommended homeservers from `raw.githubusercontent.com` every time it opens;
  - tapping *Report* on an error searches existing issues at `api.github.com/search/issues` with a short hash of the error, not its text;
  - on Windows, once a day Odango asks the releases of the repository whether a newer installer exists (turn it off with `checkForUpdates`).
- **Push notifications** need a push gateway. This build has none configured; see the README.
- **Location messages** show a map that is loaded from the OpenStreetMap tile servers (`tile.openstreetmap.org`) whenever such a message is on screen. OpenStreetMap sees your IP address and the map area. This is inherited from the upstream app and not yet a setting.
- **UnifiedPush** (only if you choose it) registers with the public UnifiedPush Matrix gateway or a gateway of your own.
- **Encrypted rooms:** message content of encrypted rooms is kept only inside the encrypted local database, never in plain text preferences or logs.
- **Your data is local.** There is no migration from FluffyChat or other apps: Odango keeps its own storage under the app id `com.swovo.odango`.
