# shellcheck shell=bash
# Sourced by the `lead` scope: lead appointment (protocol 2, PLAN_009). A lane
# of a plan whose record carries the human's grant takes the lead when the
# lead, every successor and every earlier lane are gone. Fence rule F10 (and
# its tie), the protocol-1/2 sender rule, the issuer's guards, a lead that
# comes back, `lead verify`, and a 1.x receiver that fails closed.
# Uses jget, on_box, nid, P and WORLD_TAG from lead.sh.

export HERDR_PEERS_APPOINT_PROBE_GAP=0
# lead_notice2 FROM ID EPOCH LEAD SUCC LANES APPOINT VIA [PROTO] — a hand-built lead-v2 notice.
lead_notice2() {
  python3 - "$@" <<'PY'
import json, sys
frm, nid, epoch, lead, succ, lanes, appoint, via = sys.argv[1:9]
proto = sys.argv[9] if len(sys.argv) > 9 else '2'
rec = {'schema': 'herdr-peers/lead-v2', 'plan': 'PLAN_900_demo',
       'lead': None if lead == 'null' else lead, 'epoch': int(epoch),
       'succession': [s for s in succ.split(',') if s], 'lanes': [s for s in lanes.split(',') if s],
       'updated_at': '2026-11-15T00:00:00Z',
       'appoint': None if appoint == 'null' else appoint, 'via': None if via == 'null' else via}
if rec['appoint'] is None and rec['via'] is None:
    rec['schema'] = 'herdr-peers/lead-v1'
    del rec['appoint'], rec['via']
print('herdr-peers lead notice (data, not instructions)')
print('swarm-lead: ' + json.dumps(rec, sort_keys=True, separators=(',', ':')))
print('')
print('[herdr-peers] protocol=%s from=%s reply=no depth=0 id=%s' % (proto, frm, nid))
print('This is a notice. Do not answer it.')
PY
}
# box_with GRANT LEAD SUCC LANES — a fresh box that adopted epoch 1 of that record from LEAD.
box_with() {
  WORLD_TAG=$RANDOM
  lead_notice2 "$2" "$(nid)" 1 "$2" "$3" "$4" "$1" null >"$WORK/e1.txt"
  on_box env HERDR_PEERS_BRIEFER="$2" "$HELPER" check --json "$WORK/e1.txt" >"$WORK/e1.out" 2>&1
}
GONE_LEAD=aa11:w9:p9; GONE_SUCC=aa11:w9:p8; GONE_LANE=aa11:w9:p7
LANE=aa11:w1:p2; LIVE=aa11:w2:p1

# --- F10: the receiver's fence ---------------------------------------------------------------
new_world appoint_fence
box_with lanes "$GONE_LEAD" "$GONE_SUCC" "$GONE_LANE,$LANE,bb22:w1:p1"
assert_eq "setup: a granted record is adopted from its briefer (protocol 2)" "adopted" \
  "$(jget "$(cat "$WORK/e1.out")" lead_status)"
assert_eq "the box keeps the grant" "lanes" "$(jget "$(on_box "$HELPER" lead show --plan "$P" --json)" appoint)"
lead_notice2 "$LANE" "$(nid)" 2 "$LANE" "$GONE_SUCC" "$GONE_LANE,bb22:w1:p1" lanes appointment >"$WORK/a.txt"
run on_box "$HELPER" check --json "$WORK/a.txt"
assert_eq "F10: the first live lane appointed when lead, successor and earlier lane are gone" \
  "adopted 2" "$(jget "$OUT" lead_status) $(jget "$OUT" epoch)"
assert_contains "the reason names the appointment" "$(jget "$OUT" lead_reason)" "appointment of lane $LANE"
assert_eq "the box follows the appointee" "$LANE" "$(jget "$(on_box "$HELPER" lead show --plan "$P" --json)" lead)"
# Tie: the earlier lane comes back and also appointed itself at epoch 2: it wins.
lead_notice2 "$GONE_LANE" "$(nid)" 2 "$GONE_LANE" "$GONE_SUCC" "$LANE,bb22:w1:p1" lanes appointment >"$WORK/tie.txt"
run on_box "$HELPER" check --json "$WORK/tie.txt"
assert_eq "a tie at the appointment epoch goes to the earlier lane" "adopted" "$(jget "$OUT" lead_status)"
lead_notice2 "$LANE" "$(nid)" 2 "$LANE" "$GONE_SUCC" "$GONE_LANE,bb22:w1:p1" lanes appointment >"$WORK/tie2.txt"
run on_box "$HELPER" check --json "$WORK/tie2.txt"
assert_eq "the later lane loses the tie" "rejected" "$(jget "$OUT" lead_status)"
lead_notice2 "$LANE" "$(nid)" 1 "$LANE" "$GONE_SUCC" "$GONE_LANE,bb22:w1:p1" lanes appointment >"$WORK/stale.txt"
run on_box "$HELPER" check --json "$WORK/stale.txt"
assert_eq "a replayed appointment at an old epoch is stale" "rejected" "$(jget "$OUT" lead_status)"

