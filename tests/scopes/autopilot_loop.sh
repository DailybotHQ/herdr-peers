# shellcheck shell=bash
# Part of scope `autopilot` (sourced by autopilot.sh): the plan loop — the
# machine report (`herdr-peers plans`, plans-v1) and what `autopilot --loop`
# does with it.

PLANS_SCHEMA="$ROOT/docs/schema/plans-v1.json"
LOOP_XDG_STATE=$XDG_STATE_HOME
# iso_world NAME — a fresh world with its own state root: the machine report reads
# the whole root when it cannot tell which Herdr server it is on.
iso_world() { new_world "$1"; export XDG_STATE_HOME="$WORLD/xdg-state"; }
VALIDATE="$ROOT/tests/tools/validate_records.py"
# plan_field JSON PLAN FIELD — one field of one plan of a plans-v1 report.
plan_field() { python3 -c 'import json,sys
for p in json.loads(sys.argv[1])["plans"]:
    if p["plan"] == sys.argv[2]:
        v = p[sys.argv[3]]
        print("null" if v is None else (json.dumps(v) if isinstance(v, (list, dict)) else v))' "$1" "$2" "$3"; }
# mkrepo DIR — a git repository with one commit.
mkrepo() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" -c user.email=t@example.invalid \
  -c user.name=t commit -q --allow-empty -m init; }
# mkstate REPO PLAN JSON — that plan's state.json.
mkstate() { mkdir -p "$1/.dwp/plans/$2" && printf '%s\n' "$3" >"$1/.dwp/plans/$2/state.json"; }
# claim REPO PLAN [ARGS...] — this pane claims the lead of PLAN from inside REPO.
claim() { local repo=$1 plan=$2; shift 2; (cd "$repo" && "$HELPER" lead claim --plan "$plan" "$@" >/dev/null 2>&1); }
V5_OPEN='{"status":"in_progress","completed_count":1,"checkpoint":{"task":2,"step":"tests"},"blocked":null,"tasks":[{"id":1,"status":"completed"},{"id":2,"status":"in_progress"}]}'
V5_DONE='{"status":"completed","completed_count":2,"checkpoint":{"task":2,"step":"done"},"blocked":null,"tasks":[{"id":1,"status":"completed"},{"id":2,"status":"completed"}]}'
V5_BLOCKED='{"status":"blocked","completed_count":1,"checkpoint":null,"blocked":{"task":2,"reason":"needs a login","since":"2026-01-01T00:00:00Z","needs":"C2 consent screen"},"tasks":[{"id":1,"status":"completed"},{"id":2,"status":"blocked"}]}'
V7_OPEN='{"schema":"https://deepworkplan.com/schema/plan-snapshot/v6.json","blocker":null,"checkpoint":null,"updated_at":"2026-01-01T00:00:00Z","tasks":[{"id":"T-a","status":"completed","criteria":[{"criterion":"AC-a","satisfied":true}]},{"id":"T-b","status":"pending","criteria":[]}]}'
V7_DONE='{"schema":"https://deepworkplan.com/schema/plan-snapshot/v6.json","blocker":null,"checkpoint":null,"updated_at":"2026-01-02T00:00:00Z","tasks":[{"id":"T-a","status":"completed","criteria":[]},{"id":"T-b","status":"completed","criteria":[]}]}'

# --- the machine report: each plan's class -----------------------------------------------
iso_world plans
REPO="$WORK/repo"; mkrepo "$REPO"
run env -u HERDR_ENV "$HELPER" plans --json
assert_rc "plans runs outside a Herdr pane" 0
assert_eq "with no lead record the list is empty, and known" "ok []" \
  "$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(d["state"], d["plans"])' "$OUT")"
mkstate "$REPO" PLAN_901_open "$V5_OPEN";       claim "$REPO" PLAN_901_open --succession local:w2:p1
mkstate "$REPO" PLAN_902_done "$V5_DONE";       claim "$REPO" PLAN_902_done
mkstate "$REPO" PLAN_903_blocked "$V5_BLOCKED"; claim "$REPO" PLAN_903_blocked
mkstate "$REPO" PLAN_904_v7open "$V7_OPEN";     claim "$REPO" PLAN_904_v7open
mkstate "$REPO" PLAN_905_v7done "$V7_DONE";     claim "$REPO" PLAN_905_v7done
mkstate "$REPO" PLAN_906_broken '{"status": "in_progress", "tasks": [';  claim "$REPO" PLAN_906_broken
mkstate "$REPO" PLAN_907_odd '{"status":"paused","tasks":[{"id":1,"status":"pending"}]}'; claim "$REPO" PLAN_907_odd
claim "$REPO" PLAN_908_missing
mkdir -p "$WORK/elsewhere/.dwp/plans/PLAN_909_link" "$REPO/.dwp/plans"
printf '%s\n' "$V5_OPEN" >"$WORK/elsewhere/.dwp/plans/PLAN_909_link/state.json"
ln -s "$WORK/elsewhere/.dwp/plans/PLAN_909_link" "$REPO/.dwp/plans/PLAN_909_link"
claim "$REPO" PLAN_909_link
mkstate "$REPO" PLAN_910_qualified "$V5_OPEN";  claim "$REPO" repo/PLAN_910_qualified
mkstate "$REPO" PLAN_911_released "$V5_OPEN";   claim "$REPO" PLAN_911_released
(cd "$REPO" && "$HELPER" lead release --plan PLAN_911_released >/dev/null 2>&1)
run env -u HERDR_ENV "$HELPER" plans --json
assert_rc "plans --json exits 0" 0
R=$OUT
printf '%s\n' "$R" >"$WORK/plans.json"
run python3 "$VALIDATE" --doc "$PLANS_SCHEMA" "$WORK/plans.json"
assert_rc "the report validates against plans-v1" 0
assert_eq "a v5 plan in progress is open" "open" "$(plan_field "$R" PLAN_901_open class)"
assert_eq "its lead is reported" "local:w1:p1" "$(plan_field "$R" PLAN_901_open lead)"
assert_eq "and its succession" '["local:w2:p1"]' "$(plan_field "$R" PLAN_901_open succession)"
assert_eq "a v5 plan with status completed is completed" "completed" "$(plan_field "$R" PLAN_902_done class)"
assert_eq "a plan with a blocker is blocked" "blocked" "$(plan_field "$R" PLAN_903_blocked class)"
assert_eq "the blocker's class is reported when the state names one" "C2" "$(plan_field "$R" PLAN_903_blocked blocker_class)"
assert_eq "a v7 snapshot with a pending task is open" "open" "$(plan_field "$R" PLAN_904_v7open class)"
assert_eq "a v7 snapshot with every task completed is completed" "completed" "$(plan_field "$R" PLAN_905_v7done class)"
assert_eq "invalid JSON is unreadable" "unreadable" "$(plan_field "$R" PLAN_906_broken class)"
assert_eq "an unknown status is unreadable, never guessed" "unreadable" "$(plan_field "$R" PLAN_907_odd class)"
assert_eq "a missing state file is unreadable" "unreadable" "$(plan_field "$R" PLAN_908_missing class)"
assert_eq "a plan directory that is a symlink out of the repository is unreadable" "unreadable" "$(plan_field "$R" PLAN_909_link class)"
assert_eq "a qualified plan id resolves by its last component" "open" "$(plan_field "$R" repo/PLAN_910_qualified class)"
assert_eq "a released plan has no lead" "null" "$(plan_field "$R" PLAN_911_released lead)"
assert_eq "the lead holds no open ask" "0" "$(plan_field "$R" PLAN_901_open open_asks)"

# The progress digest changes on progress and only on progress.
D1=$(plan_field "$R" PLAN_904_v7open progress)
mkstate "$REPO" PLAN_904_v7open "$(printf '%s' "$V7_OPEN" | sed 's/2026-01-01T00:00:00Z/2026-03-03T00:00:00Z/')"
run env -u HERDR_ENV "$HELPER" plans --json
assert_eq "a rewritten snapshot with the same progress keeps its digest" "$D1" "$(plan_field "$OUT" PLAN_904_v7open progress)"
mkstate "$REPO" PLAN_904_v7open "$(printf '%s' "$V7_OPEN" | sed 's/"status":"pending"/"status":"in_progress"/')"
run env -u HERDR_ENV "$HELPER" plans --json
D2=$(plan_field "$OUT" PLAN_904_v7open progress)
if [ -n "$D2" ] && [ "$D1" != "$D2" ]; then t_ok "a started task changes the digest"; else t_fail "a started task changes the digest" "$D1 vs $D2"; fi

# A foreign repo_root (the record came from another machine's path) is unreadable.
python3 - "$(state_dir)/leads" <<'PY'
import glob, json, sys
for path in glob.glob(sys.argv[1] + '/*.json'):
    data = json.load(open(path))
    if data['record']['plan'] == 'PLAN_902_done':
        data['repo_root'] = '/nonexistent/elsewhere'
        json.dump(data, open(path, 'w'))
PY
run env -u HERDR_ENV "$HELPER" plans --json
assert_eq "a repo_root that is not on this machine is unreadable" "unreadable" "$(plan_field "$OUT" PLAN_902_done class)"

# An open ask held by the lead is counted; an abandoned one is not.
id=$("$HELPER" ask local:w1:p2 "question" 2>/dev/null)
run env -u HERDR_ENV "$HELPER" plans --json
assert_eq "an ask the lead awaits is counted" "1" "$(plan_field "$OUT" PLAN_901_open open_asks)"
python3 - "$(state_log)" "$id" <<'PY'
import json, sys
lines = open(sys.argv[1]).read().splitlines()
out = []
for line in lines:
    rec = json.loads(line)
    if rec.get('id') == sys.argv[2]:
        rec['ts'] = '2020-01-01T00:00:00Z'
    out.append(json.dumps(rec, sort_keys=True))
open(sys.argv[1], 'w').write('\n'.join(out) + '\n')
PY
run env -u HERDR_ENV "$HELPER" plans --json
assert_eq "an ask launched long ago is not awaited" "0" "$(plan_field "$OUT" PLAN_901_open open_asks)"

# A plan kept in a linked worktree is found through the lead pane's directory.
iso_world worktree
REPO="$WORK/repo"; mkrepo "$REPO"
git -C "$REPO" worktree add -q "$WORK/tree" -b side
mkstate "$WORK/tree" PLAN_920_tree "$V5_OPEN"
claim "$WORK/tree" PLAN_920_tree
run env -u HERDR_ENV "$HELPER" plans --json
assert_eq "without the pane's directory the worktree plan is not found" "unreadable" "$(plan_field "$OUT" PLAN_920_tree class)"
python3 - "$FAKE_HERDR_DIR/local/agents.json" "$WORK/tree" <<'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
agents[0]['cwd'] = sys.argv[2]
json.dump(agents, open(sys.argv[1], 'w'))
PY
run "$HELPER" plans --json
assert_eq "with it, the plan in the worktree is open" "open" "$(plan_field "$OUT" PLAN_920_tree class)"
assert_contains "and the pane's repository and branch are reported" "$OUT" '"branch": "side"'
run "$HELPER" plans
assert_contains "the human table names the plan and its class" "$OUT" "PLAN_920_tree"

# An unreadable state root is unknown, never an empty list.
iso_world plans_unknown
mkdir -p "$XDG_STATE_HOME/herdr-peers"
chmod 000 "$XDG_STATE_HOME/herdr-peers"
run env -u HERDR_ENV "$HELPER" plans --json
chmod 700 "$XDG_STATE_HOME/herdr-peers"
if [ "$(id -u)" = 0 ]; then t_skip "unreadable state root (running as root)"; else
  assert_contains "an unreadable state root reports unknown" "$OUT" '"state": "unknown"'
  assert_rc "and exits non-zero" 1
fi

# =========================================================================================
# autopilot --loop
# =========================================================================================
export HERDR_PEERS_AUTOPILOT_GRACE=0
box_home() { printf '%s/ssh/box/home' "$FAKE_HERDR_DIR"; }
# box_claim REPO PLAN [ARGS...] — pane w1:p1 of the other machine claims PLAN there.
box_claim() { local repo=$1 plan=$2; shift 2; mkdir -p "$(box_home)"
  (cd "$repo" && HOME="$(box_home)" XDG_STATE_HOME="$(box_home)/.local/state" \
    FAKE_HERDR_SERVER_ID="box-$T_N" HERDR_PANE_ID=w1:p1 "$HELPER" lead claim --plan "$plan" "$@" >/dev/null 2>&1); }
# pane_claim PANE REPO PLAN [ARGS...] — a local pane claims PLAN.
pane_claim() { local pane=$1 repo=$2 plan=$3; shift 3
  (cd "$repo" && HERDR_PANE_ID="$pane" HERDR_WORKSPACE_ID="${pane%%:*}" "$HELPER" lead claim --plan "$plan" "$@" >/dev/null 2>&1); }
ssh_calls() { [ -f "$FAKE_HERDR_DIR/ssh.log" ] && wc -l <"$FAKE_HERDR_DIR/ssh.log" | tr -d ' ' || echo 0; }
ssh_argv() { python3 -c 'import json,sys
for line in open(sys.argv[1]):
    print(" ".join(json.loads(line)["argv"]))' "$FAKE_HERDR_DIR/ssh.log" 2>/dev/null | sort -u; }
prompt_count() { calls agent prompt; }
loop_world() { iso_world "$1"; set_state bb22 w1:p3 idle; REPO="$WORK/repo"; mkrepo "$REPO"; mkdir -p "$(box_home)"; }
fleet_file() { printf '%s/herdr-peers/fleet.json' "$XDG_STATE_HOME"; }

# --- a plan on this machine and a plan on another machine ----------------------------------
loop_world loop
mkstate "$REPO" PLAN_930_here "$V5_OPEN";  pane_claim w2:p1 "$REPO" PLAN_930_here
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
: >"$FAKE_HERDR_DIR/argv.log"
run "$HELPER" autopilot --loop --once
assert_rc "a loop pass exits 0" 0
assert_contains "the idle lead of an open plan here is asked to continue it" "$(last_prompt local w2:p1)" "Plan PLAN_930_here is not finished"
assert_contains "and told to respect its gates" "$(last_prompt local w2:p1)" "respecting its gates"
assert_contains "the idle lead of an open plan on another machine is asked too" "$(last_prompt bb22 w1:p1)" "Plan PLAN_931_there is not finished"
assert_eq "exactly one prompt per lead" "2" "$(prompt_count)"
assert_eq "the other machine is asked with the fixed argv, and only it" \
  "-o BatchMode=yes -o ConnectTimeout=8 -- box python3 -" "$(ssh_argv)"
assert_contains "the prompt is recorded with its plan" "$(ap_records)" "nudged local:w2:p1 plan_open"
assert_contains "on the other machine too" "$(ap_records)" "nudged bb22:w1:p1 plan_open"
run python3 "$VALIDATE" "$ROOT/skills/herdr-peers/templates/delegation-record.json" "$(state_log)"
assert_rc "loop records validate against the delegation-record schema" 0
assert_eq "the map is kept privately" "600" "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$(fleet_file)")"

# --- without --loop nothing of this happens -----------------------------------------------
loop_world noloop
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_930_here
: >"$FAKE_HERDR_DIR/argv.log"
run "$HELPER" autopilot --once
assert_eq "without --loop no machine is asked for its plans" "0" "$(ssh_calls)"
assert_eq "and no lead is prompted" "0" "$(prompt_count)"
if [ -e "$(fleet_file)" ]; then t_fail "without --loop no map is written"; else t_ok "without --loop no map is written"; fi

# --- dry run, --no-nudge ---------------------------------------------------------------------
loop_world loopdry
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_930_here
run "$HELPER" autopilot --loop --once --dry-run
assert_eq "a dry loop pass sends no prompt" "0" "$(prompt_count)"
assert_contains "and records what it would do" "$(ap_records)" "nudged local:w2:p1 plan_open action=prompt dry_run"
if [ -e "$(fleet_file)" ]; then t_fail "a dry loop pass writes no map"; else t_ok "a dry loop pass writes no map"; fi
"$HELPER" autopilot --interval 15 >"$WORK/d.out" 2>&1 &
daemon=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do "$HELPER" autopilot status 2>/dev/null | grep -q running && break; sleep 0.3; done
run "$HELPER" autopilot --loop --once --dry-run
assert_rc "a bounded dry run works beside a running autopilot" 0
run "$HELPER" autopilot --loop --once
assert_rc "a real second autopilot is still refused" 4
kill "$daemon" 2>/dev/null; wait "$daemon" 2>/dev/null
loop_world loopquiet
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_930_here
run "$HELPER" autopilot --loop --once --no-nudge
assert_eq "--no-nudge disables the loop prompt" "0" "$(prompt_count)"

# --- what is never prompted ---------------------------------------------------------------------
loop_world loopleft
mkstate "$REPO" PLAN_932_done "$V5_DONE";       pane_claim w2:p1 "$REPO" PLAN_932_done
mkstate "$REPO" PLAN_933_blocked "$V5_BLOCKED"; pane_claim w1:p2 "$REPO" PLAN_933_blocked
mkstate "$REPO" PLAN_934_mine "$V5_OPEN";       claim "$REPO" PLAN_934_mine
run "$HELPER" autopilot --loop --passes 2 --interval 0
assert_eq "a completed plan, a blocked plan and the daemon's own pane get no prompt" "0" "$(prompt_count)"
assert_eq "the blocked plan is recorded once" "1" "$(ap_records | grep -c 'left local:w1:p2 plan_blocked')"
loop_world loopdraft
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w1:p2 "$REPO" PLAN_930_here
show local w1:p2 codex__idle__update_banner_and_draft
run "$HELPER" autopilot --loop --once --catch-up
assert_eq "a lead with a human draft on its input line is not prompted" "0" "$(prompt_count)"
loop_world looplogin
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_930_here
show local w2:p1 claude__blocked__login_menu
run "$HELPER" autopilot --loop --once
assert_eq "a lead at a login screen is not prompted" "0" "$(prompt_count)"
loop_world loopexcl
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_930_here
run "$HELPER" autopilot --loop --once --exclude local:w2:p1
assert_eq "an excluded lead is not prompted" "0" "$(prompt_count)"
run "$HELPER" autopilot --loop --once --scope bb22
assert_eq "nor one outside the scope" "0" "$(prompt_count)"
loop_world loopgrace
mkstate "$REPO" PLAN_930_here "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_930_here
run env HERDR_PEERS_AUTOPILOT_GRACE=300 "$HELPER" autopilot --loop --once
assert_eq "a lead whose pane changed less than the grace period ago is not prompted" "0" "$(prompt_count)"
run env HERDR_PEERS_AUTOPILOT_GRACE=nope "$HELPER" autopilot --loop --once
assert_rc "a malformed grace period is a usage error" 2

# --- a machine that does not answer its report -------------------------------------------------
for mode in down garbage wrong big hostile nopython; do
  loop_world "loop_$mode"
  mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
  printf '%s\n' "$mode" >"$FAKE_HERDR_DIR/ssh/box/mode"
  run "$HELPER" autopilot --loop --passes 2 --interval 0
  assert_rc "a machine answering '$mode' does not fail the pass" 0
  assert_eq "and nobody there is prompted" "0" "$(prompt_count)"
  assert_eq "and no plan of that machine is acted on" "0" "$(ap_records | grep -c 'plan_')"
done
assert_eq "a machine without python3 is recorded once" "1" "$(ap_records | grep -c 'left bb22:- machine_unsupported')"
loop_world loop_slow
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
echo slow >"$FAKE_HERDR_DIR/ssh/box/mode"
run env HERDR_PEERS_AUTOPILOT_SSH_TIMEOUT=1 FAKE_SSH_SLEEP=5 "$HELPER" autopilot --loop --once
assert_rc "a machine that does not answer in time does not fail the pass" 0
assert_eq "and nobody there is prompted" "0" "$(prompt_count)"
loop_world loop_target
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
python3 - "$FAKE_HERDR_DIR/machines.json" <<'PY'
import json, sys
machines = json.load(open(sys.argv[1]))
for m in machines:
    if m['id'] == 'bb22':
        m['target'] = '-oProxyCommand=touch pwned'
json.dump(machines, open(sys.argv[1], 'w'))
PY
run "$HELPER" autopilot --loop --once
assert_eq "a saved target that could be read as an option never reaches ssh" "0" "$(ssh_calls)"
assert_contains "and is recorded" "$(ap_records)" "left bb22:- machine_target"

# --- the other machine keeps a copy of the map ----------------------------------------------------
loop_world fleet
mkstate "$REPO" PLAN_930_here "$V5_OPEN";  pane_claim w2:p1 "$REPO" PLAN_930_here --succession local:w1:p2
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
run "$HELPER" fleet
assert_rc "fleet with no map exits 7" 7
run "$HELPER" autopilot --loop --once
run env -u HERDR_ENV "$HELPER" fleet --json
assert_rc "fleet --json exits 0 once a loop has reported, and works outside a pane" 0
printf '%s\n' "$OUT" >"$WORK/fleet.json"
run python3 "$VALIDATE" --doc "$ROOT/docs/schema/fleet-v1.json" "$WORK/fleet.json"
assert_rc "the map validates against fleet-v1" 0
F=$(cat "$WORK/fleet.json")
assert_contains "the map lists the plan here" "$F" "PLAN_930_here"
assert_contains "and the plan on the other machine" "$F" "PLAN_931_there"
assert_contains "an agent carries its role in a plan" "$F" '"role": "lead"'
assert_contains "and a successor its role" "$F" '"role": "successor"'
assert_contains "a machine that did not answer is listed as unknown, not dropped" "$F" '"machine": "dd44"'
assert_contains "an agent's repository comes from its machine's report" "$F" "\"repo_root\": \"$(cd "$REPO" && pwd -P)\""
run "$HELPER" fleet
assert_contains "the human view names machines, plans and agents" "$OUT" "plan  PLAN_931_there"
python3 - "$SCRIPTS" "$(fleet_file)" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr_peers
io = herdr_peers.AutopilotIO(herdr_peers.Store(), 'w1:p1', None, None, quiet=True)
io.sources()
state, report = io.plans('bb22', {}, open(sys.argv[2]).read())
assert state == 'ok' and report['fleet'] == 'stored', (state, report)
state, report = io.plans('bb22', {}, open(sys.argv[2]).read())
assert report['fleet'] == 'unchanged', report
state, report = io.plans('bb22', {}, '{"schema": "not-a-fleet"}')
assert report['fleet'] == 'failed', report
PY
assert_eq "the other machine stores the map it is handed, once, and refuses what is not a map" "0" "$?"
run env HOME="$(box_home)" XDG_STATE_HOME="$(box_home)/.local/state" HERDR_ENV= "$HELPER" fleet --json
assert_rc "fleet on the other machine prints its copy" 0
assert_contains "with the same plans" "$OUT" "PLAN_930_here"
assert_eq "its copy is private" "600" "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$(box_home)/.local/state/herdr-peers/fleet.json")"
python3 - "$(fleet_file)" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
machine = [m for m in doc['machines'] if m['plans'] and m['agents']][0]
machine['label'] = 'box\x1b[31m'
machine['plans'][0]['lead'] = 'local:w2:p1\x1b]0;x\x07'
machine['agents'][0]['branch'] = 'main\x1b[2J'
json.dump(doc, open(sys.argv[1], 'w'))
PY
assert_eq "(the hostile map was written)" "0" "$?"
run "$HELPER" fleet
assert_contains "(the hostile label is shown, neutralised)" "$OUT" "box?[31m"
run "$HELPER" fleet
if printf '%s' "$OUT" | grep -q "$(printf '\033')"; then t_fail "terminal escapes in a stored map are neutralised in the human view"; else t_ok "terminal escapes in a stored map are neutralised in the human view"; fi
touch -t 202001010000 "$(fleet_file)"
run "$HELPER" fleet
assert_rc "a map nobody has synced for long exits 5" 5
assert_contains "and says it is stale" "$OUT" "STALE"

