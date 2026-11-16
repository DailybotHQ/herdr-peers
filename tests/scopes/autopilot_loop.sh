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
assert_eq "and says why: its state.json does not parse" "parse" "$(plan_field "$R" PLAN_906_broken unreadable_reason)"
assert_eq "an unknown shape is a generation this helper does not read" "shape" "$(plan_field "$R" PLAN_907_odd unreadable_reason)"
assert_eq "a missing state file says missing" "missing" "$(plan_field "$R" PLAN_908_missing unreadable_reason)"
assert_eq "a symlink out of the repository counts as missing" "missing" "$(plan_field "$R" PLAN_909_link unreadable_reason)"
assert_eq "a readable plan has no unreadable reason" "null" "$(plan_field "$R" PLAN_901_open unreadable_reason)"
assert_eq "a qualified plan id resolves by its last component" "open" "$(plan_field "$R" repo/PLAN_910_qualified class)"
assert_eq "a released plan has no lead" "null" "$(plan_field "$R" PLAN_911_released lead)"
assert_eq "the lead holds no open ask" "0" "$(plan_field "$R" PLAN_901_open open_asks)"
assert_eq "a v5 plan reports its tasks done" "1" "$(plan_field "$R" PLAN_901_open tasks_done)"
assert_eq "and its total" "2" "$(plan_field "$R" PLAN_901_open tasks_total)"
assert_eq "and its current task" '{"id": "2", "title": null}' "$(plan_field "$R" PLAN_901_open current_task)"
assert_eq "a v7 snapshot reports its current task with its id" '{"id": "T-b", "title": null}' "$(plan_field "$R" PLAN_904_v7open current_task)"
assert_eq "a completed plan has no current task" "null" "$(plan_field "$R" PLAN_902_done current_task)"
assert_eq "an unreadable plan has no progress" "null" "$(plan_field "$R" PLAN_906_broken tasks_total)"

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
python3 - "$FAKE_HERDR_DIR/local/agents.json" <<'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
agents[1]['terminal_title_stripped'] = 'evil\x1b]0;x\x07 title'
json.dump(agents, open(sys.argv[1], 'w'))
PY
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
assert_contains "an agent carries its session title" "$F" '"title": "box worker"'
assert_contains "a hostile session title is neutralised on the map" "$F" '"title": "evil ]0;x title"'
assert_contains "and when its state last changed" "$F" '"state_since": "20'
assert_contains "a plan carries its progress" "$F" '"tasks_total": 2'
assert_contains "and when its state last moved (2.1.0, for fleet ui's stale plans)" "$F" '"state_updated_at": '
assert_contains "an agent's repository comes from its machine's report" "$F" "\"repo_root\": \"$(cd "$REPO" && pwd -P)\""
run "$HELPER" fleet
assert_contains "the human view names machines, plans and agents" "$OUT" "plan  PLAN_931_there"
assert_contains "the human view shows a plan's progress" "$OUT" "1/2 tasks"
assert_contains "and an agent's title" "$OUT" '"box worker"'
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
assert_contains "and when each plan's state last moved" "$OUT" '"state_updated_at": '
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
# A lead at its usage limit is not gone: the screen pass retries it, and the
# helper would refuse a takeover on that evidence.
io, ap = fresh(grace=0)
io.rows['local'] = [row('w1:p2'), row('w1:p4')]
report(io, 'local', plan(succession=['local:w1:p4']))
ap.run_pass()
for tries in (1, autopilot.MAX_LIMIT_RETRIES):
    ap.panes['local:w1:p2'].limit_tries = tries
    step(ap)
