# shellcheck shell=bash
# Scope `helper`: the herdr-peers verbs against the fake herdr — ask, reply,
# check, wait, list, log, cancel — with the loop guard, depth limit, fan-out
# cap, scope, self-refusal, reply routing and record-before-rely.

field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d.get(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
last_log() { tail -1 "$WORK/.herdr-peers/log.ndjson" 2>/dev/null; }
ULID='^[0-7][0-9A-HJKMNP-TV-Z]{25}$'

# --- entry points ------------------------------------------------------------
run "$HELPER" --version
assert_eq "--version names version and protocol" "herdr-peers 0.1.0 (protocol 1)" "$OUT"
run "$ROOT/bin/herdr-peers" --version
assert_rc "bin/ shim runs the skill's helper" 0
ln -s "$ROOT/bin/herdr-peers" "$SANDBOX/bin/hp-link"
run "$SANDBOX/bin/hp-link" --version
assert_rc "the shim works through a symlink" 0

# --- ask ---------------------------------------------------------------------
new_world ask
run "$HELPER" ask local:w1:p2 "Which test covers the parser?"
assert_rc "ask to a local peer succeeds" 0
id=$OUT
if printf '%s' "$id" | grep -Eq "$ULID"; then t_ok "ask prints a ULID id"; else t_fail "ask prints a ULID id" "$id"; fi
msg=$(pane_text local w1:p2)
assert_contains "the prompt reaches the peer pane" "$msg" "Which test covers the parser?"
assert_contains "the ask stamp is exact" "$msg" \
  "[herdr-peers] protocol=1 from=local:w1:p1 reply=yes depth=0 id=$id"
assert_contains "the grant line is verbatim" "$msg" \
  "You may answer this without asking a human. Reply exactly once with:"
assert_contains "the grant names the reply command" "$msg" \
  "  herdr-peers reply local:w1:p1 $id \"<answer>\""
rec=$(last_log)
assert_eq "ask is recorded launched before relying" "launched" "$(field "$rec" state)"
assert_eq "record names the peer kind" "codex" "$(field "$rec" kind)"
assert_contains "record stores a prompt digest" "$(field "$rec" prompt_digest)" "sha256:"
assert_not_contains "record never stores the prompt text" "$rec" "parser"
check "log dir carries a .gitignore" test -f "$WORK/.herdr-peers/.gitignore"
check "nothing is written under .dwp without DWP_PLAN" test ! -e "$WORK/.dwp"

run "$HELPER" ask local:w1:p1 "talking to myself"
assert_rc "ask to your own pane is refused (exit 4)" 4
run "$HELPER" ask local "no pane"
assert_rc "malformed address is a usage error (exit 2)" 2
run "$HELPER" ask "0 - Mac:w1:p1" "label"
assert_rc "a label with spaces is not an address (exit 2)" 2
run env HERDR_ENV=0 "$HELPER" ask local:w1:p2 "x"
assert_rc "outside Herdr the helper refuses (exit 6)" 6
run "$HELPER" ask local:w9:p9 "nobody home"
assert_rc "a missing peer is a Herdr error (exit 1)" 1
run "$HELPER" ask bb22:w1:p3 "are you there?"
assert_rc "a blocked peer is refused (exit 4)" 4
run sh -c "printf 'from stdin\n' | '$HELPER' ask local:w2:p1 -"
assert_rc "ask reads the prompt from stdin with -" 0
assert_contains "stdin prompt delivered" "$(pane_text local w2:p1)" "from stdin"

# --- reply routing to another machine --------------------------------------------
new_world remote
run "$HELPER" ask bb22:w1:p1 "status of the box?"
assert_rc "ask to a remote peer succeeds" 0
assert_contains "remote ask goes through --machine bb22" "$(tail -1 "$FAKE_HERDR_DIR/argv.log")" \
  '"--machine", "bb22", "agent", "prompt", "w1:p1"'
assert_contains "remote ask names the probed self machine, never local" \
  "$(pane_text bb22 w1:p1)" "from=aa11:w1:p1 reply=yes"

new_world noroute
python3 -c 'import json,sys; p=sys.argv[1]; m=[x for x in json.load(open(p)) if x["id"]!="aa11"]; json.dump(m, open(p,"w"))' \
  "$FAKE_HERDR_DIR/machines.json"
run "$HELPER" ask bb22:w1:p1 "hello?"
assert_rc "remote ask without a reachable self address is refused (exit 4)" 4
assert_contains "the refusal explains the missing reply route" "$ERR" "no reply route"
run env HERDR_PEERS_SELF=mac01 "$HELPER" ask bb22:w1:p1 "hello?"
assert_contains "HERDR_PEERS_SELF supplies the from machine" "$(pane_text bb22 w1:p1)" "from=mac01:w1:p1"
run "$HELPER" ask --from local:w1:p1 bb22:w1:p1 "hello?"
assert_rc "--from local toward another machine is refused (exit 4)" 4

# --- depth, fan-out, scope ------------------------------------------------------
new_world limits
run env HERDR_PEERS_DEPTH=1 "$HELPER" ask local:w1:p2 "delegate further"
assert_rc "a marked delegate cannot ask (exit 3)" 3
for i in 1 2 3 4; do "$HELPER" ask local:w1:p2 "q$i" >/dev/null 2>&1; done
run "$HELPER" ask local:w1:p2 "q5"
assert_rc "the fifth open ask hits the fan-out cap (exit 4)" 4
run "$HELPER" ask --fanout 5 local:w1:p2 "q5"
assert_rc "raising the cap needs a reason (exit 2)" 2
run "$HELPER" ask --fanout 5 --reason "split review across five files" local:w1:p2 "q5"
assert_rc "raising the cap with a reason succeeds" 0
assert_eq "the override reason is recorded" "split review across five files" "$(field "$(last_log)" reason)"
first=$("$HELPER" log --open --json | head -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
run "$HELPER" cancel "$first" --reason "superseded"
assert_rc "cancel closes an open ask" 0
assert_eq "cancel is recorded" "cancelled" "$(field "$(last_log)" state)"
run "$HELPER" cancel "$first"
assert_rc "cancelling twice is refused (exit 3)" 3

new_world scope
run env HERDR_PEERS_SCOPE=local "$HELPER" ask bb22:w1:p1 "outside"
assert_rc "scope refuses another machine (exit 4)" 4
run "$HELPER" ask --scope local:w1 local:w2:p1 "other workspace"
assert_rc "workspace scope refuses another workspace (exit 4)" 4
run "$HELPER" ask --scope local:w1 local:w1:p2 "same workspace"
assert_rc "workspace scope allows its own workspace" 0
run "$HELPER" ask --scope 'bad scope!' local:w1:p2 "x"
assert_rc "an invalid scope entry is a usage error (exit 2)" 2

# --- receive: check records, depth via holding, reply exactly once ---------------
new_world receive
id=$("$HELPER" ask local:w1:p2 "Is the migration safe?")
pane_text local w1:p2 >"$WORK/ask.txt"
run as_pane w1:p2 "$HELPER" check --json "$WORK/ask.txt"
assert_rc "receiver check of a valid ask exits 0" 0
assert_eq "check records the inbound ask" "delegate launched" \
  "$(field "$(last_log)" role) $(field "$(last_log)" state)"
run as_pane w1:p2 "$HELPER" ask local:w2:p1 "can I delegate this?"
assert_rc "a peer holding an ask cannot delegate (exit 3)" 3
run as_pane w1:p2 "$HELPER" reply --message "$WORK/ask.txt" local:w1:p1 "$id" "Yes, it is additive only."
assert_rc "the delegate replies once" 0
reply=$(pane_text local w1:p1)
assert_contains "the reply reaches the caller pane" "$reply" "Yes, it is additive only."
assert_contains "the reply stamp is exact" "$reply" "[herdr-peers] protocol=1 reply-to=$id depth=1"
assert_contains "the reply carries the reply clause" "$reply" "This is a reply. Do not answer it."
assert_not_contains "the reply stamp offers no from= address" "$reply" "reply-to=$id depth=1 from="
run as_pane w1:p2 "$HELPER" reply local:w1:p1 "$id" "Second answer"
assert_rc "a second reply to the same id is refused (exit 3)" 3
run as_pane w1:p2 "$HELPER" check --json "$WORK/ask.txt"
assert_contains "an answered id is never answered again (rule 12)" "$OUT" '"rule": 12'
run "$HELPER" reply local:w1:p2 "$id" "answering my own question's reply"
assert_rc "replying to an id you originated is refused (exit 3)" 3
pane_text local w1:p1 >"$WORK/reply.txt"
run as_pane w1:p2 "$HELPER" reply --message "$WORK/reply.txt" local:w1:p1 "$id" "loop"
assert_rc "reply --message refuses a message that is a reply (exit 3)" 3
run "$HELPER" reply local:w1:p2 NOTANID "x"
assert_rc "reply with a malformed id is a usage error (exit 2)" 2

# Caller side: the reply is recorded before it is used.
run "$HELPER" check --json "$WORK/reply.txt"
assert_rc "the caller's check of the reply says never answer (exit 3)" 3
assert_contains "the reply is recorded against the ask" "$OUT" '"reply_status": "recorded"'
assert_eq "the caller record is completed" "caller completed" \
  "$(field "$(last_log)" role) $(field "$(last_log)" state)"
rp=$(field "$(last_log)" result_path)
assert_contains "result_path holds the reply body" "$(cat "$rp" 2>/dev/null)" "Yes, it is additive only."
run "$HELPER" check --json "$WORK/reply.txt"
assert_contains "the same reply again is already recorded" "$OUT" '"reply_status": "already-recorded"'
sed 's/additive only/a trap/' "$WORK/reply.txt" >"$WORK/forged.txt"
run "$HELPER" check --json "$WORK/forged.txt"
assert_contains "a different second reply is flagged as a conflict" "$OUT" '"reply_status": "conflict"'
run as_pane w2:p1 "$HELPER" check --json "$WORK/reply.txt"
assert_contains "a reply nobody here asked for is unsolicited" "$OUT" '"reply_status": "unsolicited"'

# Self-loop and scope on receive.
new_world selfloop
id=$("$HELPER" ask local:w1:p2 "loop me")
pane_text local w1:p2 >"$WORK/ask.txt"
run "$HELPER" check --json --no-record "$WORK/ask.txt"
assert_contains "an ask from your own pane is a self-loop (rule 10)" "$OUT" '"rule": 10'
run as_pane w1:p2 env HERDR_PEERS_SCOPE=bb22 "$HELPER" check --json --no-record "$WORK/ask.txt"
assert_contains "an ask from outside your scope is never answered (rule 11)" "$OUT" '"rule": 11'

# --- wait ---------------------------------------------------------------------
new_world wait
id=$("$HELPER" ask local:w1:p2 "What is 2+2?")
as_pane w1:p2 "$HELPER" reply local:w1:p1 "$id" "4" >/dev/null 2>&1
run "$HELPER" wait "$id" --timeout 5
assert_rc "wait returns once the reply is in this pane" 0
assert_eq "wait prints the reply body" "4" "$OUT"
assert_eq "wait records completion before printing" "completed" "$(field "$(last_log)" state)"
run "$HELPER" wait "$id" --timeout 2
assert_eq "wait on a completed ask prints the stored reply" "4" "$OUT"
id2=$("$HELPER" ask local:w1:p2 "Never answered")
run "$HELPER" wait "$id2" --timeout 0.3
assert_rc "wait times out with exit 5" 5
assert_contains "the timeout reports the peer state" "$ERR" "the peer is idle"
run "$HELPER" wait 01M4EZB9004TFF59TDWH9EDD1R --timeout 1
assert_rc "wait on an unknown id is a usage error (exit 2)" 2

# --- list ---------------------------------------------------------------------
new_world list
run "$HELPER" list
assert_rc "list succeeds" 0
assert_contains "list marks the caller row" "$OUT" "<- you"
assert_contains "list prints you-are line with the self machine" "$OUT" "saved here as machine aa11"
assert_contains "list shows remote agents" "$OUT" "box worker"
assert_contains "list keeps an unreachable machine as a row" "$OUT" "unreachable"
assert_contains "the unreachable row carries the diagnosis" "$OUT" "Connection refused"
assert_not_contains "list skips disabled machines" "$OUT" "cc33"
run "$HELPER" list --json
rows=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for r in d["rows"] if r.get("machine")=="aa11"))' 2>/dev/null)
assert_eq "the saved machine that is this server is not listed twice" "0" "$rows"
run "$HELPER" list --json --scope local
assert_not_contains "list honours the scope" "$OUT" "bb22"