# --- --notify ------------------------------------------------------------------------------------------
loop_world notify
cat >"$WORK/tell" <<'SH'
#!/bin/sh
cat >>"$TELL_OUT"
SH
chmod +x "$WORK/tell"
export TELL_OUT="$WORK/events.ndjson"
mkstate "$REPO" PLAN_933_blocked "$V5_BLOCKED"; pane_claim w1:p2 "$REPO" PLAN_933_blocked
run "$HELPER" autopilot --loop --passes 2 --interval 0 --notify "$WORK/tell" --notify-env TELL_OUT
assert_rc "a loop with --notify exits 0" 0
assert_eq "a blocked plan is told once" "1" "$(wc -l <"$TELL_OUT" | tr -d ' ')"
run python3 "$VALIDATE" --doc "$ROOT/docs/schema/plan-event-v1.json" "$TELL_OUT"
assert_rc "the event validates against plan-event-v1" 0
assert_contains "it names the situation" "$(cat "$TELL_OUT")" '"event": "plan_blocked"'
assert_contains "the plan" "$(cat "$TELL_OUT")" '"plan": "PLAN_933_blocked"'
assert_contains "and the blocker's class" "$(cat "$TELL_OUT")" '"blocker_class": "C2"'
: >"$TELL_OUT"
run "$HELPER" autopilot --loop --once --dry-run --notify "$WORK/tell" --notify-env TELL_OUT
assert_eq "a dry run runs no notify command" "0" "$(wc -l <"$TELL_OUT" | tr -d ' ')"
run "$HELPER" autopilot --loop --once --notify "$WORK/tell ; touch $WORK/pwned"
if [ -e "$WORK/pwned" ]; then t_fail "the notify command runs without a shell"; else t_ok "the notify command runs without a shell"; fi
run "$HELPER" autopilot --once --notify "$WORK/tell"
assert_rc "--notify without --loop is a usage error" 2
run "$HELPER" autopilot --loop --once --notify ""
assert_rc "an empty notify command is a usage error" 2
run "$HELPER" autopilot --loop --once --notify "$WORK/no-such-program"
assert_rc "a notify program that does not exist is a usage error" 2
run "$HELPER" autopilot --loop --once --notify "$WORK/tell 'unbalanced"
assert_rc "unbalanced quotes are a usage error" 2
loop_world notifyfail
mkstate "$REPO" PLAN_933_blocked "$V5_BLOCKED"; pane_claim w1:p2 "$REPO" PLAN_933_blocked
mkstate "$REPO" PLAN_935_blocked "$V5_BLOCKED"; pane_claim w2:p1 "$REPO" PLAN_935_blocked
run "$HELPER" autopilot --loop --once --notify false
assert_rc "a failing notify command does not fail the pass" 0
assert_eq "and is recorded once" "1" "$(ap_records | grep -c 'notify_failed')"