assert not [p for p in prompts(io) if 'takeover' in p[3]], 'a usage limit never asks a successor'
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
# A per-event timeout of 60 s cannot widen a pass budget of 2 s (issue #43).
run env HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT=60 HERDR_PEERS_AUTOPILOT_NOTIFY_BUDGET=2 MY_SECRET_TOKEN=s3cr3t-value "$HELPER" autopilot --loop --once --notify "$WORK/hang"
t1=$(date +%s)
assert_rc "a hanging notify command does not fail the pass" 0
if [ $((t1 - t0)) -lt 12 ]; then t_ok "a long per-event timeout never widens the pass's notify budget"; else t_fail "a long per-event timeout never widens the pass's notify budget" "took $((t1 - t0)) s"; fi
assert_eq "a hanging command spends the pass's budget: the other events wait" "1" "$(wc -l <"$WORK/hang.runs" | tr -d ' ')"
sleep 1
if kill -0 "$(cat "$WORK/hang.child")" 2>/dev/null; then t_fail "its children are killed with it"; kill "$(cat "$WORK/hang.child")"; else t_ok "its children are killed with it"; fi
assert_not_contains "the notify command does not get tokens" "$(cat "$WORK/hang.env")" "s3cr3t-value"
assert_contains "it gets PATH" "$(cat "$WORK/hang.env")" "PATH="
run env HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT=2 HERDR_PEERS_AUTOPILOT_NOTIFY_BUDGET=2 MY_SECRET_TOKEN=s3cr3t-value "$HELPER" autopilot --loop --once --catch-up --notify "$WORK/hang" --notify-env MY_SECRET_TOKEN
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
    'state_updated_at': None, 'server': 'a' * 64, 'updated_at': '2026-01-01T00:00:00Z', 'lead_in_repo': None,
    'tasks_done': None, 'tasks_total': None, 'current_task': None, 'detail': None, 'appoint': None, 'appointed': False, 'appointed': False}]}
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

# --- titles and task titles are neutralised and cut -------------------------------------------------
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

# A lead working in a linked worktree of the plan's repository is still in it.
iso_world wtlead
REPO="$WORK/main"; mkrepo "$REPO"; mkrepo "$WORK/elsewhere"
git -C "$REPO" worktree add -q "$WORK/wt" -b side
mkstate "$REPO" PLAN_980_wt "$V5_OPEN"
pane_claim w2:p1 "$REPO" PLAN_980_wt
python3 - "$FAKE_HERDR_DIR/local/agents.json" "$WORK/wt" <<'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
for a in agents:
    if a['pane_id'] == 'w2:p1':
        a['cwd'] = sys.argv[2]
json.dump(agents, open(sys.argv[1], 'w'))
PY
run "$HELPER" plans --json
assert_eq "a lead in a linked worktree of the plan's repository is in it" "True" "$(plan_field "$OUT" PLAN_980_wt lead_in_repo)"
assert_eq "(the plan itself is found)" "open" "$(plan_field "$OUT" PLAN_980_wt class)"
python3 - "$FAKE_HERDR_DIR/local/agents.json" "$WORK/elsewhere" <<'PY'
import json, sys
agents = json.load(open(sys.argv[1]))
for a in agents:
    if a['pane_id'] == 'w2:p1':
        a['cwd'] = sys.argv[2]
json.dump(agents, open(sys.argv[1], 'w'))
PY
run "$HELPER" plans --json
assert_eq "a lead in another repository is not" "False" "$(plan_field "$OUT" PLAN_980_wt lead_in_repo)"

# Agents outside --scope never reach the map, here or on another machine.
loop_world scopemap
mkstate "$REPO" PLAN_931_there "$V7_OPEN"; box_claim "$REPO" PLAN_931_there
run "$HELPER" autopilot --loop --once --scope local:w1,bb22
assert_rc "a scoped loop pass exits 0" 0
assert_contains "(an in-scope agent is on the map)" "$(cat "$(fleet_file)")" '"pane": "w1:p2"'
assert_not_contains "an agent outside the scope is not on the map" "$(cat "$(fleet_file)")" '"pane": "w2:p1"'
run "$HELPER" autopilot --loop --once --scope local:w1,bb22
assert_not_contains "nor on the copy left on another machine" "$(cat "$(box_home)/.local/state/herdr-peers/fleet.json" 2>/dev/null)" '"pane": "w2:p1"'

