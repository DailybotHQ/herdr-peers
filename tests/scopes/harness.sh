# shellcheck shell=bash
# Scope `harness`: the sandbox is sealed and the fake herdr models the real
# 0.9.x CLI shapes the helper depends on.

case "$HOME" in
  "$ROOT/tmp/test-sandbox."*) t_ok "HOME is a sandbox under tmp/" ;;
  *) t_fail "HOME is a sandbox under tmp/" "HOME=$HOME" ;;
esac
assert_eq "HOME is not the real home" "different" \
  "$([ "$HOME" != "$REAL_HOME" ] && echo different || echo same)"
assert_eq "herdr on PATH is the fake" "$ROOT/tests/fakes/herdr" "$(command -v herdr)"
assert_eq "no inherited Herdr socket" "" "${HERDR_SOCKET_PATH:-}"
leaked=$(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | grep -E '_API_KEY$|_TOKEN$' || true)
assert_eq "no *_API_KEY / *_TOKEN variable in the sandbox" "" "$leaked"
case ":$PATH:" in
  *":$REAL_HOME/.local/bin:"*) t_fail "real ~/.local/bin is off PATH" ;;
  *) t_ok "real ~/.local/bin is off PATH" ;;
esac

new_world harness
run herdr --version
assert_contains "fake reports a 0.9.x version" "$OUT" "herdr 0.9."

run herdr pane current --current
pane=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])' 2>/dev/null)
assert_eq "pane current returns the caller pane in result.pane" "w1:p1" "$pane"

run herdr agent list
count=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["result"]["agents"]))' 2>/dev/null)
assert_eq "agent list returns result.agents" "3" "$count"

run herdr --machine bb22 agent list
assert_contains "--machine routes to that machine's server" "$OUT" "term_box_p1"

run herdr --machine box agent get w1:p1
assert_rc "a machine label is accepted as selector" 0

run herdr --machine nope agent list
assert_rc "unknown machine is a syntax error (exit 2)" 2
assert_contains "unknown machine message mirrors herdr" "$ERR" "unknown machine 'nope'"

run herdr --machine dd44 agent list
assert_rc "unreachable machine exits 1" 1
assert_contains "unreachable machine surfaces the SSH error" "$ERR" "Connection refused"

run herdr --machine cc33 agent list
assert_rc "disabled machine is refused" 1

run herdr agent get nobody
assert_rc "missing agent is a server error (exit 1)" 1
assert_contains "server errors are JSON with error.code" "$ERR" '"code": "agent_not_found"'

run herdr agent prompt w1:p2 "hello there"
assert_rc "agent prompt succeeds on an idle agent" 0
assert_eq "agent prompt lands in the target pane" "hello there" "$(pane_text local w1:p2)"
assert_contains "argv is recorded" "$(cat "$FAKE_HERDR_DIR/argv.log")" '"agent", "prompt", "w1:p2"'

run herdr --machine bb22 agent prompt w1:p3 "hi"
assert_rc "agent prompt refuses a blocked agent" 1
assert_contains "blocked refusal code" "$ERR" "agent_blocked"

run herdr pane read w1:p2 --source recent-unwrapped --lines 5
assert_eq "pane read returns the pane text" "hello there" "$OUT"

run herdr pane wait-output w1:p2 --match "hello" --timeout 1000
assert_rc "wait-output matches existing output" 0
run herdr pane wait-output w1:p2 --match "never-there" --timeout 200
assert_rc "wait-output times out with exit 1" 1
assert_contains "wait-output timeout code" "$ERR" '"code": "timeout"'

run herdr machine list --json
assert_contains "machine list --json prints the saved profiles" "$OUT" '"id": "bb22"'

run herdr no-such-group
assert_rc "unknown subcommand is a syntax error (exit 2)" 2

run bash "$ROOT/tests/run.sh" no-such-scope
assert_rc "runner refuses an unknown scope (exit 2)" 2