# --- the loop's decisions, with scripted I/O and a scripted clock -------------------------------
run python3 - "$SCRIPTS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot

class IO(object):
    def __init__(self):
        self.rows, self.screens, self.sent, self.log = {'local': [], 'far': []}, {}, [], []
        self.reports, self.events, self.asked, self.down, self.fleets = {}, [], [], set(), []
        self.self_machine = None
    def sources(self): return ['local', 'far']
    def agents(self, machine):
        return None if machine in self.down else [dict(r) for r in self.rows.get(machine, [])]
    def read(self, machine, pane): return self.screens.get((machine, pane), '')
    def state(self, machine, pane): return [r for r in self.rows[machine] if r['pane'] == pane][0]['state']
    def keys(self, machine, pane, keys): self.sent.append(('keys', machine, pane)); return True
    def prompt(self, machine, pane, text): self.sent.append(('prompt', machine, pane, text)); return True
    def record(self, addr, kind, choice, outcome, dry, plan=None): self.log.append((outcome, addr, choice.cls, plan))
    def warn(self, addr, exc): self.warned = getattr(self, 'warned', []) + [(addr, type(exc).__name__)]
    def label(self, machine): return machine
    def identity(self): return {'pane': 'w1:p1', 'local_is': None}
    def plans(self, machine, panes, fleet_text):
        self.asked.append(machine)
        return self.reports.get(machine, ('ok', {'plans': [], 'agents': []}))
    def save_fleet(self, text): self.fleets.append(text)
    def event(self, event, dry): self.events.append((event['event'], event['plan'], event['machine']))

