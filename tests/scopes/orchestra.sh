# shellcheck shell=bash
# Scope `orchestra`: the control-plane verbs against the fake herdr —
# `status` (lane state, blocked-screen classes, documented next step,
# read-only), `lanes` (lanes-v1 JSON per docs/schema/lanes-v1.json),
# profile/vendor on delegation records, and the stale-pane guard on `ask`.

jget() { python3 -c 'import json,sys; d=json.loads(sys.argv[1])
for k in sys.argv[2].split("."):
    d = d[int(k)] if isinstance(d, list) else d.get(k)
print("null" if d is None else d)' "$1" "$2" 2>/dev/null; }
LANES_SCHEMA="$ROOT/docs/schema/lanes-v1.json"
VALIDATE="$ROOT/tests/tools/validate_records.py"
# screen MACHINE PANE TEXT — what the fake shows in that pane.
screen() { printf '%s\n' "$3" >"$FAKE_HERDR_DIR/$1/panes/$(printf '%s' "$2" | tr ':' '_').out"; }
last_log() { tail -1 "$(state_log)" 2>/dev/null; }
sends_keys() { grep -c 'send-keys' "$FAKE_HERDR_DIR/argv.log"; }

# --- status: lane states ---------------------------------------------------------
new_world status
run "$HELPER" status local:w1:p2
assert_rc "status of an idle peer exits 0" 0
assert_contains "status names the state and agent" "$OUT" "local:w1:p2  idle  agent=codex"
run "$HELPER" status --json local:w2:p1
assert_eq "done is reported as done" "done" "$(jget "$OUT" state)"
assert_eq "a ready lane has no screen class" "none" "$(jget "$OUT" screen)"
screen local w5:p1 "zsh %"
run "$HELPER" status --json local:w5:p1
assert_rc "a plain shell pane is a lane state, not an error" 0
assert_eq "a pane without an agent is no_agent" "no_agent" "$(jget "$OUT" state)"
run "$HELPER" status --json dd44:w1:p1
assert_rc "an unreachable machine exits 1" 1
assert_eq "an unreachable machine is unreachable" "unreachable" "$(jget "$OUT" state)"
run "$HELPER" status local:w9:p9
assert_rc "a missing pane exits 1" 1
run "$HELPER" status "local"
assert_rc "a malformed address is a usage error (exit 2)" 2
python3 -c 'import json,sys; p=sys.argv[1]; a=json.load(open(p)); a[0]["agent_status"]="paused"; json.dump(a, open(p,"w"))' \
  "$FAKE_HERDR_DIR/local/agents.json"
run as_pane w1:p2 "$HELPER" status --json local:w1:p1
assert_eq "an unrecognized Herdr state is reported as unknown" "unknown" "$(jget "$OUT" state)"

# --- status: blocked-screen classes ------------------------------------------------
new_world screens
B=bb22:w1:p3
screen bb22 w1:p3 "Do you trust the files in this folder?
 ❯ 1. Yes, proceed
   2. No, exit"
run "$HELPER" status --json "$B"
assert_eq "a Claude folder-trust screen is folder_trust" "folder_trust" "$(jget "$OUT" screen)"
assert_eq "folder trust may be unblocked" "unblock" "$(jget "$OUT" action)"
assert_eq "the unblock step accepts the default option" \
  "herdr --machine bb22 pane send-keys w1:p3 enter" "$(jget "$OUT" next)"
run "$HELPER" status "$B"
assert_contains "the folder-trust step names its limits" "$OUT" "folder trust only, on a pane you launched yourself"
screen bb22 w1:p3 "Do you trust the contents of this directory? Working with untrusted contents
› 1. Yes, continue
  2. No, quit"
run "$HELPER" status --json "$B"
assert_eq "a Codex folder-trust screen is folder_trust" "folder_trust" "$(jget "$OUT" screen)"
screen bb22 w1:p3 "WARNING: Claude Code running in Bypass Permissions mode
 ❯ 1. No, exit
   2. Yes, I accept"
run "$HELPER" status --json "$B"
assert_eq "the bypass acknowledgement is bypass_ack" "bypass_ack" "$(jget "$OUT" screen)"
assert_eq "the bypass acknowledgement escalates, never unblocks" "escalate" "$(jget "$OUT" action)"
assert_contains "the bypass step goes to the developer, once per profile" "$(jget "$OUT" next)" \
  "escalate to the developer: accept once per profile; never keyed by an agent"
assert_not_contains "no bypass next step suggests keys" "$(jget "$OUT" next)" "send-keys"
run "$HELPER" status "$B"
assert_not_contains "the human view of bypass_ack suggests no keys" "$OUT" "send-keys"
assert_contains "the human view of bypass_ack says escalate" "$OUT" "next: escalate"
ukeys=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import herdr_peers as h; print(" ".join(sorted(h.UNBLOCK_KEYS)))' "$ROOT/skills/herdr-peers/scripts")
assert_eq "folder trust is the only keyable screen" "folder_trust" "$ukeys"
screen bb22 w1:p3 "Select login method:
 ❯ 1. Claude account with subscription"
run "$HELPER" status --json "$B"
assert_eq "a login screen is login" "login" "$(jget "$OUT" screen)"
assert_eq "login escalates" "escalate" "$(jget "$OUT" action)"
assert_contains "login never asks to type credentials" "$(jget "$OUT" next)" "never type credentials"
screen bb22 w1:p3 "Bash command: rm -rf build
Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again"
run "$HELPER" status --json "$B"
assert_eq "a per-action approval is permission" "permission" "$(jget "$OUT" screen)"
assert_eq "permission escalates" "escalate" "$(jget "$OUT" action)"
screen bb22 w1:p3 "Something entirely different is on screen"
run "$HELPER" status --json "$B"
assert_eq "an unrecognized blocked screen is unknown" "unknown" "$(jget "$OUT" screen)"
assert_eq "an unknown screen escalates" "escalate" "$(jget "$OUT" action)"
run "$HELPER" status "$B"
assert_contains "the human view says escalate" "$OUT" "next: escalate"
fake_key="sk-""ant-$(printf 'FAKE%.0s' 1 2 3 4 5 6)0000"   # built at runtime: a fake, not a literal
screen bb22 w1:p3 "Do you trust this folder? $fake_key"
run "$HELPER" status --json "$B"
assert_not_contains "status never echoes screen text" "$OUT$ERR" "FAKEFAKE"
screen local w6:p1 "Do you trust the files in this folder?"
run "$HELPER" status --json local:w6:p1
assert_eq "a first-run screen before agent detection is classified" "no_agent folder_trust" \
  "$(jget "$OUT" state) $(jget "$OUT" screen)"
assert_eq "status never sends keys" "0" "$(sends_keys)"

# --- profile and vendor on records ------------------------------------------------
new_world vendor
id=$("$HELPER" ask --profile @work1 local:w1:p2 "first")
assert_eq "the vendor is derived from the agent kind" "openai" "$(jget "$(last_log)" vendor)"
assert_eq "the profile is recorded" "@work1" "$(jget "$(last_log)" profile)"
"$HELPER" cancel "$id" >/dev/null
assert_eq "a later record repeats the profile" "@work1" "$(jget "$(last_log)" profile)"
assert_eq "a later record repeats the vendor" "openai" "$(jget "$(last_log)" vendor)"
"$HELPER" ask --vendor acme local:w2:p1 "second" >/dev/null
assert_eq "--vendor overrides the derived vendor" "acme" "$(jget "$(last_log)" vendor)"
run "$HELPER" ask --vendor 'bad vendor' local:w2:p1 "third"
assert_rc "a malformed --vendor is a usage error (exit 2)" 2
run "$HELPER" log
assert_contains "log shows vendor and profile" "$OUT" "openai     @work1"
run python3 "$VALIDATE" "$ROOT/skills/herdr-peers/templates/delegation-record.json" \
  "$(state_log)"
assert_rc "records with vendor validate against the delegation schema" 0

# --- lanes (lanes-v1) ---------------------------------------------------------------
new_world lanes
run "$HELPER" lanes --json
assert_rc "lanes with no asks exits 0" 0
printf '%s\n' "$OUT" >"$WORK/empty.json"
assert_eq "an empty lanes view is lanes=[]" "[]" \
  "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["lanes"]))' "$WORK/empty.json")"
run python3 "$VALIDATE" --doc "$LANES_SCHEMA" "$WORK/empty.json"
assert_rc "the empty view validates against lanes-v1" 0
a1=$("$HELPER" ask --profile work1 --task T-1 local:w1:p2 "one")
"$HELPER" ask local:w1:p2 "two" >/dev/null
a3=$("$HELPER" ask --profile @work3 bb22:w1:p1 "three")
"$HELPER" cancel "$a3" >/dev/null
"$HELPER" ask local:w2:p1 "four" >/dev/null
last_prompt local w1:p2 >"$WORK/ask.txt"
run "$HELPER" lanes --json
assert_rc "lanes --json exits 0" 0
printf '%s\n' "$OUT" >"$WORK/lanes.json"
run python3 "$VALIDATE" --doc "$LANES_SCHEMA" "$WORK/lanes.json"
assert_rc "the lanes view validates against lanes-v1" 0
L=$(cat "$WORK/lanes.json")
assert_eq "schema id" "herdr-peers/lanes-v1" "$(jget "$L" schema)"
assert_eq "self is this pane" "local:w1:p1" "$(jget "$L" self)"
assert_eq "one row per peer, sorted" "bb22:w1:p1 local:w1:p2 local:w2:p1" \
  "$(python3 -c 'import json,sys; print(" ".join(l["peer"] for l in json.load(open(sys.argv[1]))["lanes"]))' "$WORK/lanes.json")"
keys=$(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["lanes"][0])))' "$WORK/lanes.json")
assert_eq "a lane carries exactly the contract keys" \
  "agent capacity label last open_asks peer profile screen state vendor" "$keys"
