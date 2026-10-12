# shellcheck shell=bash
# Drill round-two regressions: repository identity, pane context, plan-id mirror.
new_world round_two
P=PLAN_901_round_two
run "$HELPER" lead claim --plan "$P" --lanes local:w1:p2 --succession local:w2:p1
L=$("$HELPER" lead show --plan "$P" --json)
assert_eq "r2: outside git records an explicit null repository" '0 True null' "$RC $(python3 -c 'import json,sys; print("repo_root" in json.loads(sys.argv[1]))' "$L") $(jget "$L" repo_root)"
assert_contains "r2: lead notices carry the repository field" "$(last_prompt local w1:p2)" '"repo_root":null'
run "$HELPER" lead show --pane w1:p2 --plan "$P" --json
assert_eq "r2: show accepts a valid explicit pane without changing the record" "0 local:w1:p1" "$RC $(jget "$OUT" lead)"
run "$HELPER" lead show --pane w9:p9 --plan "$P" --json
assert_rc "r2: show refuses a stale explicit pane" 6
"$HELPER" lead release --plan "$P" >/dev/null 2>&1
run "$HELPER" lead claim --plan "$P"
L=$("$HELPER" lead show --plan "$P" --json)
assert_eq "r2: a released claim clears old lists and keeps the epoch monotonic" '0 3 [] []' "$RC $(jget "$L" epoch) $(jget "$L" lanes) $(jget "$L" succession)"
"$HELPER" lead release --plan "$P" >/dev/null 2>&1
run "$HELPER" lead claim --plan "$P" --lanes local:w1:p2 --succession local:w2:p1
L=$("$HELPER" lead show --plan "$P" --json)
assert_eq "r2: a released claim uses explicit new lists" '0 5 ["local:w1:p2"] ["local:w2:p1"]' "$RC $(jget "$L" epoch) $(jget "$L" lanes) $(jget "$L" succession)"

new_world round_two_repos
P=PLAN_901_round_two
mkdir -p "$WORK/repo-a/sub" "$WORK/repo-b"
git init -q "$WORK/repo-a" && git init -q "$WORK/repo-b" || exit 2
cd "$WORK/repo-a/sub" || exit 2
run "$HELPER" lead claim --plan "$P" --lanes local:w1:p2 --succession local:w2:p1
L=$("$HELPER" lead show --plan "$P" --json)
root_a=$(cd "$WORK/repo-a" && pwd -P)
assert_eq "r2: nested cwd records the git common root" "0 $root_a" "$RC $(jget "$L" repo_root)"
git -C "$WORK/repo-a" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm init || exit 2
git -C "$WORK/repo-a" worktree add -q "$WORK/linked" -b linked || exit 2
cd "$WORK/linked" || exit 2
run "$HELPER" lead claim --plan "$P"
L=$("$HELPER" lead show --plan "$P" --json)
assert_eq "r2: a linked worktree refresh uses the same common root" "0 1 $root_a" "$RC $(jget "$L" epoch) $(jget "$L" repo_root)"
mkdir -p "$WORK/linked/.dwp/plans/$P"
run env DWP_PLAN="$P" "$HELPER" notify local:w1:p2 'linked worktree mirror'
check "r2: a worktree plan id mirrors into its own checkout" grep -q '"state": "sent"' "$WORK/linked/.dwp/plans/$P/analysis_results/delegations.ndjson"
cd "$WORK/repo-b" || exit 2
run "$HELPER" lead claim --plan "$P"
assert_eq "r2: another repository cannot refresh an active record" '4' "$RC"
assert_contains "r2: collision refusal recommends a qualified plan id" "$ERR" '--plan <repo>/<id>'
run as_pane w1:p2 "$HELPER" notify --plan "$P" lead 'cross-repository milestone'
assert_eq "r2: another repository resolves and delivers to the lead" '0 yes' "$RC $(last_prompt local w1:p1 | python3 -c 'import sys; print("yes" if "cross-repository milestone" in sys.stdin.read() else "no")')"
run "$HELPER" lead claim --plan "repo-b/$P" --lanes local:w1:p2
L=$("$HELPER" lead show --plan "repo-b/$P" --json)
assert_eq "r2: qualified ids claim and show their own record" "0 repo-b/$P" "$RC $(jget "$L" plan)"
assert_contains "r2: qualified id notices carry that id" "$(last_prompt local w1:p2)" "repo-b/$P"
printf '%s\n' "$L" >"$WORK/qualified.json"
"$HELPER" lanes --plan "repo-b/$P" --json >"$WORK/qualified-lanes.json"
run bash -c 'python3 "$1/tests/tools/validate_records.py" --doc "$1/docs/schema/lead-v1.json" "$2/qualified.json" && python3 "$1/tests/tools/validate_records.py" --doc "$1/docs/schema/lanes-v1.json" "$2/qualified-lanes.json" && python3 "$1/tests/tools/validate_records.py" "$1/skills/herdr-peers/templates/delegation-record.json" "$3"' _ "$ROOT" "$WORK" "$(state_log)"
assert_rc "r2: qualified ids validate in every public record schema" 0

