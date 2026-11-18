<!--
SPDX-FileCopyrightText: 2026 Contributors to FluffyChat
SPDX-License-Identifier: Apache-2.0
-->

# Patches against receive_sharing_intent 1.9.0

Base: `receive_sharing_intent` 1.9.0 from pub.dev (sha256 `72f229a38f2910029c11d840770c173b27072e348ef3376130b37514bc4556f6`). Licence: Apache-2.0, the upstream `LICENSE` is unchanged (upstream ships no NOTICE file). Included: `LICENSE`, `pubspec.yaml`, `lib/`, `android/`, `ios/`. Not included: `example/`, `test/`, `README.md`, `CHANGELOG.md`, `scripts/`.

## Why

The upstream native code names the copy of a shared file after the **sender's** display name and writes it into the app's own storage:

- Android `FileDirectory.kt:104` `File(context.cacheDir, fileName)` (`_display_name` of the sender's provider) → `../shared_prefs/...` overwrites app-private files; any existing cache name is overwritten. `ReceiveSharingIntentPlugin.kt:163` names the video thumbnail after the file name.
- iOS `RSIShareViewController.swift:200-236, 384-394, 422-427` copies to `<App Group container>/<lastPathComponent>` after deleting whatever is there; that container is the database directory of the app.

Upstream issues: KasemJaffer/receive_sharing_intent #181, #411, #417 (all open, 1.9.0 is the latest release). FluffyChat issue: fluffychat#197.

## How to see the patch

```sh
diff -ru ~/.pub-cache/hosted/pub.dev/receive_sharing_intent-1.9.0 third_party/receive_sharing_intent
```

## Removal condition

Delete this directory and put `receive_sharing_intent: ^<fixed version>` back into `pubspec.yaml` as soon as upstream sanitises names and copies into a private directory. The Dart tests (`test/shared_file_filter_test.dart`, `test/shared_media_canary_test.dart`) keep guarding the app side either way.

## Hunks (line numbers: upstream 1.9.0 → patched)

| File | Upstream lines → patched lines | Change |
|---|---|---|
| `pubspec.yaml` | 1-7 → 1-9 | modification notice, version `1.9.0+fluffychat.1`, `publish_to: none` |
| `android/build.gradle` | +53-57 | `testImplementation 'junit:junit:4.12'` for the new unit tests (4.13.2 is not in the offline Gradle cache; test scope only, never shipped) |
| `android/.../FileDirectory.kt` | whole object (upstream 18-171 → 20-138) | `getAbsolutePath` accepts only `content://`, rejects providers of this app (`isOwnProvider`), always copies through `ContentResolver` into `cache/receive_sharing_intent/<random UUID>/<sanitised name>` (`newShareDir`, `safeFileName`), caps the copy at 512 MiB (`copyCapped`), deletes the directory on any failure (`copyInto`, pure JVM, unit-tested). Removed: raw-path branches (`file://`, `/storage/...`, `_data`), `getDataColumn` (upstream 90-145), the three `is*Document` helpers (152-170), the DocumentsContract/MediaStore imports. |
| `android/.../ReceiveSharingIntentPlugin.kt` | +1-2 (header) | modification notice |
| | 139-150 → 141-153 | an entry without a safe copy and without text is skipped (`val value = path ?: text ?: return null`); `put("path", value)`; a text-only fallback (no safe copy) is typed `text` (`MediaType.forShare`) whatever the intent mime type says |
| | 154-177 → 157-188 | video thumbnail goes to `FileDirectory.newShareDir(cacheDir)/thumbnail.png`; the body is wrapped in `try/catch` (hostile media no longer crashes the share) |
| `android/src/test/.../FileDirectoryTest.kt`, `MediaTypeTest.kt` | new | JVM unit tests for the helpers, `copyInto` cleanup and the text fallback type |
| `ios/.../RSIShareViewController.swift` | +7-8 (header) | modification notice |
| | 187-189 → 189-193 | the image temp file goes to a fresh share directory |
| | 202 → 208-212 | the copy of a file goes to a fresh share directory |
| | 351-357 → 361-367 | `getFileName` sanitises `lastPathComponent` |
| | 369-377 → 379-384, 383-391 → 390-395 | `writeTempFile` and `copyFile` no longer `removeItem` an existing target: the target directory is always new and empty, so a clash fails instead of replacing a file (deviates from plan §4.1.5, safer) |
| | 397-413 → 401-409 | `getVideoInfo`: no share directory means no thumbnail (the duration is still returned) |
| | 419-430 → 425-486 | `getThumbnailPath()` is optional and uses a fresh directory; new `makeShareDirectory()`, `sanitizedFileName(_:)` and `cappedFileName(_:)` (at most 200 UTF-8 bytes, a 1-16 character extension is kept) |

`ios/.../ReceiveSharingIntentPlugin.swift`, `RSIComposeView.swift`, `Package.swift`, `lib/**`, `android/{settings.gradle,gradle.properties,src/main/AndroidManifest.xml}` are byte-identical to upstream.

**Swift is not compiled in CI or in this repository's Linux environment.** Build the share extension on a Mac before a release.

## Contract the app relies on

Every file reported for a `content://` share lives at `<cache or App Group container>/receive_sharing_intent/<uuid>/<name>`. `lib/utils/shared_media_filter.dart` accepts nothing else.