now = [1000.0]
def fresh(**kw):
    io = IO()
    return io, autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, loop=True, **kw)
def row(pane, state='idle', seq=1, agent='claude'):
    return {'pane': pane, 'state': state, 'agent': agent, 'seq': seq, 'turn': seq, 'you': False, 'cwd': '/r'}
def plan(pid='PLAN_1_a', cls='open', lead='local:w1:p2', progress='0' * 16, epoch=1, succession=(), lanes=(),
         asks=0, block=None):
    return {'plan': pid, 'class': cls, 'lead': lead, 'epoch': epoch, 'succession': list(succession),
            'lanes': list(lanes), 'repo_root': '/r', 'plan_dir': '/r/.dwp/plans/' + pid,
            'blocker_class': block, 'progress': progress, 'state_updated_at': None,
            'updated_at': '2026-01-01T00:00:00Z', 'open_asks': asks, 'lead_in_repo': True}
def report(io, machine, *plans):
    io.reports[machine] = ('ok', {'plans': list(plans), 'agents': []})
def prompts(io): return [s for s in io.sent if s[0] == 'prompt']
def step(ap, seconds=60):
    now[0] += seconds
    ap.run_pass()
def work_then_stop(io, machine='local', pane='w1:p2'):
    """The lead takes a turn and stops again: what makes a new prompt legitimate."""
    for r in io.rows[machine]:
        if r['pane'] == pane:
            r['seq'] += 1; r['turn'] += 1

