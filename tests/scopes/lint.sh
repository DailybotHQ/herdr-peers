# shellcheck shell=bash
# Scope `lint`: shellcheck over every shell file, python syntax over every
# python file, JSON validity over every JSON file this repo ships.

shell_files=""
for f in "$ROOT/tests/run.sh" "$ROOT/tests/lib.sh" "$ROOT"/tests/scopes/*.sh \
  "$ROOT/bin/herdr-peers" "$ROOT/skills/herdr-peers/scripts/herdr-peers" \
  "$ROOT"/scripts/*.sh; do
  [ -f "$f" ] && shell_files="$shell_files $f"
done

if [ -n "$SHELLCHECK_BIN" ]; then
  # shellcheck disable=SC2086
  run "$SHELLCHECK_BIN" -x -s bash $shell_files
  if [ "$RC" = 0 ]; then
    t_ok "shellcheck ($("$SHELLCHECK_BIN" --version | sed -n 's/^version: //p')) is clean"
  else
    t_fail "shellcheck is clean" "$OUT"
  fi
else
  t_skip "shellcheck: unavailable (not installed on this host)"
fi

for f in $shell_files; do
  check "bash -n $(basename "$f")" bash -n "$f"
done

for f in "$ROOT/tests/fakes/herdr" "$ROOT"/skills/herdr-peers/scripts/*.py "$ROOT"/tests/tools/*.py; do
  [ -f "$f" ] || continue
  check "python compiles $(basename "$f")" python3 -c \
    'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$f"
done

json_files=$(find "$ROOT/skills" "$ROOT/tests/fixtures" -name '*.json' 2>/dev/null | sort)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  check "valid JSON $(basename "$f")" python3 -m json.tool "$f"
done <<EOF_JSON
$json_files
EOF_JSON
