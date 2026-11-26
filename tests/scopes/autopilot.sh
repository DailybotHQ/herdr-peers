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
assert_eq "the log stays private" "600" "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$(state_log)")"

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
assert_contains "plan approval is accepted from a done pane, without switching to auto mode" "$(keys_sent)" "local w2:p1 down,enter"
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

# --- background mode: start, status, stop -------------------------------------------------------
fmode() { python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$1" 2>/dev/null; }
alive() { kill -0 "$1" 2>/dev/null; }
quiet_world background
SD=$(state_dir)
mkdir -p "$SD"
head -c 1100000 /dev/zero | tr '\0' 'x' >"$SD/autopilot.out"
# The parent shell exits as soon as start returns; the daemon must outlive it.
run sh -c "'$HELPER' autopilot start --interval 15 --no-nudge --exclude bb22:w1:p3"
assert_rc "autopilot start exits 0" 0
assert_contains "start says it runs in the background" "$OUT" "started in the background (pid"
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
assert_contains "start prints the options" "$OUT" "options: --interval 15 --no-nudge --exclude bb22:w1:p3"
assert_contains "start prints the log path" "$OUT" "log: $SD/autopilot.out"
check "the daemon outlives the shell that started it" alive "$bg"
assert_eq "the daemon leads its own session (no tie to the pane's tty)" "$bg" \
  "$(ps -o pgid= -p "$bg" 2>/dev/null | tr -d ' ')"
run "$HELPER" autopilot status
assert_contains "status shows it running" "$OUT" "running (pid $bg)"
assert_contains "status shows background mode and the starting pane" "$OUT" "mode: background, since "
assert_contains "status names the starting pane" "$OUT" "started from pane local:w1:p1"
assert_contains "status shows its options" "$OUT" "options: --interval 15 --no-nudge --exclude bb22:w1:p3"
assert_contains "status shows the log path" "$OUT" "log: $SD/autopilot.out"
run as_pane w2:p1 "$HELPER" autopilot status
assert_contains "status works from any pane" "$OUT" "running (pid $bg)"
assert_eq "the log is private" "0o600" "$(fmode "$SD/autopilot.out")"
assert_eq "the options file is private" "0o600" "$(fmode "$SD/autopilot.json")"
check "an oversized log was rotated to autopilot.out.1" test -s "$SD/autopilot.out.1"
check "and the fresh log is small" test "$(wc -c <"$SD/autopilot.out")" -lt 100000
for _ in $(seq 1 40); do [ "$(calls agent list)" -ge 2 ] && break; sleep 0.25; done
assert_eq "only start (parent and daemon) asks which pane this is; the loop never does" \
  "2" "$(calls pane current)"
run "$HELPER" autopilot start --interval 15
assert_rc "a second start is refused (exit 4)" 4
assert_contains "the refusal names the way out" "$ERR" "autopilot stop"
run "$HELPER" autopilot on
assert_rc "on is start, and is refused too" 4
run "$HELPER" autopilot --once
assert_rc "a foreground run is refused while the daemon runs" 4
run "$HELPER" autopilot stop
assert_rc "stop exits 0" 0
assert_contains "stop signals the daemon" "$OUT" "stop sent to pid $bg"
assert_contains "stop waits and reports it stopped" "$OUT" "stopped (pid $bg)"
check "the daemon is gone" sh -c "! kill -0 $bg 2>/dev/null"
check "its options file is removed" test ! -e "$SD/autopilot.json"
assert_contains "the log says it stopped" "$(cat "$SD/autopilot.out")" "autopilot: stopped"
run "$HELPER" autopilot status
assert_contains "status says not running, with the way to start" "$OUT" "not running (start it with"
run "$HELPER" autopilot on --interval 15
assert_rc "on starts it" 0
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
run "$HELPER" autopilot off
assert_contains "off stops it" "$OUT" "stopped (pid $bg)"
# stop reports only what it saw: an autopilot that will not exit is not "stopped".
python3 - "$SD" <<'PY' &
import fcntl, os, signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
fd = os.open(os.path.join(sys.argv[1], "autopilot.lock"), os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(os.path.join(sys.argv[1], "autopilot.pid"), "w").write("%d\n" % os.getpid())
time.sleep(30)
PY
stubborn=$!
BG_PIDS="${BG_PIDS:-} $stubborn"
for _ in $(seq 1 20); do [ -s "$SD/autopilot.pid" ] && break; sleep 0.1; done
run "$HELPER" autopilot stop
assert_rc "an autopilot that does not exit makes stop time out (exit 5)" 5
assert_not_contains "and stop never claims it stopped" "$OUT" "stopped (pid"
kill -9 "$stubborn" 2>/dev/null
wait "$stubborn" 2>/dev/null
rm -f "$SD/autopilot.pid"
run "$HELPER" autopilot start --once
assert_rc "start takes no --once (exit 2)" 2
run "$HELPER" autopilot start --interval 5
assert_rc "start keeps the interval minimum (exit 2)" 2
run env -u HERDR_ENV "$HELPER" autopilot start
assert_rc "outside Herdr start refuses (exit 6)" 6

# A daemon that dies at once: start fails and shows the log tail.
mkdir "$SD/autopilot.pid"
run "$HELPER" autopilot start --interval 15
assert_rc "a daemon that dies at once makes start fail (exit 1)" 1
assert_contains "start says it did not start" "$ERR" "did not start"
assert_contains "and shows the log tail with the daemon's error" "$ERR" "cannot write"
rmdir "$SD/autopilot.pid"
run "$HELPER" autopilot status
assert_contains "nothing is left running" "$OUT" "not running"

# The log is never opened through a symlink.
mv "$SD/autopilot.out" "$SD/autopilot.out.real"
ln -s "$WORK/elsewhere.txt" "$SD/autopilot.out"
run "$HELPER" autopilot start --interval 15
assert_rc "a symlinked log is refused (exit 4)" 4
check "and nothing was written through it" test ! -e "$WORK/elsewhere.txt"
rm -f "$SD/autopilot.out"
run "$HELPER" autopilot status
assert_contains "and nothing started" "$OUT" "not running"

# Resume: `start --resume` records the human's start; after the daemon is killed
# (a reboot, a Herdr restart) `autopilot resume` starts it again with the same
# options, and `stop` or a plain start forgets the record.
quiet_world resume
SD=$(state_dir)
mkdir -p "$SD"
run "$HELPER" autopilot resume
assert_rc "resume with no record exits 0" 0
assert_contains "and says there is nothing to resume" "$OUT" "nothing to resume"
run "$HELPER" autopilot status
assert_contains "and starts nothing" "$OUT" "not running"
run "$HELPER" autopilot --once --resume
assert_rc "--resume is refused on a foreground run (exit 2)" 2
run "$HELPER" autopilot resume --interval 15
assert_rc "resume takes no options (exit 2)" 2
run env HERDR_PEERS_AUTOPILOT_GRACE=120 "$HELPER" autopilot start --interval 15 --no-nudge --resume
assert_rc "start --resume exits 0" 0
assert_contains "start says resume is on" "$OUT" "resume: on"
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
assert_eq "the resume record is private" "0o600" "$(fmode "$SD/autopilot-resume.json")"
assert_contains "the record keeps the helper settings of the start" \
  "$(cat "$SD/autopilot-resume.json")" '"HERDR_PEERS_AUTOPILOT_GRACE": "120"'
run "$HELPER" autopilot status
assert_contains "status shows resume on while it runs" "$OUT" "resume: on"
run "$HELPER" autopilot resume
assert_rc "resume beside a running daemon exits 0" 0
assert_contains "and says it is already running" "$OUT" "already running"
before=$(cat "$SD/autopilot-resume.json")
run "$HELPER" autopilot start --interval 30 --resume
assert_rc "a start --resume beside a running daemon is refused (exit 4)" 4
assert_eq "and leaves the record as it was" "$before" "$(cat "$SD/autopilot-resume.json")"
kill -9 "$bg" 2>/dev/null
for _ in $(seq 1 40); do kill -0 "$bg" 2>/dev/null || break; sleep 0.1; done
run "$HELPER" autopilot status
assert_contains "a killed daemon is not running" "$OUT" "not running"
assert_contains "and status names the way back with its options" "$OUT" \
  "autopilot resume\` starts it again with: --interval 15 --no-nudge"
run env HERDR_PEERS_DEPTH=1 "$HELPER" autopilot resume
assert_rc "resume from a delegate's pane exits 0" 0
assert_contains "and starts nothing there" "$OUT" "not resumed from a delegate"
run "$HELPER" autopilot status
assert_contains "the daemon is still not running" "$OUT" "not running"
# Every pane's shell may run resume at once: one daemon, every caller exits 0.
for n in 1 2 3 4; do
  ( as_pane w2:p1 env HERDR_PEERS_AUTOPILOT_CONFIRM=never "$HELPER" autopilot resume \
      >"$WORK/resume.$n.out" 2>&1; echo $? >"$WORK/resume.$n.rc" ) &
done
wait
assert_eq "four resumes at once all exit 0" "0 0 0 0" "$(cat "$WORK"/resume.[1-4].rc | tr '\n' ' ' | sed 's/ $//')"
# The pane that resumes has other helper settings (here an invalid one): the
# daemon gets those of the start.
OUT=$(cat "$WORK"/resume.[1-4].out)
assert_eq "and exactly one of them started the daemon" "1" \
  "$(printf '%s\n' "$OUT" | grep -c 'started in the background (pid')"
assert_contains "resume says what it resumes" "$OUT" "resuming what was started with --resume"
assert_contains "and it runs in the background" "$OUT" "started in the background (pid"
bg2=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg2"
assert_contains "the log says it was a resume" "$(cat "$SD/autopilot.out")" "autopilot resume requested"
run "$HELPER" autopilot status
assert_contains "with the same options" "$OUT" "options: --interval 15 --no-nudge"
assert_contains "from the pane that resumed it" "$OUT" "started from pane local:w2:p1"
assert_contains "and resume stays on" "$OUT" "resume: on"
assert_eq "a resume leaves the human's record untouched" "$before" "$(cat "$SD/autopilot-resume.json")"
run "$HELPER" autopilot stop
assert_contains "stop turns resume off" "$OUT" "resume turned off"
assert_contains "and stops the daemon" "$OUT" "stopped (pid $bg2)"
check "the record is gone" test ! -e "$SD/autopilot-resume.json"
run "$HELPER" autopilot resume
assert_contains "after a stop there is nothing to resume" "$OUT" "nothing to resume"
run "$HELPER" autopilot status
assert_contains "and nothing runs" "$OUT" "not running"
# A stop that lands while a resume holds its lock waits for it, so what the
# resume starts is what gets stopped; a resume beside it does nothing.
python3 - "$SD" <<'PY' &
import fcntl, os, sys, time
fd = os.open(os.path.join(sys.argv[1], "autopilot-resume.lock"), os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)
open(os.path.join(sys.argv[1], "resume-lock.held"), "w").close()
time.sleep(2)
PY
holder=$!
BG_PIDS="${BG_PIDS:-} $holder"
for _ in $(seq 1 40); do [ -e "$SD/resume-lock.held" ] && break; sleep 0.1; done
t0=$(date +%s)
run "$HELPER" autopilot stop
assert_rc "stop beside a resume under way exits 0 once it is over" 0
check "and it waited for the resume's lock" test $(( $(date +%s) - t0 )) -ge 1
wait "$holder" 2>/dev/null
rm -f "$SD/resume-lock.held"
# A plain start is the last word too: it forgets an earlier record.
run "$HELPER" autopilot start --interval 15 --resume
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
kill -9 "$bg" 2>/dev/null
for _ in $(seq 1 40); do kill -0 "$bg" 2>/dev/null || break; sleep 0.1; done
run "$HELPER" autopilot start --interval 15
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
assert_contains "a start without --resume says the record is forgotten" "$OUT" "resume: off"
check "and removes it" test ! -e "$SD/autopilot-resume.json"
run "$HELPER" autopilot stop
assert_not_contains "a stop with no record does not mention resume" "$OUT" "resume"
# A record nobody's `start --resume` wrote is never used: other content, a
# symlink, or a file another user could write.
printf '{"schema":"herdr-peers/autopilot-resume-v1","since":"x","env":{},"options":{"notify":"touch %s"}}\n' \
  "$WORK/resumed.txt" >"$SD/autopilot-resume.json"
run "$HELPER" autopilot resume
assert_rc "a record of another shape is refused (exit 4)" 4
check "and its command never ran" test ! -e "$WORK/resumed.txt"
# A well-formed record is refused for one option-shaped value, a delegate's
# mark or a token name among its settings, or too many bytes.
bad_record() {
  python3 - "$SD/autopilot-resume.json" "$1" <<'PY'
import json, os, sys
opts = {"interval": 15, "dry_run": False, "no_nudge": False, "catch_up": False, "exclude": [],
        "scope": None, "loop": False, "notify": None, "notify_env": [], "appoint": False,
        "revive": False, "brain": False, "brain_kinds": None, "brain_model": []}
rec = {"schema": "herdr-peers/autopilot-resume-v1", "since": "2026-01-01T00:00:00Z",
       "options": opts, "env": {}}
kind = sys.argv[2]
if kind == "option":
    opts["scope"] = "--revive"
elif kind == "list":
    opts["exclude"] = ["--brain"]
elif kind == "depth":
    rec["env"] = {"HERDR_PEERS_DEPTH": "0"}
elif kind == "token":
    rec["env"] = {"HERDR_PEERS_FAKE_TOKEN": "fake"}
elif kind == "foreign":
    rec["env"] = {"PATH": "/tmp"}
elif kind == "big":
    rec["pad"] = "x" * 70000
elif kind == "bool":
    opts["interval"] = True
if os.path.lexists(sys.argv[1]):
    os.unlink(sys.argv[1])
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
os.write(fd, json.dumps(rec).encode())
os.close(fd)
PY
}
for kind in option list depth token foreign big bool; do
  bad_record "$kind"
  run "$HELPER" autopilot resume
  assert_rc "a record with a bad $kind is refused (exit 4)" 4
done
bad_record good
run "$HELPER" autopilot status
assert_contains "the same record without the bad part is accepted" "$OUT" "resume: on since 2026-01-01T00:00:00Z"
ln "$SD/autopilot-resume.json" "$WORK/resume-hardlink.json"
run "$HELPER" autopilot resume
assert_rc "a record with a second hard link is refused (exit 4)" 4
rm -f "$WORK/resume-hardlink.json"
run env HERDR_PEERS_FAKE_TOKEN=fake HERDR_PEERS_DEPTH=0 "$HELPER" autopilot start --interval 15 --resume
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
assert_not_contains "a token-named setting is never recorded" "$(cat "$SD/autopilot-resume.json")" "TOKEN"
assert_not_contains "nor the delegate mark" "$(cat "$SD/autopilot-resume.json")" "HERDR_PEERS_DEPTH"
run "$HELPER" autopilot stop
long=$(head -c 1500 /dev/zero | tr '\0' 'y')
run env HERDR_PEERS_AUTOPILOT_NOTE="$long" "$HELPER" autopilot start --interval 15 --resume
assert_rc "a start whose settings cannot be recorded says so (exit 2)" 2
assert_contains "and that resume stays off" "$ERR" "resume stays off"
check "with no record written" test ! -e "$SD/autopilot-resume.json"
run "$HELPER" autopilot stop
mkdir "$SD/autopilot-resume.json"
run "$HELPER" autopilot stop
assert_rc "a record that cannot be removed makes stop fail (exit 4)" 4
assert_contains "and stop says to remove it by hand" "$ERR" "remove it by hand"
rmdir "$SD/autopilot-resume.json"
printf '{"schema":"herdr-peers/autopilot-resume-v1","since":"x","env":{},"options":{"notify":"touch %s"}}\n' \
  "$WORK/resumed.txt" >"$SD/autopilot-resume.json"
run "$HELPER" autopilot status
assert_contains "status says the record is ignored" "$OUT" "it is ignored"
assert_contains "and nothing started" "$OUT" "not running"
"$HELPER" autopilot start --interval 15 --resume >/dev/null 2>&1
"$HELPER" autopilot status | sed -n 's/.*running (pid \([0-9]*\)).*/\1/p' >"$WORK/resume.pid"
bg=$(cat "$WORK/resume.pid")
BG_PIDS="${BG_PIDS:-} $bg"
kill -9 "$bg" 2>/dev/null
for _ in $(seq 1 40); do kill -0 "$bg" 2>/dev/null || break; sleep 0.1; done
chmod 0666 "$SD/autopilot-resume.json"
run "$HELPER" autopilot resume
assert_rc "a record others can write is refused (exit 4)" 4
chmod 0600 "$SD/autopilot-resume.json"
mv "$SD/autopilot-resume.json" "$WORK/resume-real.json"
ln -s "$WORK/resume-real.json" "$SD/autopilot-resume.json"
run "$HELPER" autopilot resume
assert_rc "a symlinked record is refused (exit 4)" 4
run "$HELPER" autopilot status
assert_contains "and nothing was started from it" "$OUT" "not running"
run "$HELPER" autopilot stop
check "stop removes the link, not its target" sh -c "test ! -e '$SD/autopilot-resume.json' && test -s '$WORK/resume-real.json'"

# A daemon whose starting pane closed: a new pane with the reused id is not its own.
own=$(python3 - "$SCRIPTS" <<'PY'
import json, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr_peers as hp
rows = [{"pane_id": "w1:p1", "terminal_id": "term_reused", "agent_status": "blocked"},
        {"pane_id": "w1:p2", "terminal_id": "term_local_p2", "agent_status": "idle"}]
hp.herdr = lambda argv, machine=None, timeout=30: (0, json.dumps({"result": {"agents": rows}}), "")
io = hp.AutopilotIO(None, "w1:p1", "term_local_p1", None, quiet=True)
first = [r["you"] for r in io.agents("local")]
rows[0]["terminal_id"] = "term_local_p1"
print(first, [r["you"] for r in io.agents("local")])
PY
)
assert_eq "own pane is matched by pane id and terminal" "[False, False] [True, False]" "$own"

# A background daemon has no pane: the pane it was started from is watched like
# any other agent pane (a lead that started it answers its own questions too).
quiet_world bgself
set_state local w1:p1 blocked
show local w1:p1 claude__blocked__question_tabs_recommended_es
run "$HELPER" autopilot start --interval 15
bg=$(printf '%s\n' "$OUT" | sed -n 's/.*background (pid \([0-9]*\)).*/\1/p')
BG_PIDS="${BG_PIDS:-} $bg"
for _ in $(seq 1 60); do keys_sent | grep -q 'local w1:p1' && break; sleep 0.25; done
assert_contains "the background daemon keys the pane it was started from" "$(keys_sent)" "local w1:p1 enter"
run "$HELPER" autopilot stop
assert_contains "and stops" "$OUT" "stopped (pid $bg)"
quiet_world fgself
set_state local w1:p1 blocked
show local w1:p1 claude__blocked__question_tabs_recommended_es
run "$HELPER" autopilot --once
assert_not_contains "a foreground autopilot never keys its own pane" "$(keys_sent)" "local w1:p1"

# --- logs: the background log, read-only, from any pane ----------------------------------------
quiet_world logs
SD=$(state_dir)
mkdir -p "$SD"
run as_pane w2:p1 "$HELPER" autopilot logs
assert_rc "logs without a log exits 0" 0
assert_contains "logs says the daemon is not running" "$ERR" "autopilot: not running"
assert_contains "and that there is no log yet" "$ERR" "no log yet"
for i in $(seq 1 60); do echo "line $i"; done >"$SD/autopilot.out"
printf 'evil \033]0;owned\007 title\n' >>"$SD/autopilot.out"
run "$HELPER" autopilot logs
assert_contains "logs prints the last 50 lines by default" "$OUT" "line 12"
assert_not_contains "and not the 51st from the end" "$OUT" "line 11"
assert_contains "logs still shows the log when nothing runs" "$ERR" "not running"
assert_not_contains "a hostile line reaches the terminal without its escapes" "$OUT" $'\033'
assert_contains "it is shown through safe()" "$OUT" "evil ?]0;owned? title"
run "$HELPER" autopilot logs --lines 3
assert_eq "--lines N prints the last N" "line 59
line 60
evil ?]0;owned? title" "$OUT"
run "$HELPER" autopilot logs --lines -1
assert_rc "a negative --lines is a usage error" 2
run "$HELPER" autopilot --once --follow
assert_rc "--follow outside logs is a usage error" 2
# --lines 1 prints the current last line first: once it is out, the follower
# holds the file at its end and every later line is new (no start-up race).
"$HELPER" autopilot logs -f --lines 1 >"$WORK/follow.out" 2>"$WORK/follow.err" &
fp=$!
for _ in $(seq 1 80); do [ -s "$WORK/follow.out" ] && break; sleep 0.25; done
printf 'appended \033[31mred\n' >>"$SD/autopilot.out"
for _ in $(seq 1 40); do grep -q appended "$WORK/follow.out" && break; sleep 0.25; done
assert_contains "follow prints an appended line" "$(cat "$WORK/follow.out")" "appended ?[31mred"
mv "$SD/autopilot.out" "$SD/autopilot.out.1"
printf 'after rotation\n' >"$SD/autopilot.out"
for _ in $(seq 1 40); do grep -q 'after rotation' "$WORK/follow.out" && break; sleep 0.25; done
assert_contains "follow survives a rotation" "$(cat "$WORK/follow.out")" "after rotation"
: >"$SD/autopilot.out"
sleep 0.6  # a truncation is seen when the file shrinks between two looks
printf 'after truncation\n' >>"$SD/autopilot.out"
for _ in $(seq 1 40); do grep -q 'after truncation' "$WORK/follow.out" && break; sleep 0.25; done
assert_contains "follow survives a truncation" "$(cat "$WORK/follow.out")" "after truncation"
kill "$fp" 2>/dev/null
wait "$fp" 2>/dev/null

# The pass line: alive, not noisy.
quiet_world passline
run "$HELPER" autopilot --passes 4 --interval 0
assert_eq "four idle passes write one pass line (the first)" "1" \
  "$(printf '%s\n' "$OUT" | grep -c ' pass [0-9]*: ')"
assert_contains "the pass line counts machines, agents, actions and time" "$OUT" " pass 1: "
run "$HELPER" autopilot --passes 11 --interval 0
assert_eq "an idle pass line every 10th pass" "2" \
  "$(printf '%s\n' "$OUT" | grep -c ' pass [0-9]*: ')"
new_world passaction
set_state bb22 w1:p3 "done"
show bb22 w1:p3 codex__done__prose_question
run "$HELPER" autopilot --once --catch-up
assert_contains "a pass that acted writes its line" "$OUT" "1 actions"

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
    def warn(self, addr, exc): self.warned = getattr(self, 'warned', []) + [addr]

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

# Nothing is left blocked when a refusal resolves it: a menu with no acceptable row (every row
# refuses or widens) is DENIED — its first refusal row, else Esc — and the agent is told once idle.
io, ap = fresh()
turn(io, 1, state='blocked', screen='claude__blocked__only_refusals'); ap.run_pass()
assert io.sent[0] == ('keys', 'w1:p2', ('enter',)), 'row 1, "No", is already selected'
assert ('keyed', 'local:w1:p2', 'denied') in io.log and not any(o[0] == 'left' for o in io.log), io.log
turn(io, 2, state='done', screen='codex__done__finished'); ap.run_pass()
told = [x for x in io.sent if x[0] == 'prompt']
assert told == [('prompt', 'w1:p2', '[autopilot]')] and ('nudged', 'local:w1:p2', 'denied_told') in io.log, io.sent
turn(io, 3, state='done', screen='codex__done__finished'); ap.run_pass()
assert len([x for x in io.sent if x[0] == 'prompt']) == 1, 'told once'
assert 'declined' in autopilot.DENIED_TEXT and 'never' in autopilot.DENIED_TEXT
# the pure denial: never Yes, never a widening row, never an exit row; Esc when no refusal row exists
d = autopilot.deny_decision(fx('claude__blocked__widening_session_wide'), 'blocked', 'denied', 'permission')
assert d.keys == ['down', 'down', 'enter'] and d.option == 4, (d.keys, d.option)
d = autopilot.deny_decision(fx('claude__blocked__permission_bash'), 'blocked', 'denied', 'permission')
assert d.option == 4, d.option
d = autopilot.deny_decision(fx('claude__blocked__bypass_ack'), 'blocked', 'denied', 'bypass_ack')
assert d.keys == ['esc'], 'the bypass consent has only "No, exit": Esc, never the exit row'
assert autopilot.deny_decision('just text', 'blocked', 'denied', 'permission').keys == ['esc']
# M1 (review of #63): an agent's own question whose rows all refuse or open free text is a decision
# about the work: left for the human, never answered "No" by the daemon
QUESTION_ONLY_REFUSALS = '''Claude Code

 How should I handle the failing migration?

 ❯ 1. No, revert my edits
   2. Type something.
   3. Chat about this

 Enter to select · ↑/↓ to navigate · Esc to cancel
'''
def pane(io, kind, seq, state, text):
    io.rows['local'] = [{'pane': 'w1:p2', 'state': state, 'agent': kind, 'seq': seq, 'turn': seq, 'you': False}]
    io.screens[('local', 'w1:p2')] = text
io, ap = fresh()
pane(io, 'claude', 1, 'blocked', QUESTION_ONLY_REFUSALS); ap.run_pass()
assert autopilot.decide('claude', 'blocked', QUESTION_ONLY_REFUSALS).cls == 'question'
assert io.sent == [] and io.log == [('left', 'local:w1:p2', 'question')], io.log
# L1: on a Codex pane Esc aborts the whole turn: a permission with no refusal row is left, never Esc
CODEX_NO_REFUSAL = '''  Would you like to run the following command?

  $ rm -rf build

› 1. Yes, and don't ask again for this command
  2. Always allow commands like this

  Press enter to confirm or esc to cancel
'''
assert autopilot.decide('codex', 'blocked', CODEX_NO_REFUSAL).action == 'leave'
io, ap = fresh()
pane(io, 'codex', 1, 'blocked', CODEX_NO_REFUSAL); ap.run_pass()
assert not any(k for k in io.sent if k[0] == 'keys'), io.sent
assert io.log == [('left', 'local:w1:p2', 'permission')], io.log
# ...while on Claude the same refusal-less permission gets Esc (a refusal there)
io, ap = fresh()
pane(io, 'claude', 1, 'blocked', CODEX_NO_REFUSAL.replace('›', '❯')); ap.run_pass()
assert ('keys', 'w1:p2', ('esc',)) in io.sent, io.sent
# L1: the denial reads the state decide read (a follow-up step reads 'blocked', not the pane's 'idle')
d = autopilot.deny_decision(fx('claude__blocked__only_refusals'), 'blocked', 'denied', 'permission')
assert d.keys == ['enter'] and d.option == 1
# L2: an exit or quit anywhere in a label rules the row out
CANCEL_AND_EXIT = '''  Do you want to proceed?

 ❯ 1. Yes, and don't ask again
   2. Cancel and exit
   3. No

 Esc to cancel
'''
d = autopilot.deny_decision(CANCEL_AND_EXIT, 'blocked', 'denied', 'permission')
assert d.option == 3 and d.keys == ['down', 'down', 'enter'], (d.option, d.keys)

# login and the bypass-permissions consent stay the human's: left, never keyed
for name, cls in (('claude__blocked__login_menu', 'login'), ('claude__blocked__bypass_ack', 'bypass_ack')):
    io, ap = fresh()
    turn(io, 1, state='blocked', screen=name); ap.run_pass()
    assert io.sent == [] and io.log == [('left', 'local:w1:p2', cls)], (name, io.log)

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

# A look that could not be completed is repeated on the next pass.
io, ap = fresh()
turn(io, 1, state='done', screen='claude__done__plan_approval')
real_read = io.read
io.read = lambda m, p: None
ap.run_pass(); ap.run_pass()
assert io.sent == []
io.read = real_read
ap.run_pass()
assert io.sent and io.sent[0] == ('keys', 'w1:p2', ('down', 'enter')), io.sent

# A pane that appears after the first look at its machine and already asks is nudged.
io, ap = fresh()
io.rows['local'] = []; ap.run_pass()
turn(io, 5); ap.run_pass()
assert len(prompts(io)) == 1, 'a late pane that asks is continued'

# After a usage limit ends, the pane is no longer read on every pass.
io, ap = fresh()
turn(io, 1, state='blocked', screen='claude__blocked__usage_limit'); ap.run_pass()
turn(io, 2, state='working'); ap.run_pass()
turn(io, 3, state='done', screen='codex__done__finished'); ap.run_pass()
now[0] += autopilot.LIMIT_RETRY * 2
reads = io.reads
ap.run_pass(); ap.run_pass()
assert io.reads == reads, 'no reads once the limit is over'

# A ticking counter next to an unmoved menu does not defeat the stuck guard.
io, ap = fresh()
turn(io, 1, state='blocked', screen='codex__blocked__approval')
base, tick = fx('codex__blocked__approval'), [0]
def ticking(machine, pane):
    tick[0] += 1
    return base.replace('› 1. Yes', '  Working (%ds)\n› 1. Yes' % tick[0])
io.read = ticking
for _ in range(4):
    ap.run_pass()
assert len([s for s in io.sent if s[0] == 'keys']) == autopilot.MAX_ATTEMPTS, io.sent
assert ('gave_up', 'local:w1:p2', 'stuck') in io.log

# The usage-limit retry never goes over a human's draft, and --no-nudge silences it.
io, ap = fresh()
turn(io, 1, state='idle', screen='codex__idle__limit_banner_over_draft'); ap.run_pass()
now[0] += autopilot.LIMIT_RETRY + 1; ap.run_pass()
assert io.sent == [], io.sent
io, ap = fresh(nudge=False)
turn(io, 1, state='blocked', screen='claude__blocked__usage_limit'); ap.run_pass()
now[0] += autopilot.LIMIT_RETRY + 1; ap.run_pass()
assert io.sent == [], io.sent

# After a keyed step, a printed menu above an input line is not "the next step".
io, ap = fresh()
turn(io, 1, state='blocked', screen='codex__blocked__approval')
def swap(machine, pane, keys):
    io.sent.append(('keys', pane, tuple(keys)))
    io.rows['local'][0]['state'] = 'done'
    io.screens[('local', pane)] = fx('claude__done__printed_menu_over_draft')
    return True
io.keys = swap
ap.run_pass()
assert io.sent == [('keys', 'w1:p2', ('enter',))], io.sent
# ... and neither is an input line holding a draft with wrapped text under it.
io, ap = fresh()
turn(io, 1, state='blocked', screen='codex__blocked__approval')
def swap_to_draft(machine, pane, keys):
    io.sent.append(('keys', pane, tuple(keys)))
    io.rows['local'][0]['state'] = 'idle'
    io.screens[('local', pane)] = fx('codex__idle__trust_text_above_draft')
    return True
io.keys = swap_to_draft
ap.run_pass()
assert io.sent == [('keys', 'w1:p2', ('enter',))], io.sent

# An error on one pane does not stop the pass.
io, ap = fresh()
io.rows['local'] = [{'pane': 'w1:p2', 'state': 'blocked', 'agent': 'x', 'seq': 1, 'turn': 1, 'you': False},
                    {'pane': 'w1:p3', 'state': 'blocked', 'agent': 'codex', 'seq': 1, 'turn': 1, 'you': False}]
io.screens[('local', 'w1:p3')] = fx('codex__blocked__approval')
def boom(machine, pane):
    if pane == 'w1:p2':
        raise RuntimeError('x')
    return io.screens[(machine, pane)]
io.read = boom
ap.run_pass()
assert io.warned == ['local:w1:p2'] and ('keys', 'w1:p3', ('enter',)) in io.sent, (io.warned, io.sent)
print('ok')
PY
assert_rc "turn detection, the nudge cap, the usage-limit retry, backoff, repeated looks and the stuck guard hold" 0
assert_eq "(scripted I/O ran to its end)" "ok" "$OUT"
# shellcheck source-path=SCRIPTDIR source=autopilot_loop.sh
. "$ROOT/tests/scopes/autopilot_loop.sh"
# shellcheck source-path=SCRIPTDIR source=queue.sh
. "$ROOT/tests/scopes/queue.sh"
# shellcheck source-path=SCRIPTDIR source=revive.sh
. "$ROOT/tests/scopes/revive.sh"
unset HERDR_PEERS_AUTOPILOT_CONFIRM

# A failed test never leaves a background autopilot behind.
for p in ${BG_PIDS:-}; do kill -9 "$p" 2>/dev/null; done