# Grace: an idle lead is prompted only once its pane has been unchanged for the grace period.
io, ap = fresh()
io.rows['local'] = [row('w1:p2')]
report(io, 'local', plan())
ap.run_pass()
assert prompts(io) == [], prompts(io)
step(ap, 200)
assert prompts(io) == [], 'prompted inside the grace period'
step(ap, 120)
assert len(prompts(io)) == 1 and prompts(io)[0][3] == autopilot.LOOP_TEXT % 'PLAN_1_a', prompts(io)
assert ('nudged', 'local:w1:p2', 'plan_open', 'PLAN_1_a') in io.log, io.log
# No second prompt until the lead had a turn of its own.
step(ap, 400)
assert len(prompts(io)) == 1, 'prompted again without a turn in between'

# Stall: three prompts without progress, then plan_stalled once, an event, and silence.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]
report(io, 'local', plan())
ap.run_pass()
for _ in range(6):
    work_then_stop(io)
    step(ap, 1500)  # beyond the per-pane hourly window
assert len(prompts(io)) == 3, len(prompts(io))
assert io.log.count(('gave_up', 'local:w1:p2', 'plan_stalled', 'PLAN_1_a')) == 1, io.log
assert io.events == [('plan_stalled', 'PLAN_1_a', 'local')], io.events
# Progress lifts the stall and resets the count.
report(io, 'local', plan(progress='1' * 16))
work_then_stop(io)
step(ap, 1500)
assert len(prompts(io)) == 4, 'progress did not lift the stall'

# The per-pane hourly cap is shared with the prose nudge.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]
report(io, 'local', plan('PLAN_1_a'), plan('PLAN_2_b'), plan('PLAN_3_c'), plan('PLAN_4_d'))
ap.run_pass()
assert len(prompts(io)) == 1, 'one lead with several open plans gets one prompt per pass'
for _ in range(5):
    work_then_stop(io)
    step(ap, 60)
