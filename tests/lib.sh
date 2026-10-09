# shellcheck shell=bash
# Shared assertions and fixtures for tests/run.sh (bash 3.2 compatible:
# macOS still ships /bin/bash 3.2 — no associative arrays, no mapfile).
#
# Output is TAP-like: `ok N - desc`, `not ok N - desc` (+ `#` diagnostics),
# `skip - desc`. run.sh prints the summary line last.

T_N=0
T_PASS=0
T_FAIL=0
T_SKIP=0

t_ok() {
  T_N=$((T_N + 1)); T_PASS=$((T_PASS + 1))
  printf 'ok %d - %s\n' "$T_N" "$1"
}

t_fail() {
  T_N=$((T_N + 1)); T_FAIL=$((T_FAIL + 1))
  printf 'not ok %d - %s\n' "$T_N" "$1"
  if [ -n "${2:-}" ]; then
    printf '%s\n' "$2" | sed 's/^/#   /' | head -20
  fi
}

t_skip() {
  T_SKIP=$((T_SKIP + 1))
  printf 'skip - %s\n' "$1"
}

# check DESC CMD... — pass when CMD exits 0.
check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then t_ok "$desc"; else t_fail "$desc" "command failed: $*"; fi
}

assert_eq() {
  if [ "$2" = "$3" ]; then t_ok "$1"; else t_fail "$1" "expected: $2
actual:   $3"; fi
}

assert_contains() {
  case "$2" in
    *"$3"*) t_ok "$1" ;;
    *) t_fail "$1" "missing: $3
in: $2" ;;
  esac
}

assert_not_contains() {
  case "$2" in
    *"$3"*) t_fail "$1" "unexpected: $3
in: $2" ;;
    *) t_ok "$1" ;;
  esac
}

# run CMD... — captures OUT, ERR and RC without aborting.
run() {
  local errf
  errf=$(mktemp "$SANDBOX/err.XXXXXX")
  OUT=$("$@" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
}

# assert_rc DESC EXPECTED — checks RC from the last `run`.
assert_rc() {
  if [ "$RC" = "$2" ]; then t_ok "$1"; else t_fail "$1" "expected exit $2, got $RC
stdout: $OUT
stderr: $ERR"; fi
}

# --- fake Herdr worlds -------------------------------------------------------
#
# new_world [NAME] — a fresh fake server state, work directory and caller
# identity. The caller is pane w1:p1 on the local server. Seeded machines:
#   aa11 "self"  enabled; mirrors local (lets the self-probe resolve aa11)
#   bb22 "box"   enabled; agents w1:p1 claude (idle), w1:p3 codex (blocked)
#   cc33 "off"   disabled
#   dd44 "gone"  enabled but unreachable (SSH fails)
new_world() {
  WORLD="$SANDBOX/worlds/${1:-w}.$T_N.$RANDOM"
  export FAKE_HERDR_DIR="$WORLD/herdr"
  WORK="$WORLD/work"
  mkdir -p "$FAKE_HERDR_DIR/local/panes" "$FAKE_HERDR_DIR/aa11/panes" \
    "$FAKE_HERDR_DIR/bb22/panes" "$FAKE_HERDR_DIR/dd44" "$WORK"
  cat >"$FAKE_HERDR_DIR/machines.json" <<'JSON'
[
 {"id": "aa11", "label": "0 - self", "target": "self", "session": "default", "enabled": true, "selected": false},
 {"id": "bb22", "label": "box", "target": "box", "session": "default", "enabled": true, "selected": false},
 {"id": "cc33", "label": "off", "target": "off", "session": "default", "enabled": false, "selected": false},
 {"id": "dd44", "label": "gone", "target": "gone", "session": "default", "enabled": true, "selected": false}
]
JSON
  cat >"$FAKE_HERDR_DIR/local/agents.json" <<'JSON'
[
 {"agent": "claude", "agent_status": "working", "pane_id": "w1:p1", "workspace_id": "w1", "tab_id": "w1:t1", "terminal_id": "term_local_p1", "terminal_title_stripped": "caller session", "cwd": "/work", "focused": true},
 {"agent": "codex", "agent_status": "idle", "name": "reviewer", "pane_id": "w1:p2", "workspace_id": "w1", "tab_id": "w1:t1", "terminal_id": "term_local_p2", "terminal_title_stripped": "review the diff", "cwd": "/work", "focused": false},
 {"agent": "claude", "agent_status": "done", "pane_id": "w2:p1", "workspace_id": "w2", "tab_id": "w2:t1", "terminal_id": "term_local_w2p1", "terminal_title_stripped": "other workspace", "cwd": "/other", "focused": false}
]
JSON
  cp "$FAKE_HERDR_DIR/local/agents.json" "$FAKE_HERDR_DIR/aa11/agents.json"
  cat >"$FAKE_HERDR_DIR/bb22/agents.json" <<'JSON'
[
 {"agent": "claude", "agent_status": "idle", "pane_id": "w1:p1", "workspace_id": "w1", "tab_id": "w1:t1", "terminal_id": "term_box_p1", "terminal_title_stripped": "box worker", "cwd": "/srv", "focused": false},
 {"agent": "codex", "agent_status": "blocked", "pane_id": "w1:p3", "workspace_id": "w1", "tab_id": "w1:t1", "terminal_id": "term_box_p3", "terminal_title_stripped": "waiting for approval", "cwd": "/srv", "focused": false}
]
JSON
  echo dd44 >"$FAKE_HERDR_DIR/unreachable"
  : >"$FAKE_HERDR_DIR/argv.log"
  export HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1
  unset HERDR_PEERS_LOG HERDR_PEERS_SCOPE HERDR_PEERS_SELF HERDR_PEERS_DEPTH \
    HERDR_PEERS_FANOUT HERDR_PEERS_MAX_BYTES DWP_PLAN DWP_TASK
  cd "$WORK" || return 1
}

# pane_text MACHINE PANE — what the fake server shows in that pane.
pane_text() {
  cat "$FAKE_HERDR_DIR/$1/panes/$(printf '%s' "$2" | tr ':' '_').out" 2>/dev/null
}

# last_prompt MACHINE PANE — the latest prompt delivered to that pane, alone.
last_prompt() {
  cat "$FAKE_HERDR_DIR/$1/panes/$(printf '%s' "$2" | tr ':' '_').last" 2>/dev/null
}

# as_pane PANE CMD... — run CMD as another local pane (a peer), in a subshell.
as_pane() {
  local pane=$1; shift
  (export HERDR_PANE_ID="$pane" HERDR_WORKSPACE_ID="${pane%%:*}"; "$@")
}