# --- titles and task titles are neutralised and cut -------------------------------------------------
run python3 - "$SCRIPTS" <<'PY'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot, fleet_report
hostile = 'x\x1b[31mred\x07‮' + 'y' * 500
t = autopilot.clean_title(hostile)
assert t is not None and len(t) <= 120 and not any(ord(c) < 32 or c == '‮' for c in t), repr(t)
state = {'tasks': [{'id': 'T-1', 'status': 'in_progress', 'title': hostile},
                   {'id': '$(rm -rf /)', 'status': 'pending'}]}
done, total, cur = fleet_report.task_progress(state)
assert (done, total) == (0, 2) and len(cur['title']) <= 120 and '\x1b' not in cur['title'], cur
state['tasks'][0]['status'] = 'completed'
assert fleet_report.task_progress(state)[2]['id'] is None, 'a task id outside the pattern is dropped'
report = {'schema': 'herdr-peers/plans-v1', 'state': 'ok', 'agents': [], 'plans': [{
    'plan': 'P1', 'lead': None, 'epoch': 1, 'succession': [], 'lanes': [], 'class': 'open',
    'progress': None, 'blocker_class': None, 'open_asks': None, 'repo_root': None, 'plan_dir': None,
    'state_updated_at': None, 'tasks_done': 1, 'tasks_total': 2, 'server': 'a' * 64,
    'updated_at': '2026-01-01T00:00:00Z', 'lead_in_repo': None, 'detail': None, 'appoint': None, 'appointed': False,
    'current_task': {'id': 'T-1', 'title': 'bad\x1b[0m'}}]}
assert not fleet_report.valid_report(report), 'a raw control character in a task title is refused'
report['plans'][0]['current_task']['title'] = 'fine'
assert fleet_report.valid_report(report)
report['plans'][0]['tasks_total'] = -1
assert not fleet_report.valid_report(report)
print('ok')
PY
assert_eq "titles and task titles are neutralised, cut and validated" "ok" "$OUT"

# --- a plan's detail: title, tasks, blocker and the summary its agents keep ---------------------------
iso_world detail
REPO="$WORK/repo"; mkrepo "$REPO"
mkstate "$REPO" PLAN_940_detail '{"status":"blocked","completed_count":1,"checkpoint":null,"blocked":{"task":2,"reason":"needs \u001b[31mthe staging key","since":"2026-01-01T00:00:00Z","needs":"C1 approval"},"tasks":[{"id":1,"status":"completed","title":"Write the \u001b]0;pwn\u0007parser"},{"id":2,"status":"blocked","file":"2.task_deploy.md"}]}'
printf '{"title": "Ship the parser"}\n' >"$REPO/.dwp/plans/PLAN_940_detail/manifest.json"
cat >"$REPO/.dwp/plans/PLAN_940_detail/PROGRESS.md" <<'MD'
# PROGRESS — PLAN_940_detail

## Goal

- Ship the parser.

~~~
ignored fence
~~~
---
- Next action: wait for the staging key.
MD
claim "$REPO" PLAN_940_detail
mkstate "$REPO" PLAN_941_done "$V5_DONE"; claim "$REPO" PLAN_941_done
python3 - "$REPO/.dwp/plans" <<'PY'
import json, sys
tasks = [{'id': i, 'status': 'completed' if i < 80 else 'pending', 'title': 'task %d' % i} for i in range(100)]
import os
os.makedirs(sys.argv[1] + '/PLAN_942_long', exist_ok=True)
json.dump({'status': 'in_progress', 'blocked': None, 'checkpoint': None, 'tasks': tasks},
          open(sys.argv[1] + '/PLAN_942_long/state.json', 'w'))
