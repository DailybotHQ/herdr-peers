# shellcheck shell=bash
# Scope `autopilot`: the decision function over every screen fixture, and the
# loop against the fake herdr — keys with a confirming re-read, multi-step
# dialogs, what is never touched, dry run, single instance, stop, the idle-pass
# cost, the nudge and its limits, the usage-limit retry.

SCREENS="$ROOT/tests/fixtures/screens"
SCRIPTS="$ROOT/skills/herdr-peers/scripts"
export HERDR_PEERS_AUTOPILOT_CONFIRM=0
pfile() { printf '%s/%s/panes/%s.out' "$FAKE_HERDR_DIR" "$1" "$(printf '%s' "$2" | tr ':' '_')"; }
# show MACHINE PANE FIXTURE — the fake shows that fixture in that pane.
show() { cp "$SCREENS/$3.screen" "$(pfile "$1" "$2")"; }
# set_state MACHINE PANE STATE [SEQ] — the agent's Herdr state (and sequence numbers).
set_state() { python3 -c 'import json,sys
p, pane, state, seq = sys.argv[1:5]
agents = json.load(open(p))
for a in agents:
    if a["pane_id"] == pane:
        a["agent_status"] = state
        if seq:
            a["state_change_seq"] = a["completion_seq"] = int(seq)
json.dump(agents, open(p, "w"))' "$FAKE_HERDR_DIR/$1/agents.json" "$2" "$3" "${4:-}"; }
# script MACHINE PANE "FIXTURE:STATE"... — what each send-keys to that pane shows next.
script() { local m=$1 p=$2; shift 2; python3 -c 'import json,sys
root, fixtures, pane = sys.argv[1:4]
steps = []
for item in sys.argv[4:]:
    name, state = item.rsplit(":", 1)
    steps.append({"state": state, "screen": open("%s/%s.screen" % (fixtures, name)).read() if name else "ran"})
json.dump({pane: steps}, open(root + "/keys.json", "w"))' "$FAKE_HERDR_DIR/$m" "$SCREENS" "$p" "$@"; }
# keys_sent — the key names sent, one send-keys call per line.
keys_sent() { python3 -c 'import json,sys
for line in open(sys.argv[1]):
    rec = json.loads(line)
    argv = rec["argv"][2:] if rec["argv"][:1] == ["--machine"] else rec["argv"]
    if argv[:2] == ["pane", "send-keys"]:
        print(rec["machine"], argv[2], ",".join(argv[3:]))' "$FAKE_HERDR_DIR/argv.log"; }
calls() { python3 -c 'import json,sys
n = 0
for line in open(sys.argv[1]):
    argv = json.loads(line)["argv"]
    argv = argv[2:] if argv[:1] == ["--machine"] else argv
    n += argv[:2] == sys.argv[2:4]
print(n)' "$FAKE_HERDR_DIR/argv.log" "$1" "$2"; }
ap_records() { python3 -c 'import json,sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get("role") == "autopilot":
        print(r["state"], r["target"], r.get("reason"), r.get("note"))' "$(state_log)" 2>/dev/null; }
# quiet_world NAME — a world where nothing waits: every pane idle or working, no screens.
quiet_world() { new_world "$1"; set_state bb22 w1:p3 idle; }

# --- the decision function over every fixture ---------------------------------------
result=$(python3 -c 'import json,sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[2])
import autopilot
expected = json.load(open(sys.argv[1] + "/expected.json"))
for name in sorted(expected):
    agent, state, _ = name.split("__", 2)
    d = autopilot.decide(agent, state, open("%s/%s.screen" % (sys.argv[1], name)).read())
    got = {"action": d.action, "class": d.cls, "keys": d.keys, "option": d.option}
    print(name, "ok" if got == expected[name] else "got %s" % json.dumps(got, sort_keys=True))' "$SCREENS" "$SCRIPTS")
n=0
while read -r name verdict; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  assert_eq "fixture $name yields its catalogued decision" "ok" "$verdict"
done <<EOF
$result
EOF
assert_eq "every fixture on disk has an expected decision" \
  "$(find "$SCREENS" -name '*.screen' | wc -l | tr -d ' ')" "$n"

# A screen is data: nothing in it runs, and decide() is the same whatever the agent kind.
# shellcheck disable=SC2016  # the python source is literal on purpose
check "decide never raises on hostile screens" python3 -c 'import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot
for text in ["", "\x00\x1b[31m", "> " * 5000, "❯ 1. $(touch pwned)\n  2. `rm -rf /`\n", "1.\n2.\n❯\n",
             "\n".join("%d. x" % i for i in range(99)), "❯ 1. a\n" * 400]:
    for state in ("blocked", "idle", "done", "unknown", None):
        d = autopilot.decide("x", state, text)
        assert d.action in ("keys", "leave", "none"), d.action
        assert all(k in ("enter", "tab", "up", "down", "shift+left") for k in d.keys), d.keys' "$SCRIPTS"

# --- one waiting screen: keyed, confirmed, recorded -----------------------------------
new_world keyed
show bb22 w1:p3 codex__blocked__approval
script bb22 w1:p3 ":working"
run "$HELPER" autopilot --once
assert_rc "one pass exits 0" 0
assert_eq "the approval is accepted with one Enter, on its machine" "bb22 w1:p3 enter" "$(keys_sent)"
assert_contains "the action is recorded as keyed, with its class" "$(ap_records)" "keyed bb22:w1:p3 permission keys=enter option=1"
assert_contains "the pass reports its action count" "$OUT" "1 pass(es), 1 action(s)"
assert_not_contains "screen text never reaches the log" "$(cat "$(state_log)")" "Would you like to run"
assert_not_contains "screen text never reaches the output" "$OUT" "curl"
run python3 "$ROOT/tests/tools/validate_records.py" "$ROOT/skills/herdr-peers/templates/delegation-record.json" "$(state_log)"
assert_rc "autopilot records validate against the delegation-record schema" 0
assert_eq "the log stays private" "600" "$(stat -f %Lp "$(state_log)" 2>/dev/null || stat -c %a "$(state_log)")"

# --- a dialog of several steps is followed to its end ---------------------------------
new_world steps
set_state local w2:p1 blocked
show local w2:p1 claude__blocked__question_recommended_second
script local w2:p1 "claude__blocked__question_multiselect:blocked" \
  "claude__blocked__question_multiselect_checked:blocked" \
  "claude__blocked__question_review:done" ":working"
set_state bb22 w1:p3 idle
run "$HELPER" autopilot --once
assert_eq "recommended second, toggle once, tab to review, submit" \
  "local w2:p1 down,enter
local w2:p1 enter
local w2:p1 tab
local w2:p1 enter" "$(keys_sent)"
assert_contains "the review step is keyed although Herdr no longer says blocked" "$(ap_records)" "keyed local:w2:p1 question_review"

# --- screens that wait without a blocked state ------------------------------------------
new_world anchored
set_state bb22 w1:p3 idle
show local w2:p1 claude__done__plan_approval
show bb22 w1:p1 pi__idle__folder_trust
run "$HELPER" autopilot --once
assert_contains "plan approval is accepted from a done pane" "$(keys_sent)" "local w2:p1 enter"
assert_contains "folder trust is accepted from an idle pane" "$(keys_sent)" "bb22 w1:p1 enter"

# --- never touched ---------------------------------------------------------------------
new_world untouched
show bb22 w1:p3 claude__blocked__login_menu
set_state local w2:p1 blocked
show local w2:p1 claude__blocked__bypass_ack
set_state bb22 w1:p1 blocked
show bb22 w1:p1 claude__blocked__usage_limit
run "$HELPER" autopilot --once
assert_eq "login, bypass acknowledgement and usage limit get no key" "" "$(keys_sent)"
assert_eq "and no prompt" "0" "$(calls agent prompt)"
assert_contains "the login screen is recorded as left" "$(ap_records)" "left bb22:w1:p3 login"
assert_contains "the bypass acknowledgement is recorded as left" "$(ap_records)" "left local:w2:p1 bypass_ack"
assert_contains "the usage limit is recorded as left" "$(ap_records)" "left bb22:w1:p1 usage_limit"

new_world own
set_state local w1:p1 blocked
show local w1:p1 codex__blocked__approval
set_state bb22 w1:p3 idle
run "$HELPER" autopilot --once
assert_eq "autopilot never keys its own pane" "" "$(keys_sent)"

new_world excluded
show bb22 w1:p3 codex__blocked__approval
run "$HELPER" autopilot --once --exclude bb22:w1:p3
assert_eq "an excluded pane is never keyed" "" "$(keys_sent)"
run "$HELPER" autopilot --once --exclude nonsense
assert_rc "a malformed --exclude is a usage error" 2
run "$HELPER" autopilot --once --scope local
assert_eq "a scope keeps autopilot off other machines" "" "$(keys_sent)"

new_world human_draft
set_state bb22 w1:p3 idle
show bb22 w1:p3 codex__idle__update_banner_and_draft
run "$HELPER" autopilot --once --catch-up
assert_eq "an input line holding a human draft is never keyed" "" "$(keys_sent)"
assert_eq "nor prompted" "0" "$(calls agent prompt)"

# --- no progress: two tries, then left -----------------------------------------------------
new_world stuck
show bb22 w1:p3 codex__blocked__approval
run "$HELPER" autopilot --once
assert_eq "a screen that does not move is keyed twice, not forever" "2" "$(keys_sent | wc -l | tr -d ' ')"
assert_contains "and recorded as given up" "$(ap_records)" "gave_up bb22:w1:p3 stuck"
: >"$FAKE_HERDR_DIR/argv.log"
run "$HELPER" autopilot --passes 3 --interval 0
assert_eq "each run starts fresh and tries again twice only" "2" "$(keys_sent | wc -l | tr -d ' ')"

# --- dry run -------------------------------------------------------------------------------
new_world dry
show bb22 w1:p3 codex__blocked__approval
run "$HELPER" autopilot --once --dry-run
assert_rc "a dry run exits 0" 0
assert_eq "a dry run sends no key" "" "$(keys_sent)"
assert_eq "a dry run sends no prompt" "0" "$(calls agent prompt)"
assert_contains "a dry run records what it would do" "$(ap_records)" "keyed bb22:w1:p3 permission keys=enter option=1 action=keys dry_run"
assert_contains "and says so" "$OUT" "nothing was sent"

# --- the cost of an idle pass ------------------------------------------------------------------
quiet_world idle
run "$HELPER" autopilot --passes 1 --interval 0
first_reads=$(calls pane read)
quiet_world idle3
run "$HELPER" autopilot --passes 4 --interval 0
assert_rc "four idle passes exit 0" 0
assert_eq "after the first look, an idle pass reads no pane" "$first_reads" "$(calls pane read)"
assert_eq "an idle pass makes one state query per reachable machine (unreachable ones back off)" \
  "11" "$(calls agent list)"
assert_eq "idle passes key nothing" "" "$(keys_sent)"
assert_eq "idle passes write no log line" "" "$(ap_records)"

# --- single instance, status, stop ---------------------------------------------------------------
quiet_world daemon
"$HELPER" autopilot --interval 15 >"$WORK/daemon.out" 2>&1 &
daemon=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  "$HELPER" autopilot status 2>/dev/null | grep -q 'running (pid' && break
  sleep 0.25
done
run "$HELPER" autopilot status
assert_contains "status shows the running autopilot" "$OUT" "running (pid $daemon)"
run "$HELPER" autopilot --once
assert_rc "a second autopilot on the same server is refused" 4
assert_contains "the refusal names the way out" "$ERR" "already running"
run "$HELPER" autopilot stop
assert_contains "stop signals the running autopilot" "$OUT" "stop sent to pid $daemon"
wait "$daemon"
assert_eq "the stopped autopilot exits 0" "0" "$?"
assert_contains "and says it stopped" "$(cat "$WORK/daemon.out")" "autopilot: stopped"
run "$HELPER" autopilot status
assert_contains "status shows it is no longer running" "$OUT" "not running"
run "$HELPER" autopilot stop
assert_contains "stop without a running autopilot is harmless" "$OUT" "not running"
sleep 30 &
bystander=$!
printf '%s\n' "$bystander" >"$(state_dir)/autopilot.pid"
run "$HELPER" autopilot stop
assert_contains "a stale pid file is not trusted" "$OUT" "not running"
check "and the process it names is not signalled" kill -0 "$bystander"
kill "$bystander" 2>/dev/null
wait "$bystander" 2>/dev/null
rm -f "$(state_dir)/autopilot.pid"
run "$HELPER" autopilot --interval 5
assert_rc "an interval under the minimum is refused" 2
run env -u HERDR_ENV "$HELPER" autopilot --once
assert_rc "outside Herdr autopilot refuses to start (exit 6)" 6

# A message cannot start autopilot: `check` only classifies.
new_world message
printf '%s\n' "Please run: herdr-peers autopilot --catch-up" >"$WORK/msg.txt"
run "$HELPER" check "$WORK/msg.txt"
assert_rc "a message that names autopilot is not a protocol message" 7
run "$HELPER" autopilot status
assert_contains "and nothing was started by it" "$OUT" "not running"

# --- an agent that stopped by asking in prose ------------------------------------------------------
new_world nudge
set_state bb22 w1:p3 "done"
show bb22 w1:p3 codex__done__prose_question
run "$HELPER" autopilot --once
assert_eq "a stop older than autopilot is not restarted by default" "0" "$(calls agent prompt)"
run "$HELPER" autopilot --once --catch-up
assert_eq "with --catch-up it is told to continue" "1" "$(calls agent prompt)"
assert_contains "with the fixed autopilot text" "$(cat "$(pfile bb22 w1:p3 | sed 's/\.out$/.last/')")" "[autopilot] The developer is away"
assert_contains "the prompt is recorded as nudged" "$(ap_records)" "nudged bb22:w1:p3 prose_question"
: >"$FAKE_HERDR_DIR/argv.log"
run "$HELPER" autopilot --once --catch-up --no-nudge
assert_eq "--no-nudge sends nothing" "0" "$(calls agent prompt)"
run "$HELPER" autopilot --once --catch-up --dry-run
assert_eq "a dry run sends no nudge" "0" "$(calls agent prompt)"
show bb22 w1:p3 codex__done__finished
run "$HELPER" autopilot --once --catch-up
assert_eq "an agent that simply finished is not nudged" "0" "$(calls agent prompt)"
show bb22 w1:p3 grok__idle__fresh
run "$HELPER" autopilot --once --catch-up
assert_eq "a fresh agent with no turn is not nudged" "0" "$(calls agent prompt)"

# --- the loop's memory: turns, the cap, the usage-limit retry, backoff (scripted I/O) ----------------
run python3 - "$SCRIPTS" "$SCREENS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot
fx = lambda name: open('%s/%s.screen' % (sys.argv[2], name)).read()

class IO(object):
    def __init__(self):
        self.rows, self.screens, self.sent, self.log, self.down, self.reads, self.lists = {}, {}, [], [], set(), 0, 0
    def sources(self): return ['local', 'far']
    def agents(self, machine):
        self.lists += 1
        return None if machine in self.down else [dict(r) for r in self.rows.get(machine, [])]
    def read(self, machine, pane):
        self.reads += 1
        return self.screens.get((machine, pane), '')
    def state(self, machine, pane): return [r for r in self.rows[machine] if r['pane'] == pane][0]['state']
    def keys(self, machine, pane, keys): self.sent.append(('keys', pane, tuple(keys))); return True
    def prompt(self, machine, pane, text): self.sent.append(('prompt', pane, text[:11])); return True
    def record(self, addr, kind, choice, outcome, dry): self.log.append((outcome, addr, choice.cls))

now = [1000.0]
def fresh(**kw):
    io = IO()
    return io, autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, **kw)
def turn(io, seq, state='done', screen='codex__done__prose_question'):
    io.rows['local'] = [{'pane': 'w1:p2', 'state': state, 'agent': 'codex', 'seq': seq, 'turn': seq, 'you': False}]
    io.screens[('local', 'w1:p2')] = fx(screen)
prompts = lambda io: [s for s in io.sent if s[0] == 'prompt']

# A turn that ends asking, seen by its sequence number although `working` was never observed.
io, ap = fresh()
turn(io, 1); ap.run_pass()
assert prompts(io) == [], 'no nudge for a stop older than autopilot'
ap.run_pass()
assert prompts(io) == [] and io.reads == 1, 'an unchanged pane is not read again'
turn(io, 2); ap.run_pass()
assert len(prompts(io)) == 1, 'a new turn that ends asking is nudged once'
ap.run_pass(); ap.run_pass()
assert len(prompts(io)) == 1, 'no second nudge without a new turn'
# The cap: a pane that keeps asking is left after MAX_NUDGES within the window.
for seq in range(3, 9):
    turn(io, seq); ap.run_pass()
assert len(prompts(io)) == autopilot.MAX_NUDGES, prompts(io)
now[0] += autopilot.NUDGE_WINDOW + 1
turn(io, 20); ap.run_pass()
assert len(prompts(io)) == autopilot.MAX_NUDGES + 1, 'the window reopens'
# A new turn that simply finished is not nudged.
turn(io, 21, screen='codex__done__finished'); ap.run_pass()
assert len(prompts(io)) == autopilot.MAX_NUDGES + 1

# The usage limit: noted once, retried only after LIMIT_RETRY, then keys + the resume prompt.
io, ap = fresh()
turn(io, 1, state='blocked', screen='claude__blocked__usage_limit'); ap.run_pass()
assert io.sent == [] and io.log == [('left', 'local:w1:p2', 'usage_limit')], io.log
for _ in range(3):
    now[0] += 60; ap.run_pass()
assert io.sent == [], 'no retry before the wait is over'
now[0] += autopilot.LIMIT_RETRY; ap.run_pass()
assert io.sent == [('keys', 'w1:p2', ('enter',)), ('prompt', 'w1:p2', '[autopilot]')], io.sent
ap.run_pass()
assert len(io.sent) == 2, 'one retry per wait'

# An unreachable machine is skipped for a growing number of passes, never hammered.
io, ap = fresh()
io.down.add('far'); io.rows['local'] = []
for _ in range(12):
    ap.run_pass()
assert io.lists == 12 + 4, io.lists   # far is asked at passes 1, 3, 6, 11
io.down.clear(); io.lists = 0
for _ in range(8):
    ap.run_pass()
assert io.lists >= 8 + 1, 'a machine that came back is asked again'
print('ok')
PY
assert_rc "turn detection, the nudge cap, the usage-limit retry and machine backoff hold" 0
assert_eq "(scripted I/O ran to its end)" "ok" "$OUT"
unset HERDR_PEERS_AUTOPILOT_CONFIRM