# --- log, DWP_PLAN mirror, location ---------------------------------------------
new_world plan
mkdir -p "$WORK/plan"
run env DWP_PLAN="$WORK/plan" DWP_TASK=T-x "$HELPER" ask local:w1:p2 "plan-scoped ask"
mirror="$WORK/plan/analysis_results/delegations.ndjson"
check "DWP_PLAN mirrors the record into the plan" test -s "$mirror"
assert_eq "the mirrored record carries DWP_TASK" "T-x" "$(field "$(tail -1 "$mirror")" task)"
run env DWP_PLAN="$WORK/missing" "$HELPER" ask local:w1:p2 "plan dir missing"
assert_rc "a missing DWP_PLAN never blocks the helper" 0
run "$HELPER" log --json
lines=$(printf '%s\n' "$OUT" | python3 -c 'import json,sys; print(sum(1 for l in sys.stdin if l.strip() and json.loads(l)))' 2>/dev/null)
assert_eq "log --json prints one JSON record per line" "2" "$lines"

new_world location
git init -q "$WORK" && mkdir -p "$WORK/sub/dir" && cd "$WORK/sub/dir" || exit 2
run "$HELPER" log --path
assert_eq "the log lives at the git toplevel" "$(cd "$WORK" && pwd -P)/.herdr-peers/log.ndjson" "$OUT"
run env HERDR_PEERS_LOG="$WORLD/custom/peers.ndjson" "$HELPER" log --path
assert_eq "HERDR_PEERS_LOG overrides the location" "$WORLD/custom/peers.ndjson" "$OUT"