for bad in "../$P" "repo/../$P" "/$P" "repo//$P"; do
  run "$HELPER" lead claim --plan "$bad"
  assert_rc "r2: qualified ids refuse traversal or empty segments ($bad)" 2
done
# A successor operates from a different repository; identity belongs to the claim.
run "$HELPER" lead handover local:w2:p1 --plan "repo-b/$P"
L=$("$HELPER" lead show --plan "repo-b/$P" --json)
root_b=$(pwd -P)
assert_eq "r2: handover preserves the claiming root" "0 $root_b" "$RC $(jget "$L" repo_root)"
cd "$WORK/repo-a" || exit 2
run as_pane w2:p1 "$HELPER" lead release --plan "repo-b/$P"
L=$("$HELPER" lead show --plan "repo-b/$P" --json)
assert_eq "r2: cross-repository release preserves the claiming root" "0 $root_b" "$RC $(jget "$L" repo_root)"
run "$HELPER" lead claim --plan "repo-b/$P"
L=$("$HELPER" lead show --plan "repo-b/$P" --json)
assert_eq "r2: released record can be reclaimed from another repository" "0 4 $root_a [] []" "$RC $(jget "$L" epoch) $(jget "$L" repo_root) $(jget "$L" lanes) $(jget "$L" succession)"
# Record root survives an unplanned succession as well.
"$HELPER" lead claim --plan "$P" --succession local:w2:p1 >/dev/null 2>&1
python3 - "$FAKE_HERDR_DIR/local/agents.json" <<'PYTEST'
import json,sys
p=sys.argv[1]; a=json.load(open(p));json.dump([r for r in a if r['pane_id'] != 'w1:p1'],open(p,'w'))
PYTEST
cd "$WORK/repo-b" || exit 2
run as_pane w2:p1 "$HELPER" lead takeover --plan "$P"
L=$("$HELPER" lead show --plan "$P" --json)
assert_eq "r2: takeover preserves the claiming root across repositories" "0 $root_a" "$RC $(jget "$L" repo_root)"