assert_eq "without a lead record the plan fields are null" "null null null" \
  "$(jget "$L" plan) $(jget "$L" lead) $(jget "$L" epoch)"
assert_eq "the remote lane carries its machine label" "box" "$(jget "$L" lanes.0.label)"
assert_eq "a cancelled-only lane has no open asks" "0" \
  "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["lanes"][0]["open_asks"]))' "$WORK/lanes.json")"
assert_eq "its last ask is the cancelled one" "$a3 cancelled" "$(jget "$L" lanes.0.last.id) $(jget "$L" lanes.0.last.state)"
assert_eq "the profile is shown as @name" "@work3" "$(jget "$L" lanes.0.profile)"
assert_eq "two open asks to the reviewer" "2" \
  "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["lanes"][1]["open_asks"]))' "$WORK/lanes.json")"
assert_eq "an open ask carries its id and task" "$a1 T-1" "$(jget "$L" lanes.1.open_asks.0.id) $(jget "$L" lanes.1.open_asks.0.task)"
assert_eq "a bare profile gains the @" "@work1" "$(jget "$L" lanes.1.profile)"
assert_eq "the vendor comes from the record" "openai" "$(jget "$L" lanes.1.vendor)"
assert_eq "the lane state is live from Herdr" "idle none" "$(jget "$L" lanes.1.state) $(jget "$L" lanes.1.screen)"
assert_not_contains "lanes never carries prompt text" "$L" "three"
run as_pane w1:p2 "$HELPER" lanes --json
assert_eq "another pane sharing the log sees only its own lanes" "[]" \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["lanes"]))')"
run as_pane w1:p2 "$HELPER" lanes --json --all
assert_contains "--all shows every pane's lanes" "$OUT" '"peer": "local:w2:p1"'
run "$HELPER" lanes
assert_contains "the table names the columns" "$OUT" "PEER"
assert_contains "the table shows a lane" "$OUT" "local:w1:p2"
assert_eq "lanes never sends keys" "0" "$(sends_keys)"