assert len(prompts(io)) == autopilot.MAX_NUDGES, len(prompts(io))

# A lead waiting for its lanes or for a reply is not stopped.
for kw, rows in (({'lanes': ['local:w1:p3']}, [row('w1:p2'), row('w1:p3', 'working')]),
                 ({'asks': 1}, [row('w1:p2')]), ({'asks': None}, [row('w1:p2')])):
    io, ap = fresh(grace=0)
    io.rows['local'] = rows
    report(io, 'local', plan(**kw))
    ap.run_pass(); step(ap)
    assert prompts(io) == [], kw
# A working lead, a blocked pane, a released plan and a lead on another machine: nothing.
for rows, kw in (([row('w1:p2', 'working')], {}), ([row('w1:p2', 'blocked')], {}),
                 ([row('w1:p2')], {'lead': None}), ([row('w1:p2')], {'lead': 'far:w1:p2'})):
    io, ap = fresh(grace=0)
    io.rows['local'] = rows
    report(io, 'local', plan(**kw))
    ap.run_pass(); step(ap)
    assert prompts(io) == [], (rows, kw)
# Unreadable and completed plans: nothing; a completed plan is told only if it was seen open.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]
report(io, 'local', plan('PLAN_1_a', 'unreadable'), plan('PLAN_2_b', 'completed'))
ap.run_pass(); step(ap)
assert prompts(io) == [] and io.events == [], (prompts(io), io.events)
report(io, 'local', plan('PLAN_3_c', 'open', lead='local:w9:p9', succession=[]))
io.rows['local'] = [row('w1:p2'), row('w9:p9', 'working')]
step(ap, 400)
report(io, 'local', plan('PLAN_3_c', 'completed', lead='local:w9:p9'))
step(ap, 400)
assert io.events == [('plan_completed', 'PLAN_3_c', 'local')], io.events
step(ap, 400)
assert len(io.events) == 1, 'completed told twice'

# Blocked: recorded and told once; again only after it left the situation and came back.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]
report(io, 'local', plan(cls='blocked', block='C2'))
ap.run_pass(); step(ap, 400); step(ap, 400)
assert io.log.count(('left', 'local:w1:p2', 'plan_blocked', 'PLAN_1_a')) == 1, io.log
assert io.events == [('plan_blocked', 'PLAN_1_a', 'local')] and prompts(io) == [], io.events
report(io, 'local', plan(cls='open', progress='2' * 16)); io.rows['local'] = [row('w1:p2', 'working')]
step(ap, 400)
report(io, 'local', plan(cls='blocked', progress='3' * 16))
step(ap, 400)
assert io.events.count(('plan_blocked', 'PLAN_1_a', 'local')) == 2, io.events

# A lead that is gone: the first reachable successor is asked once per epoch.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p3', 'working'), row('w1:p4'), row('w1:p5')]
report(io, 'local', plan(succession=['far:w7:p7', 'local:w1:p3', 'local:w1:p4', 'local:w1:p5']))
ap.run_pass(); step(ap)
sent = prompts(io)
assert len(sent) == 1 and sent[0][2] == 'w1:p4', sent  # a foreign address and a working successor are passed over
assert sent[0][3] == autopilot.TAKEOVER_TEXT % ('PLAN_1_a', 'no_agent', 'PLAN_1_a'), sent[0][3]
assert 'herdr-peers lead takeover --plan PLAN_1_a ' in sent[0][3] and '--reason' not in sent[0][3], \
    'the takeover is left to the helper\'s own gone check'
assert ('nudged', 'local:w1:p4', 'plan_takeover_prompted', 'PLAN_1_a') in io.log, io.log
step(ap, 400); step(ap, 400)
assert len(prompts(io)) == 1, 'asked twice at one epoch'
report(io, 'local', plan(epoch=2, lead='local:w1:p9', succession=['local:w1:p5']))
step(ap, 400)
assert len(prompts(io)) == 2 and prompts(io)[1][2] == 'w1:p5', prompts(io)  # a new epoch asks again
# Nobody to ask: plan_no_lead, recorded and told once.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p3', 'working')]
report(io, 'local', plan(succession=['local:w1:p3', 'local:w8:p8']))
ap.run_pass(); step(ap, 400); step(ap, 400)
assert prompts(io) == [] and io.events == [('plan_no_lead', 'PLAN_1_a', 'local')], (prompts(io), io.events)
assert io.log.count(('left', 'local:w1:p2', 'plan_no_lead', 'PLAN_1_a')) == 1, io.log
# A lead at its usage limit is gone only once the screen pass gave up on it.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2'), row('w1:p4')]
report(io, 'local', plan(succession=['local:w1:p4']))
ap.run_pass()
ap.panes['local:w1:p2'].limit_tries = 1
step(ap)
assert not [p for p in prompts(io) if 'takeover' in p[3]], 'one retry is not gone'
ap.panes['local:w1:p2'].limit_tries = autopilot.MAX_LIMIT_RETRIES
step(ap)
assert [p[2] for p in prompts(io) if 'takeover' in p[3]] == ['w1:p4'], prompts(io)
# A lead missing from one listing is not gone: it must be missing twice.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2', 'working'), row('w1:p4')]
report(io, 'local', plan(succession=['local:w1:p4']))
ap.run_pass()
io.rows['local'] = [row('w1:p4')]
step(ap)
assert prompts(io) == [], 'one missing listing is not a gone lead'
step(ap)
assert [p[2] for p in prompts(io)] == ['w1:p4'], prompts(io)
# A lead outside --scope is listed, so it is not gone; nobody outside the scope is prompted.
io, ap = fresh(grace=0)
lead = row('w1:p2', 'working'); lead['in_scope'] = False
out = row('w1:p5'); out['in_scope'] = False
io.rows['local'] = [lead, row('w1:p4'), out]
report(io, 'local', plan(succession=['local:w1:p5', 'local:w1:p4']), plan('PLAN_2_b', lead='local:w1:p5'))
ap.run_pass(); step(ap); step(ap)
assert prompts(io) == [], prompts(io)
# A lead record whose pane now works elsewhere (a reused pane id) is never prompted.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]
stale = plan(); stale['lead_in_repo'] = False
report(io, 'local', stale)
ap.run_pass(); step(ap, 400); step(ap, 400)
assert prompts(io) == [], prompts(io)
assert io.log.count(('left', 'local:w1:p2', 'plan_lead_moved', 'PLAN_1_a')) == 1, io.log
assert io.events == [('plan_lead_moved', 'PLAN_1_a', 'local')], io.events
# An error in the plan pass never stops the daemon.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]
broken = plan(); del broken['lead']
report(io, 'local', broken)
io.reports['far'] = ('ok', {'plans': [plan()], 'agents': 'nope'})
io.rows['far'] = [row('w1:p2')]
ap.run_pass(); step(ap)
assert getattr(io, 'warned', []), 'the error was reported'
# --no-nudge and --dry-run: no prompt of either kind.
for kw in ({'nudge': False}, {'dry_run': True}):
    io, ap = fresh(grace=0, **kw)
    io.rows['local'] = [row('w1:p2'), row('w1:p4')]
    report(io, 'local', plan('PLAN_1_a'), plan('PLAN_2_b', lead='local:w1:p9', succession=['local:w1:p4']))
    ap.run_pass(); step(ap)
    assert prompts(io) == [], kw
    assert (io.fleets == []) == bool(kw.get('dry_run')), 'a dry run writes no map'

