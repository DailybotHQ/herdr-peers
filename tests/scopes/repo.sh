# shellcheck shell=bash
# Scope `repo`: the public repository standard — required files and README
# layout, the public-hygiene check (against this repository and against
# planted hits in a throwaway git repository) and the release assets.
# Planted values are assembled at runtime so no tracked file carries them.
# shellcheck disable=SC2016  # sh -c scripts take their file as "$1"

HYGIENE="$ROOT/scripts/check-public-hygiene.sh"
ASSETS="$ROOT/scripts/release-assets.sh"

# --- required files -------------------------------------------------------------
for f in README.md LICENSE CHANGELOG.md CONTRIBUTING.md SECURITY.md \
  CODE_OF_CONDUCT.md AGENTS.md CREDITS.md docs/TESTING_GUIDE.md .gitignore \
  .public-hygiene-allow .github/ISSUE_TEMPLATE/bug_report.yml \
  .github/ISSUE_TEMPLATE/feature_request.yml .github/ISSUE_TEMPLATE/config.yml \
  .github/PULL_REQUEST_TEMPLATE.md .github/CODEOWNERS .github/dependabot.yml \
  .github/workflows/ci.yml .github/workflows/release.yml; do
  check "repository file $f exists" test -s "$ROOT/$f"
done
if [ -L "$ROOT/CLAUDE.md" ] && [ "$(readlink "$ROOT/CLAUDE.md")" = AGENTS.md ]; then
  t_ok "CLAUDE.md is a symlink to AGENTS.md"
else
  t_fail "CLAUDE.md is a symlink to AGENTS.md"
fi
check "LICENSE is MIT, DailybotHQ contributors" grep -q 'Copyright (c) 2026 DailybotHQ contributors' "$ROOT/LICENSE"
check "CODE_OF_CONDUCT is Contributor Covenant 2.1 with a contact" \
  sh -c 'grep -q "version 2.1" "$1" && ! grep -q "INSERT CONTACT" "$1"' _ "$ROOT/CODE_OF_CONDUCT.md"
check "SECURITY.md has supported versions and private reporting" \
  sh -c 'grep -q "## Supported versions" "$1" && grep -q "Report a vulnerability" "$1" && grep -q "security@dailybot.com" "$1"' _ "$ROOT/SECURITY.md"
check "CHANGELOG follows Keep a Changelog" grep -q 'keepachangelog.com' "$ROOT/CHANGELOG.md"
check "issue config turns blank issues off" grep -q 'blank_issues_enabled: false' "$ROOT/.github/ISSUE_TEMPLATE/config.yml"
check "PR template asks for no secrets or private context" grep -qi 'no secrets' "$ROOT/.github/PULL_REQUEST_TEMPLATE.md"
check ".gitignore covers .dwp/, tmp/, .env and .env.*" \
  sh -c 'for p in ".dwp/" "tmp/" ".env" ".env.*" "!.env.example"; do grep -qxF "$p" "$1" || exit 1; done' _ "$ROOT/.gitignore"
check "CI runs the public-hygiene check" grep -q 'check-public-hygiene.sh' "$ROOT/.github/workflows/ci.yml"

order=$(sed -n 's/^## //p' "$ROOT/README.md" | tr '\n' '|')
assert_eq "README sections follow the standard order" \
  "What it is|Install|Quickstart|Documentation|Security|Contributing|License|" "$order"
check "README ends with the ecosystem footer" \
  sh -c 'tail -1 "$1" | grep -qF "Part of the [DeepWorkPlan](https://deepworkplan.com) ecosystem — works on its own."' _ "$ROOT/README.md"

# --- hygiene check: this repository ------------------------------------------------
run bash "$HYGIENE" --root "$ROOT"
assert_rc "the public-hygiene check passes on this repository" 0

# --- hygiene check: planted hits ------------------------------------------------------
H="$SANDBOX/hygiene"
new_repo() { # fresh git repo with one clean file
  rm -rf "$H"
  mkdir -p "$H"
  git -C "$H" init -q
  echo "clean" >"$H/README.md"
  git -C "$H" add -A
}
plant() { # file content
  mkdir -p "$(dirname "$H/$1")"
  printf '%s\n' "$2" >"$H/$1"
  git -C "$H" add -A
}

new_repo
run bash "$HYGIENE" --root "$H"
assert_rc "a clean repository passes" 0