PY
claim "$REPO" PLAN_942_long
run env -u HERDR_ENV "$HELPER" plans --json
R=$OUT
printf '%s\n' "$R" >"$WORK/plans.json"
run python3 "$VALIDATE" --doc "$PLANS_SCHEMA" "$WORK/plans.json"
assert_rc "a report with plan details validates against plans-v1" 0
D=$(plan_field "$R" PLAN_940_detail detail)
assert_contains "the detail carries the plan's title" "$D" '"title": "Ship the parser"'
assert_contains "every task with its status" "$D" '"status": "blocked", "title": "2.task_deploy.md"'
assert_contains "a task title is neutralised on the map" "$D" '"title": "Write the ]0;pwn parser"'
assert_contains "the blocker as recorded, neutralised" "$D" '"reason": "needs [31mthe staging key"'
assert_contains "and what it needs" "$D" '"needs": "C1 approval"'
assert_contains "the summary its agents keep" "$D" 'Next action: wait for the staging key.'
assert_not_contains "without the file's own title" "$D" 'PROGRESS — PLAN_940'
assert_not_contains "or fenced text" "$D" 'ignored fence'
assert_eq "a finished plan carries no detail" "null" "$(plan_field "$R" PLAN_941_done detail)"
L=$(plan_field "$R" PLAN_942_long detail)
assert_contains "a long plan is shown as a window around its current task" "$L" '"tasks_from": 36'
assert_contains "(the current task is in the window)" "$L" '"title": "task 80"'

# Plan content stays on the daemon's machine; the copies elsewhere are reduced; tokens never travel.
loop_world mapcontent
mkstate "$REPO" PLAN_990_content "$V5_OPEN"
FAKE_TOKEN="ghp""_$(printf '%s' abcdefghijklmnopqrstuvwxyz0123456789)"   # built at run time: no token shape in the file
printf '# PROGRESS\n- Next action: deploy with key %s then report.\n' "$FAKE_TOKEN" >"$REPO/.dwp/plans/PLAN_990_content/PROGRESS.md"
pane_claim w2:p1 "$REPO" PLAN_990_content
run "$HELPER" autopilot --loop --once
run "$HELPER" autopilot --loop --once
LOCAL=$(cat "$(fleet_file)")
REMOTE=$(cat "$(box_home)/.local/state/herdr-peers/fleet.json" 2>/dev/null)
assert_contains "the daemon's own map keeps the plan's summary" "$LOCAL" "Next action: deploy with key"
assert_contains "with token shapes redacted" "$LOCAL" "[redacted]"
assert_not_contains "and never the token" "$LOCAL" "ghp_abcdefghij"
assert_contains "(the other machine has a copy)" "$REMOTE" "PLAN_990_content"
assert_not_contains "the copy elsewhere carries no plan summary" "$REMOTE" "Next action"
assert_not_contains "no plan detail" "$REMOTE" '"summary"'
assert_contains "but the plan's task counts and current task" "$REMOTE" '"tasks_total": 2'
assert_not_contains "no working directories" "$REMOTE" "\"cwd\": \"/"
assert_contains "but the plan's progress digest" "$REMOTE" '"progress": "'
run python3 - "$SCRIPTS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot, fleet_report
t = 'x؜­\U000E0041y sk-ant-' + 'a' * 30 + ' z'
assert fleet_report.clean_text(t) == 'x y [redacted] z', repr(fleet_report.clean_text(t))
assert autopilot.clean_title(t) == 'x y [redacted] z'
# Over the size cap, plan details go first and it is recorded once.
class IO(object):
    self_machine = None
    def __init__(self): self.saved, self.records = [], []
    def label(self, m): return m
    def identity(self): return {}
    def save_fleet(self, text): self.saved.append(text)
class AP(object):
    dry_run = False
    panes = {}
    brain = None
    def __init__(self, io): self.io = io
    def record(self, addr, kind, choice, outcome, plan=None): self.io.records.append(choice.cls)
io = IO(); ap = AP(io)
loop = autopilot.PlanLoop(ap)
huge = {'title': 'x', 'tasks': [], 'tasks_from': 0, 'blocker': None, 'summary': ['y' * 200] * 14, 'summary_at': None}
plans = [{'plan': 'P%d' % i, 'class': 'open', 'lead': None, 'epoch': 1, 'succession': [], 'lanes': [],
          'repo_root': '/r', 'blocker_class': None, 'progress': None, 'updated_at': None,
          'detail': dict(huge, title='t' * 100 + str(i))} for i in range(900)]
