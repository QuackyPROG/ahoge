#!/usr/bin/env bash
# Checks the quiet-window decisions of push-to-phone.sh without building or installing anything.
# Usage: bash Scripts/test-push-to-phone.sh    Exits 0 when every case passes and prints each failing case.
set -uo pipefail

. "$(dirname "$0")/push-policy.sh"

failed=0
check() { # expected (yes|no), description, command...
  local expected="$1" name="$2" got=no
  shift 2
  "$@" && got=yes
  if [ "$got" != "$expected" ]; then
    echo "FAIL: $name: expected $expected, got $got"
    failed=$((failed + 1))
  fi
}
day=$((24 * 60 * 60))

check no  "02-06 at 1 is outside"  in_quiet_window 02-06 01
check yes "02-06 at 2 is inside"   in_quiet_window 02-06 02
check yes "02-06 at 5 is inside"   in_quiet_window 02-06 05
check no  "02-06 at 6 is outside"  in_quiet_window 02-06 06
check no  "22-06 at 21 is outside" in_quiet_window 22-06 21
check yes "22-06 at 22 is inside"  in_quiet_window 22-06 22
check yes "22-06 at 3 is inside"   in_quiet_window 22-06 03
check no  "22-06 at 6 is outside"  in_quiet_window 22-06 06
check yes "08-10 at 9 is inside"   in_quiet_window 08-10 09

check yes "new commit installs inside the window"       should_install 02-06 03 false
check no  "new commit waits outside the window"         should_install 02-06 12 false
check yes "new commit installs outside with --force"    should_install 02-06 12 true

check no  "no re-sign at 2 days inside"  should_resign 02-06 03 $((2 * day))
check yes "re-sign at 3 days inside"     should_resign 02-06 03 $((3 * day))
check yes "re-sign at 5 days inside"     should_resign 02-06 03 $((5 * day))
check yes "re-sign at 6 days inside"     should_resign 02-06 03 $((6 * day))
check yes "re-sign at 7 days inside"     should_resign 02-06 03 $((7 * day))
check no  "no re-sign at 2 days outside" should_resign 02-06 12 $((2 * day))
check no  "no re-sign at 3 days outside" should_resign 02-06 12 $((3 * day))
check no  "no re-sign at 5 days outside" should_resign 02-06 12 $((5 * day))
check yes "re-sign at 6 days outside"    should_resign 02-06 12 $((6 * day))
check yes "re-sign at 7 days outside"    should_resign 02-06 12 $((7 * day))

check yes "02-06 is valid" quiet_hours_valid 02-06
check yes "22-06 is valid" quiet_hours_valid 22-06
check no  "25-06 is rejected" quiet_hours_valid 25-06
check no  "2-6x is rejected"  quiet_hours_valid 2-6x
check no  "02-02 is rejected" quiet_hours_valid 02-02
check no  "empty is rejected" quiet_hours_valid ""

# only_docs_changed runs in a throwaway repository: app, docs-only and README-only commits on top of each other.
repo="$(mktemp -d)"
(
  cd "$repo" || exit 1
  git init --quiet
  git config user.email test@example.com
  git config user.name test
  commit() { mkdir -p "$(dirname "$1")"; echo "$2" >>"$1"; git add -A; git commit --quiet -m "$1"; git rev-parse HEAD; }
  app=$(commit Ahoge/App.swift one)
  docs=$(commit Docs/plans/STATE.md note)
  readme=$(commit README.md intro)
  code=$(commit Ahoge/App.swift two)
  printf '%s\n' "$app" "$docs" "$readme" "$code"
) >"$repo.commits" || { echo "FAIL: could not set up the test repository"; failed=$((failed + 1)); }
{ read -r app; read -r docs; read -r readme; read -r code; } <"$repo.commits"
in_repo() { (cd "$repo" && "$@"); }
check yes "docs commit after an app commit is docs only"   in_repo only_docs_changed "$app" "$docs"
check yes "docs and README commits together are docs only" in_repo only_docs_changed "$app" "$readme"
check no  "a code commit is not docs only"                 in_repo only_docs_changed "$readme" "$code"
check no  "docs then code is not docs only"                in_repo only_docs_changed "$app" "$code"
check no  "going backwards is not docs only"               in_repo only_docs_changed "$docs" "$app"
check no  "no installed commit is not docs only"           in_repo only_docs_changed "" "$docs"
rm -rf "$repo" "$repo.commits"

if [ "$failed" -gt 0 ]; then
  echo "$failed case(s) failed"
  exit 1
fi
echo "all cases passed"
