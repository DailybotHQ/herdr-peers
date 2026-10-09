# shellcheck shell=bash
# Scope `live`: optional checks against a real Herdr server. Opt-in only —
# run `HERDR_PEERS_LIVE=1 bash tests/run.sh live` from inside a Herdr pane.
# Everything here is read-only against the server: no pane, tab or session
# is created, changed or closed, and HOME stays the sandbox (so no saved
# machines are contacted). Without the opt-in, or without a server, the
# scope reports `unavailable` — never a pass.

if [ "${HERDR_PEERS_LIVE:-}" != 1 ]; then
  t_skip "live: unavailable (opt-in: HERDR_PEERS_LIVE=1 inside a Herdr pane)"
elif [ -z "$LIVE_HERDR_BIN" ] || [ -z "$LIVE_ENV" ]; then
  t_skip "live: unavailable (not inside a Herdr pane, or herdr is not installed)"
else
  live() {
    # shellcheck disable=SC2086
    env $LIVE_ENV PATH="$(dirname "$LIVE_HERDR_BIN"):$SANDBOX/bin:/usr/bin:/bin" "$@"
  }
  run live herdr status
  if [ "$RC" != 0 ] || ! printf '%s' "$OUT" | grep -q 'status: running'; then
    t_skip "live: unavailable (no Herdr server answers: $(printf '%s' "$ERR$OUT" | tail -1))"
  else
    t_ok "live: a Herdr server answers"
    version=$(printf '%s' "$OUT" | sed -n '/^server:/,$ s/^ *version: //p' | head -1)
    if python3 -c 'import sys; v=tuple(int(x) for x in sys.argv[1].split(".")[:3]); sys.exit(0 if v >= (0, 9, 1) else 1)' "$version" 2>/dev/null; then
      t_ok "live: server version $version >= 0.9.1"
    else
      t_fail "live: server version >= 0.9.1" "server version: $version"
    fi
    mkdir -p "$SANDBOX/live" && cd "$SANDBOX/live" || exit 2
    run live "$HELPER" list --json
    assert_rc "live: herdr-peers list runs against the real server" 0
    you=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for r in d["rows"] if r.get("you")))' 2>/dev/null)
    assert_eq "live: the real listing marks exactly one row as you" "1" "$you"
    run live "$HELPER" ask --scope local local:w0:p0 "never sent"
    assert_rc "live: asking a pane that does not exist fails cleanly (exit 1)" 1
    check "live: nothing was recorded for the failed ask" sh -c "! grep -q '\"state\": \"launched\"' '$SANDBOX/live/.herdr-peers/log.ndjson' 2>/dev/null"
    t_skip "live: two-pane ask/reply round trip not run — it creates panes in the live session; v0.1.0 covers the round trip against the fake (helper scope)"
  fi
fi