loop.machines['local'] = {'at': 0, 'state': 'ok', 'report': {'plans': plans, 'agents': []}}
loop.publish({'local': []}, 1000.0)
loop.fleet_key = None
loop.publish({'local': []}, 1001.0)
assert len(io.saved[-1].encode()) <= autopilot.MAP_MAX_BYTES, len(io.saved[-1])
assert '"detail": null' in io.saved[-1] and io.records.count('fleet_too_large') == 1, io.records
print('ok')
PY
assert_eq "free text is cleaned and redacted; a map over the cap drops plan details, recorded once" "ok" "$OUT"

# --- the appointment drill (PLAN_009): the lead dies mid-plan, a lane takes it, the lead comes back ---
drop_agent() { python3 -c 'import json,sys; p, pane = sys.argv[1:3]; a=[x for x in json.load(open(p)) if x["pane_id"]!=pane]; json.dump(a, open(p,"w"))' "$FAKE_HERDR_DIR/local/agents.json" "$1"; }
cat >"$WORK/tell" <<'SH'
#!/bin/sh
cat >>"$0.events"
SH
chmod +x "$WORK/tell"
appoint_world() {
  loop_world "$1"; cp "$WORK/../tell" "$WORK/tell" 2>/dev/null || true
  mkstate "$REPO" PLAN_970_appoint "$V5_OPEN"
  pane_claim w2:p1 "$REPO" PLAN_970_appoint --succession local:w9:p8 --lanes local:w9:p7,local:w1:p2 "$2" --any-kind
}
TELL="$WORK/tell"
appoint_world appointdrill --allow-appointment
drop_agent w2:p1
export HERDR_PEERS_AUTOPILOT_APPOINT_GRACE=0 HERDR_PEERS_APPOINT_PROBE_GAP=0
run "$HELPER" autopilot --loop --passes 3 --interval 0 --notify "$TELL"
assert_contains "without --appoint the daemon only reports the plan without a lead" "$(ap_records)" "plan_no_lead"
assert_eq "and asks no lane" "" "$(last_prompt local w1:p2 | grep -o 'as-lane')"
: >"$FAKE_HERDR_DIR/argv.log"
run "$HELPER" autopilot --loop --appoint --passes 3 --interval 0 --notify "$TELL"
assert_rc "--appoint runs" 0
assert_contains "the first live lane is asked to take the lead (the gone lane before it is skipped)" \
  "$(last_prompt local w1:p2)" "herdr-peers lead takeover --plan PLAN_970_appoint --as-lane"
assert_contains "the prompt says to verify before a merge, tag or release" "$(last_prompt local w1:p2)" "lead verify"
assert_contains "the appointment prompt is recorded" "$(ap_records)" "plan_appointment_prompted"
assert_contains "and reported" "$(cat "$TELL.events")" '"event": "plan_appointment_prompted"'
run sh -c "cd '$REPO' && HERDR_PANE_ID=w1:p2 '$HELPER' lead takeover --plan PLAN_970_appoint --as-lane"
assert_rc "the lane's helper checks twice and takes the lead" 0
run "$HELPER" autopilot --loop --appoint --passes 2 --interval 0 --notify "$TELL"
assert_contains "the daemon reports the appointment once it sees it" "$(cat "$TELL.events")" '"event": "plan_appointed"'
assert_eq "the appointee leads at epoch 2" "local:w1:p2 2" \
  "$(cd "$REPO" && "$HELPER" lead show --plan PLAN_970_appoint --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["lead"], d["epoch"])')"