# Cost: a machine is asked again only at the refresh cadence, sooner only while it is hot.
io, ap = fresh(grace=10 ** 6)
io.rows['local'] = [row('w1:p2', 'working')]
report(io, 'local', plan())
ap.run_pass()
for _ in range(4):
    step(ap, 60)
assert io.asked.count('local') == 1, io.asked  # the lead is working: nothing to ask about
step(ap, 60)
assert io.asked.count('local') == 2, io.asked  # 300 s: the refresh
io.rows['local'] = [row('w1:p2', 'idle', 2)]
step(ap, 60)
assert io.asked.count('local') == 3, io.asked  # an idle lead of an open plan: hot
io.reports['local'] = ('ok', {'plans': [plan(cls='blocked')], 'agents': []})
step(ap, 60); step(ap, 60); step(ap, 60)
assert io.asked.count('local') == 4, io.asked  # blocked: back to the refresh cadence
# An unknown answer keeps the last report: it is not "no plans".
io, ap = fresh(grace=0)
io.rows['far'] = [row('w1:p2', 'working')]
report(io, 'far', plan())
ap.run_pass()
io.reports['far'] = ('unknown', None)
io.rows['far'] = [row('w1:p2', 'idle', 2)]
step(ap, 400)
assert [p[1:3] for p in prompts(io)] == [('far', 'w1:p2')], prompts(io)
# A machine that does not answer its listing is neither asked nor prompted.
io, ap = fresh(grace=0)
io.rows['far'] = [row('w1:p2')]
report(io, 'far', plan())
io.down.add('far')
ap.run_pass(); step(ap)
assert 'far' not in io.asked and prompts(io) == [], (io.asked, prompts(io))
# The same plan id on two machines is two plans.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2')]; io.rows['far'] = [row('w1:p2')]
report(io, 'local', plan()); report(io, 'far', plan())
ap.run_pass()
assert sorted(p[1] for p in prompts(io)) == ['far', 'local'], prompts(io)
# Without --loop the plan pass does not exist.
io = IO()
ap = autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0)
io.rows['local'] = [row('w1:p2')]
report(io, 'local', plan())
ap.run_pass()
assert io.asked == [] and prompts(io) == [] and io.fleets == [], io.asked
print('ok')
PY
assert_rc "grace, stall, caps, waiting leads, blocked and completed plans, succession, cadence and unknown answers hold" 0
assert_eq "(scripted loop I/O ran to its end)" "ok" "$OUT"

# --- review fixes -------------------------------------------------------------------------------------
# A remote answer is cut at the limit while it streams, not after.
iso_world flood
export HERDR_PEERS_AUTOPILOT_GRACE=0
REPO="$WORK/repo"; mkrepo "$REPO"; mkdir -p "$(box_home)"
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
echo flood >"$FAKE_HERDR_DIR/ssh/box/mode"
t0=$(date +%s)
run env HERDR_PEERS_AUTOPILOT_SSH_TIMEOUT=20 "$HELPER" autopilot --loop --once
t1=$(date +%s)
assert_rc "a machine that floods its answer does not fail the pass" 0
if [ $((t1 - t0)) -lt 15 ]; then t_ok "the flood is cut at the size limit, not at the timeout"; else t_fail "the flood is cut at the size limit, not at the timeout" "took $((t1 - t0)) s"; fi
assert_eq "and nobody is prompted" "0" "$(prompt_count)"

# A bounded dry run writes no map, here or there.
iso_world drymap
REPO="$WORK/repo"; mkrepo "$REPO"; mkdir -p "$(box_home)"
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
run "$HELPER" autopilot --loop --passes 3 --interval 0 --dry-run
assert_rc "three dry loop passes exit 0" 0
if [ -e "$(fleet_file)" ] || [ -e "$(box_home)/.local/state/herdr-peers/fleet.json" ]; then
  t_fail "a dry run writes no map on any machine"; else t_ok "a dry run writes no map on any machine"; fi

# A state that keeps only its top-level status is read, not unreadable.
iso_world topstatus
REPO="$WORK/repo"; mkrepo "$REPO"
mkstate "$REPO" PLAN_950_top '{"status":"in_progress","blocked":null,"checkpoint":null}'
claim "$REPO" PLAN_950_top
run env -u HERDR_ENV "$HELPER" plans --json
assert_eq "a state with only a top-level status is classified" "open" "$(plan_field "$OUT" PLAN_950_top class)"

# A lead record whose pane now works outside the plan's repository.
iso_world moved
REPO="$WORK/repo"; mkrepo "$REPO"; mkrepo "$WORK/other"
mkstate "$REPO" PLAN_951_moved "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_951_moved
python3 - "$FAKE_HERDR_DIR/local/agents.json" "$WORK/other" <<'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
for a in agents:
    if a['pane_id'] == 'w2:p1':
        a['cwd'] = sys.argv[2]
json.dump(agents, open(sys.argv[1], 'w'))
PY
run "$HELPER" autopilot --loop --once
assert_eq "a lead pane that works elsewhere now is not told it leads" "0" "$(prompt_count)"
assert_contains "and the stale record is recorded" "$(ap_records)" "left local:w2:p1 plan_lead_moved"

