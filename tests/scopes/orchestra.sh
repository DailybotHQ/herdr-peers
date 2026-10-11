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
last_log() { tail -1 "$WORK/.herdr-peers/log.ndjson" 2>/dev/null; }
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
  "$WORK/.herdr-peers/log.ndjson"
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
  "agent label last open_asks peer profile screen state vendor" "$keys"
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
check "nothing was recorded from the stale id" test ! -e "$WORK/.herdr-peers/log.ndjson"
sleep 30 &
other=$!
echo "$other" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
run "$HELPER" ask local:w1:p2 "pane belongs to someone else"
assert_rc "an ask from another session's pane id is refused (exit 6)" 6
assert_contains "the refusal says the id names another session" "$ERR" "another session"
run as_pane w1:p2 "$HELPER" reply local:w1:p1 01ARZ3NDEKTSV4RRFFQ69G5FAV "x"
assert_rc "reply verifies its own pane too" 3
kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
echo "$$" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
run "$HELPER" ask local:w1:p2 "an ancestor runs in this pane"
assert_rc "an ask whose pane runs an ancestor process is sent" 0
echo "999999" >"$FAKE_HERDR_DIR/local/panes/w1_p1.pids"
run "$HELPER" ask local:w2:p1 "pids not visible here (another PID namespace)"
assert_rc "pids invisible from this process table are not a refusal" 0