# Each condition false alone: rejected.
f10_case() { # NAME GRANT LEAD SUCC LANES   then the appointment notice: FROM EPOCH LEADNAME SUCC LANES APPOINT
  local name=$1; box_with "$2" "$3" "$4" "$5"; shift 5
  lead_notice2 "$1" "$(nid)" "$2" "$3" "$4" "$5" "$6" appointment >"$WORK/n.txt"
  run on_box "$HELPER" check --json "$WORK/n.txt"
  assert_eq "F10 refuses: $name" "rejected" "$(jget "$OUT" lead_status)"
}
f10_case "no grant in the stored record" null "$GONE_LEAD" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LANE" "$GONE_SUCC" "" lanes
assert_contains "and says so" "$(jget "$OUT" lead_reason)" "carries no grant"
f10_case "a sender that is not a lane (every lane gone)" lanes "$GONE_LEAD" "$GONE_SUCC" "$GONE_LANE" \
  "$LIVE" 2 "$LIVE" "$GONE_SUCC" "$GONE_LANE" lanes
assert_contains "and says it is not a lane" "$(jget "$OUT" lead_reason)" "is not a lane"
f10_case "an epoch jump" lanes "$GONE_LEAD" "$GONE_SUCC" "$LANE" \
  "$LANE" 3 "$LANE" "$GONE_SUCC" "" lanes
f10_case "a record that names someone else" lanes "$GONE_LEAD" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LIVE" "$GONE_SUCC" "" lanes
f10_case "widened lanes" lanes "$GONE_LEAD" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LANE" "$GONE_SUCC" "$LIVE" lanes
assert_contains "and says widened" "$(jget "$OUT" lead_reason)" "widened"
f10_case "a widened grant" lanes "$GONE_LEAD" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LANE" "$GONE_SUCC" "" lanes:any-kind
f10_case "a dropped successor" lanes "$GONE_LEAD" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LANE" "" "" lanes
f10_case "a reachable lead" lanes "$LIVE" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LANE" "$GONE_SUCC" "" lanes
assert_contains "and names it" "$(jget "$OUT" lead_reason)" "$LIVE is reachable"
f10_case "a reachable successor" lanes "$GONE_LEAD" "$LIVE" "$LANE" \
  "$LANE" 2 "$LANE" "$LIVE" "" lanes
f10_case "a reachable earlier lane" lanes "$GONE_LEAD" "$GONE_SUCC" "$LIVE,$LANE" \
  "$LANE" 2 "$LANE" "$GONE_SUCC" "$LIVE" lanes
# A lead idle with a limit line on screen is not proof for a receiver either.
new_world appoint_weak
python3 -c 'import json,sys; p=sys.argv[1]; a=json.load(open(p)); a[2]["agent_status"]="idle"; json.dump(a, open(p,"w"))' "$FAKE_HERDR_DIR/aa11/agents.json"
printf "You've hit your usage limit · resets 6pm\n" >"$FAKE_HERDR_DIR/aa11/panes/w2_p1.out"
f10_case "a lead idle with a limit banner (weak)" lanes "$LIVE" "$GONE_SUCC" "$LANE" \
  "$LANE" 2 "$LANE" "$GONE_SUCC" "" lanes
assert_contains "and says it is not proof" "$(jget "$OUT" lead_reason)" "not proof"