# --- stale HERDR_PANE_ID -----------------------------------------------------------
new_world stale
run env HERDR_PANE_ID=w9:p9 "$HELPER" ask local:w1:p2 "from a stale id"
assert_rc "an ask from a pane that does not exist is refused (exit 6)" 6
assert_contains "the refusal names the stale id" "$ERR" "stale"
assert_eq "nothing was sent from the stale id" "" "$(pane_text local w1:p2)"
check "nothing was recorded from the stale id" test ! -e "$(state_log)"
sleep 30 &
other=$!
echo "$other" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
run "$HELPER" ask local:w1:p2 "pane belongs to someone else"
assert_rc "an ask from another session's pane id is refused (exit 6)" 6
# with or without a terminal (CI runners have none), the refusal names the id;
# the terminal-attached wording is pinned by the scripted process table below
assert_contains "the refusal names the untrusted id" "$ERR" "HERDR_PANE_ID=w1:p1"
run as_pane w1:p2 "$HELPER" reply local:w1:p1 01ARZ3NDEKTSV4RRFFQ69G5FAV "x"
assert_rc "reply verifies its own pane too" 3
kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
echo "$$" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
run "$HELPER" ask local:w1:p2 "an ancestor runs in this pane"
assert_rc "an ask whose pane runs an ancestor process is sent" 0
echo "999999" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
run "$HELPER" ask local:w2:p1 "pids not visible here (another PID namespace)"
assert_rc "pids invisible from this process table are not a refusal" 0