new_world round_two_mirror
git init -q "$WORK" || exit 2
P=PLAN_901_round_two
mkdir -p "$WORK/.dwp/plans/$P" "$WORK/sub/dir"
cd "$WORK/sub/dir" || exit 2
run env DWP_PLAN="$P" "$HELPER" notify local:w1:p2 'plan id mirror'
mirror="$WORK/.dwp/plans/$P/analysis_results/delegations.ndjson"
assert_eq "r2: plan id mirrors from nested cwd without a warning" '0 ' "$RC $ERR"
check "r2: plan id mirror contains the actual notice record" grep -q '"state": "sent"' "$mirror"
assert_eq "r2: resolved plan mirror is private" '600' "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$mirror" 2>/dev/null)"
run env DWP_PLAN=PLAN_missing "$HELPER" notify local:w1:p2 'missing id'
assert_contains "r2: missing plan id retains the warning" "$RC $ERR" '0 herdr-peers: DWP_PLAN is set but is not a directory; the plan record was skipped'
# DWP_PLAN can default to a qualified id instead of silently dropping its prefix.
mkdir -p "$WORK/.dwp/plans/repo/$P"
run env DWP_PLAN="repo/$P" "$HELPER" lead claim --lanes ''
L=$("$HELPER" lead show --plan "repo/$P" --json)
assert_eq "r2: DWP_PLAN retains qualified ids for default plan selection" "0 repo/$P" "$RC $(jget "$L" plan)"

new_world round_two_legacy
P=PLAN_901_round_two
export WORLD_TAG=$RANDOM
lead_notice aa11:w1:p1 "$(nid)" 1 local:w1:p1 '' '' "$P" >"$WORK/legacy.txt"
run on_box env HERDR_PEERS_BRIEFER=aa11:w1:p1 "$HELPER" check --json "$WORK/legacy.txt"
assert_eq "r2: legacy notices without repo_root remain accepted" '3 adopted' "$RC $(jget "$OUT" lead_status)"
run on_box "$HELPER" lead claim --plan "$P"
L=$(on_box "$HELPER" lead show --plan "$P" --json)
assert_eq "r2: legacy holder refresh adds an explicit repository field" '0 True' "$RC $(python3 -c 'import json,sys; print("repo_root" in json.loads(sys.argv[1]))' "$L")"
# Incoming root is data: validate its shape before adopting, never execute it.
for invalid in '"relative/root"' '17' '"/bad\u001bpath"'; do
  lead_notice aa11:w1:p1 "$(nid)" 2 local:w1:p1 '' '' "$P" | python3 -c 'import json,sys
lines=sys.stdin.read().splitlines(); i=next(i for i,l in enumerate(lines) if l.startswith("swarm-lead:")); d=json.loads(lines[i].split(": ",1)[1]);d["repo_root"]=json.loads(sys.argv[1]);lines[i]="swarm-lead: "+json.dumps(d);print("\n".join(lines))' "$invalid" >"$WORK/invalid-root.txt"
  run on_box "$HELPER" check --json "$WORK/invalid-root.txt"
  assert_eq "r2: malformed repository root is rejected ($invalid)" '3 rejected malformed lead record: malformed repo_root' "$RC $(jget "$OUT" lead_status) $(jget "$OUT" lead_reason)"
done
new_world round_two_upgrade_notice
export WORLD_TAG=$RANDOM
P=PLAN_901_round_two
lead_notice aa11:w1:p1 "$(nid)" 1 aa11:w1:p1 '' '' "$P" >"$WORK/legacy.txt"
on_box env HERDR_PEERS_BRIEFER=aa11:w1:p1 "$HELPER" check "$WORK/legacy.txt" >/dev/null 2>&1
lead_notice aa11:w1:p1 "$(nid)" 1 aa11:w1:p1 '' '' "$P" | python3 -c 'import json,sys
lines=sys.stdin.read().splitlines(); i=next(i for i,l in enumerate(lines) if l.startswith("swarm-lead:")); d=json.loads(lines[i].split(": ",1)[1]);d["repo_root"]="/repository";lines[i]="swarm-lead: "+json.dumps(d);print("\n".join(lines))' >"$WORK/refresh.txt"
run on_box "$HELPER" check --json "$WORK/refresh.txt"
L=$(on_box "$HELPER" lead show --plan "$P" --json)
assert_eq "r2: a legacy receiver adopts the repository field on lead refresh" '3 adopted /repository' "$RC $(jget "$OUT" lead_status) $(jget "$L" repo_root)"
