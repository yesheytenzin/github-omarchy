#!/usr/bin/env bash
# End-to-end tests for the github-oma plugin.
#
# Drives the real helper against a fake `gh` (tests/fakebin/gh) inside a
# sandboxed HOME, then exercises the QML model with qml6 when it is
# available. Nothing here touches the network or the user's real config.

set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$PLUGIN_DIR/bin/github-oma"

PASS=0
FAIL=0

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; [[ $# -gt 1 ]] && printf '       %s\n' "$2"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi; }
contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "[$2] does not contain [$3]"; fi; }
jqis() { local got; got="$(printf '%s' "$2" | jq -r "$3" 2>/dev/null)"; check "$1" "$got" "$4"; }

SANDBOX="$(mktemp -d)"

cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

export HOME="$SANDBOX/home"
export GITHUB_OMA_GH="$PLUGIN_DIR/tests/fakebin/gh"
export GITHUB_OMA_STATE_DIR="$SANDBOX/state"
export FAKE_GH_LOG="$SANDBOX/gh.log"
export FAKE_GH_STATE="$SANDBOX/fake-state"
mkdir -p "$HOME" "$GITHUB_OMA_STATE_DIR"

CACHE="$GITHUB_OMA_STATE_DIR/cache.json"

fresh() {
  rm -rf "$GITHUB_OMA_STATE_DIR" "$FAKE_GH_STATE"
  mkdir -p "$GITHUB_OMA_STATE_DIR"
  : > "$FAKE_GH_LOG"
}

echo "== fresh refresh =="

out="$("$CLI" refresh --json 2>/dev/null)"
status=$?
check "refresh exits 0" "$status" "0"
jqis "the payload says ok" "$out" '.ok' "true"
jqis "the login is cached for the next run" "$out" '.login' "yesheytenzin"
jqis "personal issues are counted" "$out" '.scopes.mine.issues.count' "3"
jqis "personal issues come as rows" "$out" '.scopes.mine.issues.items | length' "2"
jqis "a search that tops out says so" "$out" '.scopes.mine.issues.truncated' "true"
jqis "assigned items are flagged" "$out" '[.scopes.mine.issues.items[] | select(.number == 3) | .needsMe][0]' "true"
jqis "unassigned items are not" "$out" '[.scopes.mine.issues.items[] | select(.number == 4) | .needsMe][0]' "false"
jqis "review requests are flagged" "$out" '.scopes.mine.prs.items[0].needsMe' "true"
jqis "the org list is discovered" "$out" '.orgs | join(",")' "acme-corp,OtherOrg"
jqis "org searches merge into one bucket" "$out" '.scopes.orgs.issues.count' "4"
jqis "org PRs merge across orgs" "$out" '.scopes.orgs.prs.count' "1"
jqis "org rows carry their scope" "$out" '.scopes.orgs.issues.items[0].scope' "orgs"
check "the cache is written" "$([[ -f $CACHE ]] && echo yes || echo no)" "yes"

contains "the personal query filters by owner" "$(cat "$FAKE_GH_LOG")" "user:yesheytenzin"
contains "the personal query asks for involvement" "$(cat "$FAKE_GH_LOG")" "involves:@me"
contains "the org query filters by org" "$(cat "$FAKE_GH_LOG")" "org:acme-corp"
contains "PRs are searched for explicitly" "$(cat "$FAKE_GH_LOG")" "is:pr is:open"
check "one GraphQL call per refresh" "$(grep -c 'api graphql' "$FAKE_GH_LOG")" "1"
check "the login is resolved once" "$(grep -c 'api user ' "$FAKE_GH_LOG")" "1"

echo "== cache =="

out="$("$CLI" refresh --max-age 300 2>/dev/null)"
check "a fresh cache exits 0" "$?" "0"
jqis "a fresh cache is served" "$out" '.cached' "true"
check "a fresh cache makes no GraphQL call" "$(grep -c 'api graphql' "$FAKE_GH_LOG")" "1"

printf 'not json at all' > "$CACHE"
out="$("$CLI" refresh --json 2>/dev/null)"
jqis "a corrupt cache is ignored, not fatal" "$out" '.ok' "true"

echo "== repos =="

out="$("$CLI" refresh --max-age 300 2>/dev/null)"
jqis "the account's own repos are counted" "$out" '.repos.mine.count' "2"
jqis "own repos come as rows" "$out" '.repos.mine.items | length' "2"
jqis "org repos come from the org query" "$out" '.repos.orgs.count' "2"
jqis "org repo rows arrive" "$out" '.repos.orgs.items | length' "2"
jqis "starred repos sort first inside a bucket" "$out" '.repos.mine.items[0].nameWithOwner' "yesheytenzin/auto-workspace"
jqis "the freshest push follows the starred one" "$out" '.repos.mine.items[1].nameWithOwner' "yesheytenzin/job_application_portal"
jqis "org repos sort by push too" "$out" '.repos.orgs.items[0].nameWithOwner' "acme-corp/widgets"
jqis "repo rows are typed for the row renderer" "$out" '.repos.mine.items[0].kind' "repo"
jqis "a complete bucket is not truncated" "$out" '.repos.mine.truncated' "false"
jqis "no collaborator bucket is fetched" "$out" '.repos.other' "null"

echo "== failures =="

fresh
out="$(GITHUB_OMA_GH=/nonexistent/gh "$CLI" refresh --json 2>/dev/null)"
check "a missing gh exits 1" "$?" "1"
jqis "a missing gh is typed" "$out" '.error' "no-gh"
contains "a missing gh names the install command" "$out" "github-cli"

fresh
out="$(FAKE_GH_MODE=no-auth "$CLI" refresh --json 2>/dev/null)"
check "an unauthenticated gh exits 1" "$?" "1"
jqis "an unauthenticated gh is typed" "$out" '.error' "no-auth"
contains "an unauthenticated gh names the fix" "$out" "gh auth login"

out="$(FAKE_GH_MODE=auth-error "$CLI" refresh --json 2>/dev/null)"
jqis "a GraphQL auth failure keeps the same type" "$out" '.error' "no-auth"

fresh
out="$(FAKE_GH_MODE=broken "$CLI" refresh --json 2>/dev/null)"
jqis "an unreadable GraphQL answer is typed" "$out" '.error' "fetch-failed"
check "a broken answer is retried" "$(grep -c 'api graphql' "$FAKE_GH_LOG")" "3"

fresh
out="$(FAKE_GH_MODE=hang GITHUB_OMA_TIMEOUT=1 "$CLI" refresh --json 2>/dev/null)"
jqis "a hung GitHub is typed" "$out" '.error' "timeout"

fresh
out="$(FAKE_GH_MODE=flaky "$CLI" refresh --json 2>/dev/null)"
jqis "a transient 502 is ridden out" "$out" '.ok' "true"
check "the retry is visible in the call log" "$(grep -c 'api graphql' "$FAKE_GH_LOG")" "2"

echo "== qml model =="

if command -v qml6 > /dev/null 2>&1; then
  # qml6 swallows console.log, so this gates on the exit status alone.
  QT_QPA_PLATFORM=offscreen timeout 30 qml6 "$PLUGIN_DIR/tests/ModelTest.qml" > /dev/null 2>&1
  check "qml model tests" "$?" "0"
else
  echo "  skip qml model tests (no qml6 on PATH)"
fi

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