# --- pane ownership against a scripted process table (fake ps) -------------------
# The fake `ps` prints the helper itself ($PPID of ps) under FAKE_PS_PARENT, then
# the rows of FAKE_PS_TABLE ("pid ppid tty comm"). Two caller shapes:
#   Claude-style: the helper is a child of the agent in its pane (a terminal).
#   Codex-style:  the helper runs under the agent's background app-server daemon
#                 (no terminal anywhere); that daemon's HERDR_PANE_ID names the
#                 pane that first started it, so the inherited id is not trusted.
FAKE_PS_DIR="$SANDBOX/fake-ps"
mkdir -p "$FAKE_PS_DIR"
cat >"$FAKE_PS_DIR/ps" <<'PS'
#!/bin/sh
printf '%s %s %s %s\n' "$PPID" "${FAKE_PS_PARENT:-1}" "${FAKE_PS_TTY:-??}" python3
cat "$FAKE_PS_TABLE"
PS
chmod +x "$FAKE_PS_DIR/ps"
with_ps() { (PATH="$FAKE_PS_DIR:$PATH"; export PATH FAKE_PS_TABLE FAKE_PS_PARENT FAKE_PS_TTY; "$@"); }

new_world ownership
FAKE_PS_TABLE="$WORLD/ps.table"
cat >"$FAKE_PS_TABLE" <<'TABLE'
1 0 ?? launchd
400 1 ?? /opt/agents/codex/bin/codex
500 400 ?? /opt/agents/codex/bin/codex-code-mode-host
590 1 ttys044 -zsh
600 590 ttys044 /usr/local/bin/codex
690 1 ttys045 -zsh
700 690 ttys045 /usr/local/bin/claude
790 1 ttys046 -zsh
800 790 ttys046 /usr/local/bin/claude
TABLE
echo "600 codex" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
echo "700 claude" >"$FAKE_HERDR_DIR/local/panes/w2_p1.pids"

# Claude-style: the pane's agent is an ancestor — accepted with the inherited id.
FAKE_PS_PARENT=700 FAKE_PS_TTY=ttys045
run with_ps as_pane w2:p1 "$HELPER" ask local:w1:p2 "claude-style caller"
assert_rc "a Claude-style caller (child of its pane's agent) is accepted" 0
assert_contains "the ask is stamped from its own pane" "$(last_prompt local w1:p2)" "from=local:w2:p1"

# Codex-style with the daemon's inherited id: refused, and told to pass --pane.
FAKE_PS_PARENT=500 FAKE_PS_TTY='??'
run with_ps "$HELPER" ask local:w1:p2 "codex-style, inherited id"
assert_rc "a detached caller's inherited HERDR_PANE_ID is not trusted (exit 6)" 6
assert_contains "the refusal names the background server" "$ERR" "background agent server"
assert_contains "the refusal says how to fix it" "$ERR" "--pane"

# Codex-style declaring its own pane: the pane runs the same agent program.
run with_ps "$HELPER" ask --pane w1:p1 local:w1:p2 "codex-style, declared pane"
assert_rc "a Codex-style caller declaring its pane (same agent, no terminal) is accepted" 0
assert_contains "the ask is stamped from the declared pane" "$(last_prompt local w1:p2)" "from=local:w1:p1"

# Codex-style declaring a pane that runs another agent: refused.
run with_ps "$HELPER" ask --pane w2:p1 local:w1:p2 "codex-style, someone else's pane"
assert_rc "a declared pane running another agent is refused (exit 6)" 6
assert_contains "the refusal names the declared pane" "$ERR" "--pane w2:p1 is not this session's pane"

# Stale id from another session: a terminal-attached caller outside the pane.
FAKE_PS_PARENT=800 FAKE_PS_TTY=ttys046
run with_ps "$HELPER" ask local:w1:p2 "stale id from another session"
assert_rc "a terminal-attached caller with another session's id is refused (exit 6)" 6
assert_contains "the refusal says the id names another session" "$ERR" "another session"
run with_ps "$HELPER" ask --pane w1:p1 local:w1:p2 "declared, but this caller has a terminal"
assert_rc "--pane never bypasses ancestry for a terminal-attached caller (exit 6)" 6