# The lead comes back: it is refused as lead and cannot pass verify.
python3 - "$FAKE_HERDR_DIR/local/agents.json" <<'PY'
import json, sys
p = sys.argv[1]; a = json.load(open(p))
a.append({"agent": "claude", "agent_status": "idle", "pane_id": "w2:p1", "workspace_id": "w2", "tab_id": "w2:t1", "terminal_id": "term_local_w2p1", "terminal_title_stripped": "back", "cwd": "/work", "focused": False})
json.dump(a, open(p, "w"))
PY
run sh -c "cd '$REPO' && HERDR_PANE_ID=w2:p1 HERDR_WORKSPACE_ID=w2 '$HELPER' lead verify --plan PLAN_970_appoint"
assert_rc "the returning lead fails lead verify (exit 4)" 4
run sh -c "cd '$REPO' && HERDR_PANE_ID=w2:p1 HERDR_WORKSPACE_ID=w2 '$HELPER' lead release --plan PLAN_970_appoint"
assert_rc "and cannot act as lead (exit 4)" 4
run sh -c "cd '$REPO' && HERDR_PANE_ID=w1:p2 '$HELPER' lead verify --plan PLAN_970_appoint"
assert_rc "the appointee passes lead verify" 0
if grep -q '"push"\|"update-ref"\|"notes"' "$FAKE_HERDR_DIR/argv.log" "$FAKE_HERDR_DIR/ssh.log" 2>/dev/null; then
  t_fail "the drill writes nothing to git or a remote"; else t_ok "the drill writes nothing to git or a remote"; fi

# No grant: --appoint changes nothing.
appoint_world appointnogrant --no-appointment
drop_agent w2:p1
run "$HELPER" autopilot --loop --appoint --passes 3 --interval 0
assert_contains "without the grant the plan is only reported" "$(ap_records)" "plan_no_lead"
assert_eq "and no lane is asked" "" "$(last_prompt local w1:p2 | grep -o 'as-lane')"
# The grace: evidence younger than the grace never appoints.
appoint_world appointgrace --allow-appointment
drop_agent w2:p1
run env HERDR_PEERS_AUTOPILOT_APPOINT_GRACE=3600 "$HELPER" autopilot --loop --appoint --passes 4 --interval 0
assert_eq "within the grace no lane is asked" "" "$(last_prompt local w1:p2 | grep -o 'as-lane')"
# A successor that is alive is asked instead; the lane is never asked over it.
loop_world appointsucc; mkstate "$REPO" PLAN_971_succ "$V5_OPEN"
pane_claim w2:p1 "$REPO" PLAN_971_succ --succession local:w1:p2 --lanes local:w9:p7 --allow-appointment --any-kind
drop_agent w2:p1
run "$HELPER" autopilot --loop --appoint --passes 3 --interval 0
assert_contains "a live successor gets the takeover prompt, not an appointment" "$(last_prompt local w1:p2)" \
  "lead takeover --plan PLAN_971_succ —"
# A successor that is alive but cannot be prompted (here the daemon's own
# pane) still blocks an appointment: a lane is never asked over a live successor.
loop_world appointbusy; mkstate "$REPO" PLAN_972_busy "$V5_OPEN"
pane_claim w2:p1 "$REPO" PLAN_972_busy --succession local:w1:p1 --lanes local:w1:p2 --allow-appointment --any-kind
drop_agent w2:p1
run "$HELPER" autopilot --loop --appoint --passes 4 --interval 0
assert_eq "a live successor, even one that cannot be prompted, blocks an appointment" "" \
  "$(last_prompt local w1:p2 | grep -o 'as-lane')"