# --- one total order for two records at one epoch (review #1-#3) ---------------------------
# prior: lead GONE_LEAD, succession GONE_SUCC, lanes GONE_LANE, LANE. Takeover by
# the successor and appointment of a lane both claim epoch 2; the successor comes
# first wherever and in whatever order the notices arrive.
box_with lanes "$GONE_LEAD" "$GONE_SUCC" "$GONE_LANE,$LANE"
lead_notice2 "$LANE" "$(nid)" 2 "$LANE" "$GONE_SUCC" "$GONE_LANE" lanes appointment >"$WORK/ap.txt"
lead_notice2 "$GONE_SUCC" "$(nid)" 2 "$GONE_SUCC" "" "$GONE_LANE,$LANE" lanes null >"$WORK/tk.txt"
on_box "$HELPER" check --json "$WORK/ap.txt" >/dev/null 2>&1
run on_box "$HELPER" check --json "$WORK/tk.txt"
assert_eq "appointment first, then a successor's takeover at the same epoch: the successor wins" "adopted" "$(jget "$OUT" lead_status)"
box_with lanes "$GONE_LEAD" "$GONE_SUCC" "$GONE_LANE,$LANE"
on_box "$HELPER" check --json "$WORK/tk.txt" >/dev/null 2>&1
run on_box "$HELPER" check --json "$WORK/ap.txt"
assert_eq "takeover first, then the appointment: the appointment loses (same result, any order)" "rejected" "$(jget "$OUT" lead_status)"
assert_eq "both orders end with the successor" "$GONE_SUCC" "$(jget "$(on_box "$HELPER" lead show --plan "$P" --json)" lead)"
# A tie after the appointee refreshed: the previous record is kept, so the
# earlier lane still wins.
box_with lanes "$GONE_LEAD" "$GONE_SUCC" "$GONE_LANE,$LANE"
on_box "$HELPER" check --json "$WORK/ap.txt" >/dev/null 2>&1
lead_notice2 "$LANE" "$(nid)" 2 "$LANE" "$GONE_SUCC" "$GONE_LANE,bb22:w1:p1" lanes null >"$WORK/refresh.txt"
run on_box "$HELPER" check --json "$WORK/refresh.txt"
assert_eq "the appointee's refresh is adopted" "adopted" "$(jget "$OUT" lead_status)"
lead_notice2 "$GONE_LANE" "$(nid)" 2 "$GONE_LANE" "$GONE_SUCC" "$LANE" lanes appointment >"$WORK/early.txt"
run on_box "$HELPER" check --json "$WORK/early.txt"
assert_eq "a tie after a refresh still goes to the earlier lane" "adopted" "$(jget "$OUT" lead_status)"
# The tie runs the full step: no widening, and the receiver's own probes.
box_with lanes "$GONE_LEAD" "$GONE_SUCC" "$GONE_LANE,$LANE"
on_box "$HELPER" check --json "$WORK/ap.txt" >/dev/null 2>&1
lead_notice2 "$GONE_LANE" "$(nid)" 2 "$GONE_LANE" "$GONE_SUCC" "$LANE" lanes:any-kind appointment >"$WORK/wide.txt"
run on_box "$HELPER" check --json "$WORK/wide.txt"
assert_eq "a tie notice that widens the grant is refused" "rejected" "$(jget "$OUT" lead_status)"
lead_notice2 "$GONE_LANE" "$(nid)" 2 "$GONE_LANE" "$GONE_SUCC,$GONE_LANE" "$LANE" lanes appointment >"$WORK/wide2.txt"
run on_box "$HELPER" check --json "$WORK/wide2.txt"
assert_eq "a tie notice that adds to the succession is refused" "rejected" "$(jget "$OUT" lead_status)"
box_with lanes "$LIVE" "$GONE_SUCC" "$GONE_LANE,$LANE"
lead_notice2 "$LANE" "$(nid)" 2 "$LANE" "$GONE_SUCC" "$GONE_LANE" lanes appointment >"$WORK/ap2.txt"
lead_notice2 "$GONE_LANE" "$(nid)" 2 "$GONE_LANE" "$GONE_SUCC" "$LANE" lanes appointment >"$WORK/early2.txt"
run on_box "$HELPER" check --json "$WORK/early2.txt"
assert_eq "a tie notice is probed: with the lead alive it is refused" "rejected" "$(jget "$OUT" lead_status)"
# The grant is never widened by a handover or a takeover (review #5).
box_with lanes "$GONE_LEAD" "$GONE_SUCC" "$LANE"
lead_notice2 "$GONE_LEAD" "$(nid)" 2 "$LANE" "$GONE_SUCC" "" lanes:any-kind null >"$WORK/ho.txt"
run on_box "$HELPER" check --json "$WORK/ho.txt"
assert_eq "a handover that widens the grant is refused" "rejected" "$(jget "$OUT" lead_status)"
box_with null "$GONE_LEAD" "$GONE_SUCC" "$LANE"
lead_notice2 "$GONE_SUCC" "$(nid)" 2 "$GONE_SUCC" "" "$LANE" lanes null >"$WORK/tk2.txt"
run on_box "$HELPER" check --json "$WORK/tk2.txt"
assert_eq "a takeover that adds a grant is refused" "rejected" "$(jget "$OUT" lead_status)"
# A member on a machine that cannot be reached is not proof (review #4).
box_with lanes dd44:w1:p1 "$GONE_SUCC" "$LANE"
lead_notice2 "$LANE" "$(nid)" 2 "$LANE" "$GONE_SUCC" "" lanes appointment >"$WORK/part.txt"
run on_box "$HELPER" check --json "$WORK/part.txt"
assert_eq "a lead on an unreachable machine does not count as gone for an appointment" "rejected" "$(jget "$OUT" lead_status)"
assert_contains "and says so" "$(jget "$OUT" lead_reason)" "cannot be reached (not proof)"