# A malformed --pane is a usage error; reply, check, wait, lanes and cancel take it.
run "$HELPER" ask --pane local:w1:p1 local:w1:p2 "machine prefix"
assert_rc "--pane with a machine prefix is a usage error (exit 2)" 2
for verb in reply check wait lanes cancel; do
  run "$HELPER" "$verb" --help
  assert_contains "$verb accepts --pane" "$OUT" "--pane"
done
# The receiving Codex lane (w1:p2) checks the ask with its own declared pane.
run "$HELPER" check --no-record --pane w1:p2 "$FAKE_HERDR_DIR/local/panes/w1_p2.last"
assert_contains "check prints the reply command with --pane" "$OUT" "herdr-peers reply --pane w1:p2 local:w1:p1"

# --- usage_limit screens ---------------------------------------------------------------
new_world limits
B=bb22:w1:p3
screen bb22 w1:p3 "Claude usage
You've hit your session limit · resets 6pm (Europe/Madrid)
 ❯ 1. Stop and wait for limit to reset
   2. Upgrade your plan"
run "$HELPER" status --json "$B"
assert_eq "a Claude limit screen is usage_limit" "usage_limit" "$(jget "$OUT" screen)"
assert_eq "a usage limit is handed off, never unblocked" "handoff" "$(jget "$OUT" action)"
assert_contains "the next step is the documented hand-off" "$(jget "$OUT" next)" \
  "hand off: the lead (or the deputy, for the lead) relaunches this lane's plan on an account with capacity; never keyed"
assert_not_contains "the hand-off suggests no keys" "$(jget "$OUT" next)" "send-keys"
run "$HELPER" status "$B"
assert_contains "the human view says hand off" "$OUT" "next: hand off"
screen bb22 w1:p3 "■ You've hit your usage limit. Upgrade to Pro (https://example.invalid/pricing) or try again in 2 days 3 hours."
run "$HELPER" status --json "$B"
assert_eq "a Codex limit screen is usage_limit" "usage_limit" "$(jget "$OUT" screen)"
screen bb22 w1:p3 "API Error: Rate limit reached for requests. Please wait."
run "$HELPER" status --json "$B"
assert_eq "a generic rate-limit screen is usage_limit" "usage_limit" "$(jget "$OUT" screen)"
screen bb22 w1:p3 "Error 429 Too Many Requests"
run "$HELPER" status --json "$B"
assert_eq "an HTTP 429 screen is usage_limit" "usage_limit" "$(jget "$OUT" screen)"
screen bb22 w1:p3 "WARNING: Claude Code running in Bypass Permissions mode
You've hit your usage limit
 ❯ 1. No, exit"
run "$HELPER" status --json "$B"
assert_eq "the bypass acknowledgement still wins over a limit line" "bypass_ack" "$(jget "$OUT" screen)"
# An idle lane at its limit (Herdr sees a finished turn).
screen local w1:p2 "$(printf 'old output line\n%.0s' 1 2 3)
5-hour limit reached ∙ resets 3pm"
run "$HELPER" status --json local:w1:p2
assert_eq "an idle lane at its limit stays idle" "idle" "$(jget "$OUT" state)"
assert_eq "an idle lane at its limit shows usage_limit" "usage_limit" "$(jget "$OUT" screen)"
screen local w1:p2 "You've hit your usage limit
$(printf 'later work line\n%.0s' $(seq 1 20))"
run "$HELPER" status --json local:w1:p2
assert_eq "a limit banner above the last 15 lines of an idle lane is ignored" "none" "$(jget "$OUT" screen)"
screen local w1:p2 "fyi the CI API was rate limited earlier; we hit a 429 Too Many Requests and the usage limit reached message"
run "$HELPER" status --json local:w1:p2
assert_eq "prose that mentions limits is not a limit banner" "none" "$(jget "$OUT" screen)"
screen local w1:p2 "> You've hit your usage limit"
run "$HELPER" status --json local:w1:p2
assert_eq "a quoted prompt line is not a limit banner" "none" "$(jget "$OUT" screen)"
screen bb22 w1:p3 "Do you want to proceed?
You've hit your usage limit"
run "$HELPER" status --json "$B"
assert_eq "a pending approval outranks a limit line" "permission" "$(jget "$OUT" screen)"
screen local w1:p2 "Do you want to proceed?"
run "$HELPER" status --json local:w1:p2
assert_eq "an idle lane reports no other screen class" "none" "$(jget "$OUT" screen)"
screen local w2:p1 "You've hit your weekly limit · resets Mon"
run "$HELPER" status --json local:w2:p1
assert_eq "a done lane at its limit shows usage_limit" "done usage_limit" "$(jget "$OUT" state) $(jget "$OUT" screen)"
assert_eq "usage_limit is never keyed" "0" "$(sends_keys)"