run "$HELPER" autopilot --appoint --once
assert_rc "--appoint needs --loop (exit 2)" 2
# The grace starts over when a successor comes back (review #7).
out=$(python3 - "$SCRIPTS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot as a
class IO(object):
    def event(self, *args): pass
    def read(self, *args): return None
t = [1000.0]
ap = a.Autopilot(IO(), loop=True, appoint=True, appoint_grace=100, clock=lambda: t[0])
memo = a.PlanMemo()
plan = {'plan': 'P', 'appoint': 'lanes', 'succession': ['local:w2:p2'], 'lanes': ['local:w1:p2'],
        'progress': 'd1', 'epoch': 1, 'lead': 'local:w9:p9', 'repo_root': None}
ap.plans.appoint(memo, 'local', plan, {}, set())
first = memo.gone_at
t[0] = 1050.0
ap.plans.appoint(memo, 'local', plan, {'w2:p2': {'pane': 'w2:p2'}}, set())
back = memo.gone_at
t[0] = 1080.0
ap.plans.appoint(memo, 'local', plan, {}, set())
print(first, back, memo.gone_at)
PY
)
assert_eq "a returning successor resets the appointment grace" "1000.0 None 1080.0" "$out"
unset HERDR_PEERS_AUTOPILOT_APPOINT_GRACE HERDR_PEERS_APPOINT_PROBE_GAP
unset TELL_OUT HERDR_PEERS_AUTOPILOT_GRACE

# --- pack 8.0.0 records: journal-event/v8 (a blocker event) and plan-snapshot/v8 (a blocker object) ---
run python3 - "$SCRIPTS" "$WORK" <<'PY'
import json, os, sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_report, fleet_ui
root = sys.argv[2]
J8 = 'https://deepworkplan.com/schema/journal-event/v8.json'
S8 = 'https://deepworkplan.com/schema/plan-snapshot/v8.json'
def plan_dir(name, events, snapshot):
    d = os.path.join(root, 'v8', name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'journal.ndjson'), 'w') as fh:
        for n, e in enumerate(events, 1):
            fh.write(json.dumps(dict({'schema': J8, 'seq': n, 'ts': '2026-11-16T10:00:%02dZ' % n}, **e)) + '\n')
    with open(os.path.join(d, 'state.json'), 'w') as fh:
        json.dump(snapshot, fh)
    return d
blocker = {'class': 'C3', 'reason': 'a flaky migration test keeps failing',
           'needs': 'a green migration run', 'resolver': 'lead', 'task': 'T-b', 'since': '2026-11-16T10:00:03Z'}
snap = lambda blk, statuses=('completed', 'in_progress'), at='2026-11-16T10:00:05Z': {
    'schema': S8, 'blocker': blk, 'checkpoint': None, 'updated_at': at,
    'tasks': [{'id': 'T-%s' % c, 'status': st, 'criteria': []} for c, st in zip('ab', statuses)]}
approval = {'type': 'approval', 'contract_id': 'c' * 64}
raised = {'type': 'blocker', 'state': 'raised', 'task': 'T-b', 'reason': blocker['reason'], 'resolver': 'lead',
          'note': 'raised right after the task_start of T-b'}
resolved = {'type': 'blocker', 'state': 'resolved', 'task': 'T-b', 'note': 'resolved; next task_start pending'}

# 1. A v8 plan that started a task, then raised a blocker: started, blocked, the blocker projected.
d = plan_dir('P8_blocked', [approval, {'type': 'task_start', 'task': 'T-a'}, raised], snap(blocker))
state = json.load(open(os.path.join(d, 'state.json')))
cls, block_class, progress = fleet_report.classify(state)
assert cls == 'blocked' and block_class == 'C3' and progress, (cls, block_class)
assert fleet_report.plan_started(d, state)
det = fleet_report.plan_detail(state, d)
assert det['blocker'] == {'reason': 'a flaky migration test keeps failing',
                          'needs': 'a green migration run', 'resolver': 'lead'}, det['blocker']
last, started = fleet_report.journal_facts(d)
assert last['type'] == 'approval' and started is True
# the class the v8 snapshot records wins over a class named in its prose; an unknown class backs no resolver
import brain
prose = dict(blocker, reason='waiting on C1-style approval wording, not the class')
assert fleet_report.classify(snap(prose))[1] == 'C3'
odd = dict(blocker, **{'class': 'C9'})
assert fleet_report.classify(snap(odd))[1] is None and fleet_report.plan_detail(snap(odd), d)['blocker']['resolver'] is None
for klass, askable in (('C3', True), ('C4', True), ('C7', True), ('C1', False), ('C2', False), ('C5', False),
                       ('C6', False), ('C9', False)):
    st = snap(dict(blocker, **{'class': klass}))
    row = {'blocker_class': fleet_report.classify(st)[1], 'detail': fleet_report.plan_detail(st, d)}
    assert brain.blocker_is_askable(row) is askable, (klass, row)
