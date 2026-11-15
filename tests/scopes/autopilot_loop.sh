# shellcheck shell=bash
# Part of scope `autopilot` (sourced by autopilot.sh): the plan loop — the
# machine report (`herdr-peers plans`, plans-v1) and what `autopilot --loop`
# does with it.

PLANS_SCHEMA="$ROOT/docs/schema/plans-v1.json"
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
new_world plans
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
new_world worktree
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
new_world plans_unknown
mkdir -p "$XDG_STATE_HOME/herdr-peers"
chmod 000 "$XDG_STATE_HOME/herdr-peers"
run env -u HERDR_ENV "$HELPER" plans --json
chmod 700 "$XDG_STATE_HOME/herdr-peers"
if [ "$(id -u)" = 0 ]; then t_skip "unreadable state root (running as root)"; else
  assert_contains "an unreadable state root reports unknown" "$OUT" '"state": "unknown"'
  assert_rc "and exits non-zero" 1
fi