# --- the wire: protocol 1 stays byte-compatible; protocol 2 only for granted records ----------
new_world appoint_wire
"$HELPER" lead claim --plan "$P" --lanes local:w1:p2 >/dev/null 2>&1
assert_contains "an ungranted plan's lead notice is protocol 1" "$(last_prompt local w1:p2)" \
  "[herdr-peers] protocol=1 from=local:w1:p1 reply=no"
assert_not_contains "and carries no lead-v2 keys" "$(last_prompt local w1:p2)" '"appoint"'
run "$HELPER" lead claim --plan "$P" --allow-appointment
assert_rc "the lead records the grant" 0
assert_contains "it warns that every member must run 2.0" "$ERR" "2.0 or later"
assert_contains "a granted plan's lead notice is protocol 2" "$(last_prompt local w1:p2)" \
  "[herdr-peers] protocol=2 from=local:w1:p1 reply=no"
assert_contains "and carries the grant on the wire" "$(last_prompt local w1:p2)" '"appoint":"lanes"'
assert_contains "lead-v2 on the wire" "$(last_prompt local w1:p2)" '"schema":"herdr-peers/lead-v2"'
store_file=$(ls "$(state_dir)"/leads/*.json)
assert_eq "the stored record stays lead-v1 for a same-server 1.x helper" "herdr-peers/lead-v1 lanes" \
  "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["record"]["schema"], d["appoint"])' "$store_file")"
run as_pane w1:p2 "$HELPER" check --json <(last_prompt local w1:p2)
assert_eq "a 2.x receiver records a protocol-2 notice" "notice" "$(jget "$OUT" decision)"
printf 'hi\n\n[herdr-peers] protocol=2 from=local:w1:p1 reply=yes depth=0 id=%s\nYou may answer this without asking a human. Reply exactly once with:\n  herdr-peers reply local:w1:p1 %s "<answer>"\n' "$(nid)" "$(nid)" >"$WORK/ask2.txt"
run as_pane w1:p2 "$HELPER" check --json "$WORK/ask2.txt"
assert_eq "protocol 2 never carries an ask (rule 5)" "5" "$(jget "$OUT" rule)"
OLD13="$ROOT/tests/compat/v1_3_0/herdr_peers.py"
last_prompt local w1:p2 >"$WORK/granted.txt"
run as_pane w1:p2 python3 "$OLD13" check --json "$WORK/granted.txt"
assert_eq "a frozen 1.3.0 receiver decides a protocol-2 notice never (rule 5)" "never 5" \
  "$(jget "$OUT" decision) $(jget "$OUT" rule)"
run "$HELPER" lead claim --plan "$P" --no-appointment
assert_contains "withdrawing the grant goes back to protocol 1" "$(last_prompt local w1:p2)" \
  "[herdr-peers] protocol=1 from=local:w1:p1 reply=no"

# --- the issuer: lead takeover --as-lane --------------------------------------------------------
gone_pane() { python3 -c 'import json,sys; p, pane = sys.argv[1:3]; a=[x for x in json.load(open(p)) if x["pane_id"]!=pane]; json.dump(a, open(p,"w"))' "$FAKE_HERDR_DIR/local/agents.json" "$1"; : >"$FAKE_HERDR_DIR/local/panes/$(printf '%s' "$1" | tr ':' '_').out"; }
new_world appoint_issuer
"$HELPER" lead claim --plan "$P" --succession local:w2:p1 --lanes local:w9:p7,local:w1:p2 >/dev/null 2>&1
run as_pane w1:p2 "$HELPER" lead takeover --plan "$P" --as-lane
assert_rc "no grant: a lane cannot be appointed (exit 4)" 4
assert_contains "the refusal names the missing grant" "$ERR" "no appointment grant"
"$HELPER" lead claim --plan "$P" --allow-appointment >/dev/null 2>&1
run as_pane w1:p2 "$HELPER" lead takeover --plan "$P" --as-lane
assert_rc "a reachable lead refuses the appointment (exit 4)" 4
gone_pane w1:p1
run as_pane w1:p2 "$HELPER" lead takeover --plan "$P" --as-lane
assert_rc "a reachable successor refuses the appointment (exit 4)" 4
assert_contains "and names it" "$ERR" "local:w2:p1"
gone_pane w2:p1
run as_pane w1:p2 "$HELPER" lead takeover --plan "$P" --as-lane --reason "they look gone"
assert_rc "--reason never stands in for evidence (exit 2)" 2
run "$HELPER" lead takeover --plan "$P" --as-lane
assert_rc "a pane that is not a lane cannot be appointed" 4
run as_pane w1:p2 "$HELPER" lead takeover --plan "$P" --as-lane
assert_rc "the first live lane is appointed when lead, successor and earlier lane are gone" 0
T=$("$HELPER" lead show --plan "$P" --json)
assert_eq "the appointee leads at epoch+1, marked as an appointment" "local:w1:p2 2 appointment lanes" \
  "$(jget "$T" lead) $(jget "$T" epoch) $(jget "$T" via) $(jget "$T" appoint)"
assert_eq "the succession is kept, the appointee leaves the lanes" '["local:w2:p1"] ["local:w9:p7"]' \
  "$(jget "$T" succession) $(jget "$T" lanes)"
assert_contains "the appointment is recorded" "$(grep '"appointed"' "$(state_log)")" "two probes"
run "$HELPER" lead show --plan "$P"
assert_contains "lead show counts the appointments" "$OUT" "appointment: granted (lanes); 1 of 2 used"
# The lead comes back on the same server: its lead verbs are refused, and its
# copy of the notice makes it step down.
run "$HELPER" lead release --plan "$P"
assert_rc "the returning lead cannot act (exit 4)" 4
run as_pane w1:p2 "$HELPER" lead claim --plan "$P"
assert_rc "the appointee refreshes its record" 0
T=$("$HELPER" lead show --plan "$P" --json)
assert_eq "a refresh drops the appointment mark and keeps the grant" "null lanes" "$(jget "$T" via) $(jget "$T" appoint)"
# The cap: a second appointment is allowed, a third is not.
python3 - "$(ls "$(state_dir)"/leads/*.json)" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d['appointments'] = 2; json.dump(d, open(p, 'w'))
PY
as_pane w1:p2 "$HELPER" lead claim --plan "$P" --lanes local:w1:p1 >/dev/null 2>&1
run "$HELPER" lead takeover --plan "$P" --as-lane
assert_rc "past two appointments only the human restarts the plan (exit 4)" 4
assert_contains "and says so" "$ERR" "2 appointments"

# --- lead verify: local state and read-only reports -------------------------------------------
mkrepo2() { mkdir -p "$1" && git -C "$1" init -q && git -C "$1" -c user.email=t@example.invalid \
  -c user.name=t commit -q --allow-empty -m init; }
box2_home() { printf '%s/ssh/box/home' "$FAKE_HERDR_DIR"; }
box2() { mkdir -p "$(box2_home)"; (cd "$REPO" && HOME="$(box2_home)" XDG_STATE_HOME="$(box2_home)/.local/state" \
  FAKE_HERDR_SERVER_ID="box-$WORLD_TAG" HERDR_PANE_ID=w1:p1 HERDR_WORKSPACE_ID=w1 "$HELPER" "$@" >/dev/null 2>&1); }
new_world appoint_verify
WORLD_TAG=$RANDOM
APPOINT_SAVED_XDG=${XDG_STATE_HOME:-}
export XDG_STATE_HOME="$WORLD/xdg-state"
REPO="$WORK/repo"; mkrepo2 "$REPO"
(cd "$REPO" && "$HELPER" lead claim --plan "$P" --lanes bb22:w1:p1 >/dev/null 2>&1)
# The lane on the other machine adopts the lead's notice, as it would live.
last_prompt bb22 w1:p1 >"$WORK/to-box.txt"
mkdir -p "$(box2_home)"; (cd "$REPO" && HOME="$(box2_home)" XDG_STATE_HOME="$(box2_home)/.local/state" \
  FAKE_HERDR_SERVER_ID="box-$WORLD_TAG" HERDR_PANE_ID=w1:p1 HERDR_WORKSPACE_ID=w1 \
  HERDR_PEERS_BRIEFER="$(grep -o 'from=[^ ]*' "$WORK/to-box.txt" | head -1 | cut -d= -f2)" \
  "$HELPER" check "$WORK/to-box.txt" >/dev/null 2>&1)
run sh -c "cd '$REPO' && '$HELPER' lead verify --plan '$P'"
assert_rc "verify: the lead, and the other machine agrees" 0
assert_contains "verify says so" "$OUT" "verified: local:w1:p1 leads $P at epoch 1"
assert_contains "verify is recorded" "$(grep '"verified"' "$(state_log)")" "1 machine(s) agree"
# Two independent claims of one plan at the same epoch cannot be ordered: refused.
Q2=PLAN_902_split
(cd "$REPO" && "$HELPER" lead claim --plan "$Q2" --lanes bb22:w1:p1 >/dev/null 2>&1)
box2 lead claim --plan "$Q2"
run sh -c "cd '$REPO' && '$HELPER' lead verify --plan '$Q2'"
assert_rc "two leads at one epoch that the order cannot rank: verify refuses (review #1)" 4
assert_contains "and names the other lead" "$ERR" "epoch 1 too"
Q3=PLAN_903_ahead
(cd "$REPO" && "$HELPER" lead claim --plan "$Q3" --lanes bb22:w1:p1 >/dev/null 2>&1)
box2 lead claim --plan "$Q3"; box2 lead release --plan "$Q3"; box2 lead claim --plan "$Q3"
run sh -c "cd '$REPO' && '$HELPER' lead verify --plan '$Q3'"
assert_rc "verify refuses when another machine shows a higher epoch (exit 4)" 4
assert_contains "and names it" "$ERR" "bb22 (epoch 3"
echo down >"$FAKE_HERDR_DIR/ssh/box/mode"
run sh -c "cd '$REPO' && '$HELPER' lead verify --plan '$P'"
assert_rc "an unreachable machine is not verified: exit 5 (review #6)" 5
assert_contains "and named" "$ERR" "not reached: bb22"
run sh -c "cd '$REPO' && '$HELPER' lead verify --plan '$P' --allow-unreached"
assert_rc "--allow-unreached accepts that risk, recorded" 0
run sh -c "cd '$REPO' && HERDR_PANE_ID=w1:p2 '$HELPER' lead verify --plan '$P'"
assert_rc "a pane that is not the lead is refused (exit 4)" 4
if grep -q '"push"\|"update-ref"\|"notes"' "$FAKE_HERDR_DIR/ssh.log" 2>/dev/null; then
  t_fail "verify writes nothing remotely"; else t_ok "verify writes nothing remotely"; fi
export XDG_STATE_HOME="$APPOINT_SAVED_XDG"

# The one total order, as a unit (used by the fence and by lead verify).
out=$(python3 - "$ROOT/skills/herdr-peers/scripts" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr_peers as h
prev = {'lead': 'L', 'succession': ['S1', 'S2'], 'lanes': ['A', 'B']}
keys = [h.order_key(a, prev) for a in ('L', 'S1', 'S2', 'A', 'B')]
print(keys == sorted(keys), h.order_key('X', prev), h.widens_grant({'appoint': 'lanes'}, {'appoint': 'lanes:any-kind'}),
      h.widens_grant({'appoint': 'lanes'}, {'appoint': None}))
PY
)
assert_eq "lead, then successors, then lanes, in list order; strangers unordered; only removal of a grant is not widening" "True None True False" "$out"