st = snap(dict(blocker, resolver='human'))
assert not brain.blocker_is_askable({'blocker_class': 'C3', 'detail': fleet_report.plan_detail(st, d)})

# 2. A v8 journal with ONLY blocker events (whose text even says "task_start"): never a task start.
d = plan_dir('P8_only_blockers', [approval, raised, resolved],
             snap(None, statuses=('pending', 'pending')))
state = json.load(open(os.path.join(d, 'state.json')))
last, started = fleet_report.journal_facts(d)
assert started is False, 'a blocker event is never read as a task start'
assert not fleet_report.plan_started(d, state)
assert fleet_report.classify(state)[0] == 'open'

# 3. Resolved: the v8 snapshot's blocker is null again: open, no blocker on the map.
d = plan_dir('P8_resolved', [approval, {'type': 'task_start', 'task': 'T-a'}, raised, resolved], snap(None))
state = json.load(open(os.path.join(d, 'state.json')))
assert fleet_report.classify(state)[0] == 'open' and fleet_report.plan_detail(state, d)['blocker'] is None
assert fleet_report.plan_started(d, state)

# 4. The stale rule reads the v8 snapshot's updated_at, as describe_plan copies it to state_updated_at.
old = snap(None, at='2026-11-10T08:00:00Z')
assert fleet_report.TS_RE.fullmatch(old['updated_at'])
row = {'plan': 'P8_still', 'class': 'open', 'lead': None, 'repo_root': '/r', 'situation': None,
       'tasks_done': 1, 'tasks_total': 2, 'current_task': None, 'detail': None, 'blocker_class': None,
       'state_updated_at': old['updated_at']}
p = fleet_ui.Plan('local', 'Mac', row)
now = fleet_ui.parse_ts('2026-11-12T12:00:00Z')
assert fleet_ui.stale_for(p, now) == 2 * 86400 + 4 * 3600 and fleet_ui.plan_facet(p, now) == 'attention'

# 5. The queue's view of a v8 plan: began (journal) while still queued -> in flight, never 'ready'.
base = os.path.join(root, 'v8repo')
os.makedirs(os.path.join(base, '.dwp', 'plans'), exist_ok=True)
import shutil
shutil.copytree(os.path.join(root, 'v8', 'P8_resolved'), os.path.join(base, '.dwp', 'plans', 'P8_resolved'))
shutil.copytree(os.path.join(root, 'v8', 'P8_only_blockers'), os.path.join(base, '.dwp', 'plans', 'P8_only_blockers'))
json.dump({'schema': 'dwp-queue-v1', 'items': [
    {'plan': 'P8_resolved', 'after': None, 'state': 'queued', 'lead': 'local:w1:p2', 'start': 'prompt-lead'},
    {'plan': 'P8_only_blockers', 'after': None, 'state': 'queued', 'lead': 'local:w1:p3', 'start': 'prompt-lead'}]},
    open(os.path.join(base, '.dwp', 'queue.json'), 'w'))
state_, q = fleet_report.read_queue(base)
items = dict((i['plan'], i) for i in q['items'])
assert items['P8_resolved']['blocked_reason'] == 'started, queue not updated' and not items['P8_resolved']['ready']
assert items['P8_only_blockers']['blocked_reason'] == 'another plan of this repository is running', items
print('ok')
PY
assert_eq "pack 8.0.0 records: the v8 journal's blocker events and the v8 snapshot's blocker read correctly" "ok" "$OUT"
export XDG_STATE_HOME=$LOOP_XDG_STATE