# --notify: its own process group, killed whole; a minimal environment; a budget per pass.
iso_world notifyhang
REPO="$WORK/repo"; mkrepo "$REPO"
for n in 960 961 962; do mkstate "$REPO" "PLAN_${n}_b" "$V5_BLOCKED"; claim "$REPO" "PLAN_${n}_b"; done
cat >"$WORK/hang" <<'SH'
#!/bin/sh
env >"$0.env"
echo run >>"$0.runs"
sleep 30 &
echo $! >"$0.child"
wait
SH
chmod +x "$WORK/hang"
t0=$(date +%s)
run env HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT=2 MY_SECRET_TOKEN=s3cr3t-value "$HELPER" autopilot --loop --once --notify "$WORK/hang"
t1=$(date +%s)
assert_rc "a hanging notify command does not fail the pass" 0
if [ $((t1 - t0)) -lt 12 ]; then t_ok "three hanging events cost one budget, not three timeouts"; else t_fail "three hanging events cost one budget, not three timeouts" "took $((t1 - t0)) s"; fi
assert_eq "a hanging command spends the pass's budget: the other events wait" "1" "$(wc -l <"$WORK/hang.runs" | tr -d ' ')"
sleep 1
if kill -0 "$(cat "$WORK/hang.child")" 2>/dev/null; then t_fail "its children are killed with it"; kill "$(cat "$WORK/hang.child")"; else t_ok "its children are killed with it"; fi
assert_not_contains "the notify command does not get tokens" "$(cat "$WORK/hang.env")" "s3cr3t-value"
assert_contains "it gets PATH" "$(cat "$WORK/hang.env")" "PATH="
run env HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT=2 MY_SECRET_TOKEN=s3cr3t-value "$HELPER" autopilot --loop --once --catch-up --notify "$WORK/hang" --notify-env MY_SECRET_TOKEN
run "$HELPER" autopilot --loop --once --notify-env "BAD NAME" --notify "$WORK/hang"
assert_rc "a malformed --notify-env is a usage error" 2
run "$HELPER" autopilot --loop --once --notify-env HOME
assert_rc "--notify-env without --notify is a usage error" 2

# A report missing any key is refused, whatever the rest says.
run python3 - "$SCRIPTS" <<'PY'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_report
good = {'schema': 'herdr-peers/plans-v1', 'state': 'ok', 'agents': [
    {'pane': 'w1:p1', 'cwd': '/a', 'repo_root': None, 'branch': None}], 'plans': [{
    'plan': 'P1', 'lead': None, 'epoch': 1, 'succession': [], 'lanes': [], 'class': 'open',
    'progress': None, 'blocker_class': None, 'open_asks': None, 'repo_root': None, 'plan_dir': None,
    'state_updated_at': None, 'server': 'a' * 64, 'updated_at': '2026-01-01T00:00:00Z', 'lead_in_repo': None}]}
assert fleet_report.valid_report(good)
for key in sorted(fleet_report.PLAN_KEYS):
    broken = json.loads(json.dumps(good)); del broken['plans'][0][key]
    assert not fleet_report.valid_report(broken), 'a plan without %s is refused' % key
for key in sorted(fleet_report.AGENT_KEYS):
    broken = json.loads(json.dumps(good)); del broken['agents'][0][key]
    assert not fleet_report.valid_report(broken), 'an agent without %s is refused' % key
print('ok')
PY
assert_eq "a machine report missing any key is refused" "ok" "$OUT"

# A dry run never hands a machine the map, also on a later report.
run python3 - "$SCRIPTS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot
now = [1000.0]
class IO(object):
    self_machine = None
    def __init__(self): self.fleets_sent = []
    def sources(self): return ['local', 'far']
    def agents(self, m): return [{'pane': 'w1:p2', 'state': 'working', 'agent': 'claude', 'seq': 1, 'turn': 1, 'you': False, 'cwd': '/r'}]
    def read(self, m, p): return ''
    def state(self, m, p): return 'working'
    def plans(self, m, panes, fleet_text):
        self.fleets_sent.append(fleet_text)
        return 'ok', {'plans': [], 'agents': []}
    def record(self, *a, **k): pass
    def warn(self, addr, exc): raise exc
    def label(self, m): return m
    def identity(self): return {}
    def save_fleet(self, t): raise AssertionError('a dry run saved the map')
    def event(self, e, d): pass
io = IO()
ap = autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, loop=True, dry_run=True)
for _ in range(3):
    ap.run_pass(); now[0] += 400
assert len(io.fleets_sent) >= 4 and all(f is None for f in io.fleets_sent), io.fleets_sent
print('ok')
PY
assert_eq "a dry run hands no machine the map, on any pass" "ok" "$OUT"

# A lead outside --scope is still listed: never mistaken for gone, its successor never prompted.
iso_world scopelead
export HERDR_PEERS_AUTOPILOT_GRACE=0
REPO="$WORK/repo"; mkrepo "$REPO"
mkstate "$REPO" PLAN_970_scoped "$V5_OPEN"
pane_claim w2:p1 "$REPO" PLAN_970_scoped --succession local:w1:p2
set_state local w2:p1 working
: >"$FAKE_HERDR_DIR/argv.log"   # the claim's own lead notice to the successor is not the loop's
run "$HELPER" autopilot --loop --passes 3 --interval 0 --scope local:w1
assert_rc "a scoped loop exits 0" 0
assert_eq "a working lead outside the scope is not taken for gone" "0" "$(prompt_count)"

# A stop during the plan pass stops the daemon: only Exception is caught there.
run python3 - "$SCRIPTS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot, herdr_peers
class Halt(BaseException):
    pass
class IO(object):
    self_machine = None
    def sources(self): return ['local']
    def agents(self, m): return []
    def warn(self, addr, exc): pass
ap = autopilot.Autopilot(IO(), loop=True, sleep=lambda s: None, confirm=0)
def stop(listed): raise Halt()
ap.plans.run = stop
try:
    ap.run_pass()
except Halt:
    pass
else:
    raise AssertionError('a stop inside the plan pass was swallowed')
argv = herdr_peers.autopilot_option_argv({'interval': 60, 'loop': True, 'notify': '/bin/tell x',
                                          'notify_env': ['TELL_OUT']})
assert argv[-5:] == ['--loop', '--notify', '/bin/tell x', '--notify-env', 'TELL_OUT'], argv
print('ok')
PY
assert_eq "a stop inside the plan pass stops the daemon; background mode keeps --loop and --notify" "ok" "$OUT"
unset TELL_OUT HERDR_PEERS_AUTOPILOT_GRACE
export XDG_STATE_HOME=$LOOP_XDG_STATE