# --- lanes: plan, lead, epoch and capacity ------------------------------------------------
new_world lanecap
P=PLAN_900_demo
"$HELPER" lead claim --plan "$P" --lanes local:w1:p2,local:w2:p1 >/dev/null 2>&1
run as_pane w1:p2 "$HELPER" ask --plan "$P" lead "milestone: PR open
capacity=low 22% @work2"
mid=$OUT
last_prompt local w1:p1 >"$WORK/m.txt"
"$HELPER" check "$WORK/m.txt" >/dev/null 2>&1
"$HELPER" reply local:w1:p2 "$mid" "noted" >/dev/null 2>&1   # the lead answers before it asks
run "$HELPER" lanes --json --plan "$P"
printf '%s\n' "$OUT" >"$WORK/lc.json"
run python3 "$VALIDATE" --doc "$LANES_SCHEMA" "$WORK/lc.json"
assert_rc "lanes with lead fields validates against lanes-v1" 0
C=$(cat "$WORK/lc.json")
assert_eq "lanes names the plan, lead and epoch" "$P local:w1:p1 1" "$(jget "$C" plan) $(jget "$C" lead) $(jget "$C" epoch)"
assert_eq "a lane listed in the lead record appears without an ask" "local:w1:p2 local:w2:p1" \
  "$(python3 -c 'import json,sys; print(" ".join(l["peer"] for l in json.load(open(sys.argv[1]))["lanes"]))' "$WORK/lc.json")"
assert_eq "a never-asked lane has no last ask" "null" "$(jget "$C" lanes.1.last)"
assert_eq "the lane's capacity comes from its message" "low 22 @work2" \
  "$(jget "$C" lanes.0.capacity.verdict) $(jget "$C" lanes.0.capacity.headroom_pct) $(jget "$C" lanes.0.capacity.profile)"
assert_eq "a lane that reported nothing has no capacity" "null" "$(jget "$C" lanes.1.capacity)"
run "$HELPER" lanes --json
assert_eq "without --plan the one record this pane leads is used" "$P" "$(jget "$OUT" plan)"
mkdir -p "$WORK/plans/PLAN_004_child"
run as_pane w1:p2 env DWP_PLAN="$WORK/plans/PLAN_004_child" "$HELPER" lanes --json
assert_eq "a lane in its child plan sees the record that lists it" "$P local:w1:p1" "$(jget "$OUT" plan) $(jget "$OUT" lead)"
a=$("$HELPER" ask local:w2:p1 "status?")
last_prompt local w2:p1 >"$WORK/q.txt"
as_pane w2:p1 "$HELPER" check "$WORK/q.txt" >/dev/null 2>&1
as_pane w2:p1 "$HELPER" reply local:w1:p1 "$a" "all green
capacity=ok 81% @work1" >/dev/null 2>&1
last_prompt local w1:p1 >"$WORK/r.txt"
"$HELPER" check "$WORK/r.txt" >/dev/null 2>&1
run "$HELPER" lanes --json --plan "$P"
assert_eq "a reply's capacity line updates the lane" "ok 81" \
  "$(jget "$OUT" lanes.1.capacity.verdict) $(jget "$OUT" lanes.1.capacity.headroom_pct)"
run "$HELPER" lanes --plan "$P"
assert_contains "the table names plan, lead and epoch" "$OUT" "plan $P  lead local:w1:p1  epoch 1"
assert_contains "the table shows a capacity column" "$OUT" "low 22%"
run python3 "$VALIDATE" "$ROOT/skills/herdr-peers/templates/delegation-record.json" "$(state_log)"
assert_rc "records carrying capacity validate" 0
