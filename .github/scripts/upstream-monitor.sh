#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026-Present Odango contributors
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Reports new commits of the FluffyChat project as ONE GitHub issue. Read-only for
# the repository contents: it never merges, pushes or changes a branch.
# Needs: git, gh (GH_TOKEN, GH_REPO), checkout with full history.

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/krille-chan/fluffychat}"
UPSTREAM_REPO="${UPSTREAM_URL#https://github.com/}"
LABEL="${LABEL:-upstream-sync}"
MAX_LINES="${MAX_LINES:-150}"
GIT_URL="${UPSTREAM_URL}.git"
ZWSP=$'\xe2\x80\x8b'
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '%s\n' "$*" | tee -a "$SUMMARY"; }

# Stop commit text from pinging users (@name) or linking to our issues (#123).
clean() {
  local s="${1//@/@$ZWSP}"
  printf '%s' "$s" | sed -e 's/</\&lt;/g' -e "s/#\([0-9]\)/#${ZWSP}\1/g" -e "s/\`/'/g"
}

branch="$(git ls-remote --symref "$GIT_URL" HEAD | awk '/^ref:/ { sub("refs/heads/", "", $2); print $2; exit }')"
if [ -z "$branch" ]; then
  echo "::error::Could not determine the default branch of $UPSTREAM_REPO"
  exit 1
fi

git fetch --no-tags --quiet "$GIT_URL" "+refs/heads/${branch}:refs/remotes/upstream/${branch}"
tip="$(git rev-parse "refs/remotes/upstream/${branch}")"
base="$(git merge-base HEAD "$tip" || true)"

# Right side only. --cherry-pick drops commits whose patch we already have
# (cherry-picked with or without -x), --no-merges drops merge commits.
git rev-list --right-only --cherry-pick --no-merges --reverse "HEAD...${tip}" >"$WORK/commits"
count="$(wc -l <"$WORK/commits" | tr -d ' ')"

# Latest issues with our label, any state: dedupe and respect manual closes.
issues="$(gh issue list --label "$LABEL" --state all --limit 30 --json number,state,body)"
open_issue="$(jq -r '[.[] | select(.state == "OPEN")][0].number // empty' <<<"$issues")"
known_heads="$(jq -r '.[] | (.body // "") | capture("<!-- upstream-head: (?<h>[0-9a-f]{40}) -->")? | .h' <<<"$issues")"

if [ "$count" -eq 0 ]; then
  say "Up to date with ${UPSTREAM_REPO}@${branch} (${tip:0:9})."
  if [ -n "$open_issue" ]; then
    gh issue close "$open_issue" --comment "No upstream commits are missing any more (${UPSTREAM_REPO}@${tip:0:9}). Closing."
    say "Closed #${open_issue}."
  fi
  exit 0
fi

if grep -qx "$tip" <<<"$known_heads"; then
  say "${count} upstream commits missing, already reported for ${tip:0:9}. Nothing to do."
  exit 0
fi

{
  echo "<!-- upstream-head: ${tip} -->"
  echo "**${count} commit(s)** of [${UPSTREAM_REPO}](https://github.com/${UPSTREAM_REPO}) (\`${branch}\`) are not in this repository yet."
  echo
  echo "- Compare: https://github.com/${UPSTREAM_REPO}/compare/${base}...${tip}"
  echo "- Upstream head: \`${tip:0:9}\`"
  echo "- Size: $(git diff --shortstat "$base" "$tip" 2>/dev/null || echo unknown)"
  echo
  echo "### Commits (oldest first)"
  echo
  head -n "$MAX_LINES" "$WORK/commits" | while read -r sha; do
    subject="$(clean "$(git show -s --format=%s "$sha")")"
    author="$(clean "$(git show -s --format=%an "$sha")")"
    date="$(git show -s --format=%as "$sha")"
    echo "- [\`${sha:0:9}\`](https://github.com/${UPSTREAM_REPO}/commit/${sha}) ${subject:0:200} (${author}, ${date})"
  done
  if [ "$count" -gt "$MAX_LINES" ]; then
    echo "- … and $((count - MAX_LINES)) more, see the compare link."
  fi
  echo
  echo "Nothing is merged automatically. How to review, merge or cherry-pick: [docs/UPSTREAM.md](https://github.com/${GITHUB_REPOSITORY:-OWNER/REPO}/blob/HEAD/docs/UPSTREAM.md)."
} >"$WORK/body.md"

cat "$WORK/body.md" >>"$SUMMARY"

title="Upstream: ${count} new commit(s) in ${UPSTREAM_REPO}"
gh label create "$LABEL" --force --color 0e8a16 --description "New commits in the upstream project" >/dev/null

if [ -n "$open_issue" ]; then
  gh issue edit "$open_issue" --title "$title" --body-file "$WORK/body.md"
  gh issue comment "$open_issue" --body "Upstream moved: ${count} commit(s) missing now, head \`${tip:0:9}\`. Description updated."
  say "Updated #${open_issue}."
  exit 0
fi

url="$(gh issue create --title "$title" --label "$LABEL" --body-file "$WORK/body.md")"
say "Created ${url}."