d=dailybot o=Daily
pem=$(printf -- '-----BEGIN RSA %s-----' 'PRIVATE KEY')
u=Users h=home
cases="personal-path|path to /$u/jdoe/src
personal-path|/$h/jdoe/.config
private-name|see ${o}Bot-Inc/x
private-name|clone $d-core
private-name|run ${d}-peers list
private-name|tag [$d-mesh] here
private-email|mail jdoe@$d.com
secret-aws|key AKIA$(printf 'Z%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)
secret-github|ghp_$(printf 'a%.0s' $(seq 1 36))
secret-ai|sk-ant-$(printf 'b%.0s' $(seq 1 24))
secret-slack|xoxb-$(printf '1%.0s' $(seq 1 12))
secret-google|AIza$(printf 'c%.0s' $(seq 1 35))
secret-private-key|$pem
secret-assignment|api_key = \"$(printf 'd%.0s' $(seq 1 20))\""
while IFS='|' read -r rule text; do
  [ -n "$rule" ] || continue
  new_repo
  plant notes/hit.txt "$text"
  run bash "$HYGIENE" --root "$H"
  assert_rc "a planted $rule hit fails the check" 1
  assert_contains "the hit names file, line and rule ($rule)" "$OUT" "notes/hit.txt:1: $rule"
  value=${text#* }
  assert_not_contains "the matched text is never printed ($rule)" "$OUT$ERR" "$value"
done <<EOF
$cases
EOF

new_repo
plant notes/ok.txt "write to security@$d.com or support@$d.com"
run bash "$HYGIENE" --root "$H"
assert_rc "public aliases (security@, support@) are allowed" 0

new_repo
plant .agents/skills/vendor/SKILL.md "clone $d-core"
run bash "$HYGIENE" --root "$H"
assert_rc "the vendored .agents/skills/ pack is excluded" 0

# Allow-list rules.
new_repo
plant tests/fixture.txt "$pem (planted test fixture)"
run bash "$HYGIENE" --root "$H"
assert_rc "an unlisted secret-shaped fixture fails" 1
plant .public-hygiene-allow "tests/fixture.txt secret-private-key bare header for a refusal test"
run bash "$HYGIENE" --root "$H"
assert_rc "a listed fixture whose line says it is fake passes" 0
plant tests/fixture.txt "$pem"
run bash "$HYGIENE" --root "$H"
assert_rc "a listed hit that does not say it is fake fails" 1
assert_contains "the failure explains the missing fake marker" "$OUT" "does not say it is fake"
plant .public-hygiene-allow "tests/fixture.txt secret-private-key"
run bash "$HYGIENE" --root "$H"
assert_rc "an allow-list entry without a reason is a usage error" 2
plant .public-hygiene-allow "notes/hit.txt private-name reason here"
run bash "$HYGIENE" --root "$H"
assert_rc "private names can never be allow-listed" 2

run bash "$HYGIENE" --root "$SANDBOX/does-not-exist"
assert_rc "a missing root is a usage error" 2

# --- release assets -----------------------------------------------------------------
R="$SANDBOX/release"
rm -rf "$R"
mkdir -p "$R/skills/demo" "$R/bin"
git -C "$R" init -q
printf 'MIT\n' >"$R/LICENSE"
printf 'skill\n' >"$R/skills/demo/SKILL.md"
printf '#!/bin/sh\n' >"$R/bin/demo"
printf 'untracked\n' >"$R/skills/demo/extra.txt"
cat >"$R/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- pending

## [1.2.0] - 2026-01-02

### Added

- the new thing

## [1.1.0] - 2026-01-01

- older

[1.2.0]: https://example.invalid/1.2.0
EOF
git -C "$R" add LICENSE skills/demo/SKILL.md bin/demo CHANGELOG.md
run bash "$ASSETS" --root "$R" v1.2.0 "$R/out"
assert_rc "release-assets builds the assets of a tag" 0
assert_contains "notes carry the version's section" "$(cat "$R/out/RELEASE_NOTES.md")" "the new thing"
assert_not_contains "notes stop at the next version" "$(cat "$R/out/RELEASE_NOTES.md")" "older"
assert_eq "SHA256SUMS covers exactly the tracked shipped files" "3" "$(grep -c . "$R/out/SHA256SUMS")"
check "SHA256SUMS verifies with shasum -c" sh -c 'cd "$1" && shasum -a 256 -c out/SHA256SUMS' _ "$R"
run bash "$ASSETS" --root "$R" v9.9.9 "$R/out2"
assert_rc "a version missing from the CHANGELOG fails" 1
run bash "$ASSETS" --root "$R" 1.2.0 "$R/out3"
assert_rc "a tag without the v prefix is a usage error" 2
check "release.yml requires an annotated tag" grep -q 'cat-file -t' "$ROOT/.github/workflows/release.yml"
check "release.yml publishes SHA256SUMS" grep -q 'SHA256SUMS' "$ROOT/.github/workflows/release.yml"
rm -rf "$H" "$R"
