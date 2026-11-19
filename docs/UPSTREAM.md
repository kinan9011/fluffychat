<!--
SPDX-FileCopyrightText: 2026-Present Odango contributors

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Following upstream (FluffyChat)

## 1. Relationship

Odango is an independent fork of [FluffyChat](https://github.com/krille-chan/fluffychat). It left the GitHub fork network, so GitHub no longer shows or syncs it as a fork. The Git history is the full FluffyChat history plus Odango's own commits. Both are AGPL-3.0-or-later. Upstream copyright and SPDX headers stay as they are (see [NOTICE.md](../NOTICE.md)). Odango is not affiliated with or endorsed by the FluffyChat project.

Upstream changes are **never merged automatically**. A person reviews them and brings them in through a pull request.

## 2. Remotes

| Remote | URL | Use |
|---|---|---|
| `origin` | this repository | push and pull |
| `upstream` | `https://github.com/krille-chan/fluffychat.git` | fetch only (push URL is `DISABLE`) |

```sh
git remote add upstream https://github.com/krille-chan/fluffychat.git
git remote set-url --push upstream DISABLE
git fetch upstream --tags
git remote -v
```

The upstream default branch is `main`. Check it with `git ls-remote --symref upstream HEAD` if you suspect it changed.

## 3. Monitoring

`.github/workflows/upstream-monitor.yml` runs daily (05:17 UTC) and on demand (`gh workflow run upstream-monitor.yml`). It runs `.github/scripts/upstream-monitor.sh`, which:

- compares our default branch with upstream's default branch, ignoring merge commits and commits we already cherry-picked;
- keeps **one** issue labelled `upstream-sync` with the compare link and one line per missing commit;
- does nothing when the upstream head is the same as the one already reported, including when you closed that issue by hand;
- updates the issue and adds one comment when upstream moved on, and closes it when nothing is missing any more.

The workflow has `contents: read` and `issues: write`. It cannot push or merge. Issues must be enabled on the repository.

Public repositories get their scheduled workflows disabled after 60 days without repository activity. If the monitor stops, run `gh workflow enable upstream-monitor.yml`.

## 4. Inspect new commits

```sh
git fetch upstream
git log --oneline --no-merges --cherry-pick --right-only main...upstream/main   # what is missing
git diff --stat main...upstream/main                                            # size of the change
git diff main...upstream/main -- lib/pages/chat                                 # one area
git show <sha>                                                                  # one commit
```

## 5. Option A: merge upstream (many changes, or you are far behind)

```sh
git fetch upstream
git switch -c upstream-sync/$(date +%F) main
git merge --no-ff upstream/main            # stop on conflicts, nothing is lost
git diff --name-only --diff-filter=U       # conflicted files
```

Resolve (section 7), then run the checks from CI:

```sh
flutter pub get
dart format lib/ test/ --set-exit-if-changed
flutter analyze
flutter test
```

Push the branch and open a pull request into `main`:

```sh
git push -u origin HEAD
gh pr create --base main --title "chore: merge upstream FluffyChat" --body "See the upstream-sync issue."
```

`integrate.yaml` runs on the pull request. A person reviews and merges it. **Merge it with "Create a merge commit"**, not squash or rebase: squashing drops upstream's commits from our ancestry and the monitor would report them again. Do not rebase and do not force-push shared branches.

## 6. Option B: cherry-pick (single fixes)

```sh
git switch -c upstream-pick/<topic> main
git cherry-pick -x <sha> [<sha> ...]       # -x records the upstream commit in the message
git push -u origin HEAD && gh pr create --base main
```

Prefer cherry-picking for a security fix, a crash fix or one small feature, when a merge would pull in UI or branding churn that conflicts with the Odango redesign. Prefer a merge when you are many commits behind, when commits depend on each other, or when you touch the same files anyway. Picked commits are recognised by the monitor and stop being reported.

## 7. Common conflicts

Rule: **keep Odango's identity and UI, take upstream's logic and security fixes.**

| Where | Resolve by |
|---|---|
| App name, ids, URL schemes, logos, store metadata (`com.swovo.odango`, `android/`, `ios/`, `macos/`, `snap/`, `assets/logo`) | Keep ours. Check that new upstream files don't reintroduce the FluffyChat name or ids. |
| Pages redesigned in Odango (`lib/pages/chat*`, `lib/widgets/layouts`, settings, search) | Port the upstream logic change into our widgets by hand, do not take their layout. |
| `pubspec.yaml`, `pubspec.lock` | Take upstream's dependency versions, keep our additions, then run `flutter pub get` and commit the lock. |
| `lib/l10n/intl_en.arb` | Keep both sets of keys. Other `.arb` files come from Weblate: take upstream's. |
| `README.md`, `NOTICE.md`, `docs/` | Keep ours. Update the README only to credit new upstream features. |
| `.github/workflows/` | Keep ours unless the upstream change fixes a real problem. Do not enable upstream's release workflows without your own secrets. |
| Generated or lock files | Never hand-merge: regenerate. |

Turn on `git config rerere.enabled true` so Git remembers how you resolved a conflict. To give up: `git merge --abort`.

## 8. Maintaining the monitor

- **Schedule:** edit `cron` in `.github/workflows/upstream-monitor.yml` (UTC, avoid the top of the hour).
- **Different upstream:** change `UPSTREAM_REPO` in the workflow.
- **Label or limits:** `LABEL` and `MAX_LINES` are environment variables of the script.
- **Silence it:** `gh workflow disable upstream-monitor.yml`.
- **Test it:** `gh workflow run upstream-monitor.yml`, then `gh run list --workflow upstream-monitor.yml`.
- A failing run (network, issues disabled) shows in the Actions tab. It does not change anything.

## 9. Restore tracking

| Problem | Fix |
|---|---|
| `upstream` remote missing or wrong | `git remote add upstream https://github.com/krille-chan/fluffychat.git` or `git remote set-url upstream <url>`, then `git fetch upstream` |
| Upstream branch renamed | `git ls-remote --symref upstream HEAD`, then use the new name in the commands above. The script finds it by itself. |
| Monitor not running | `gh workflow enable upstream-monitor.yml` (60-day inactivity rule), check that the file is on the default branch |
| No issue is created | Issues disabled: `gh repo edit --enable-issues` |
| Everything is reported again after a merge | The PR was squashed or rebased. The next real merge of `upstream/main` fixes it. |
| Lost the remote history | `git fetch upstream --tags`. The shared history is already part of this repository. |
