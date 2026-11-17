# shellcheck shell=bash
# Part of scope `autopilot` (sourced by autopilot.sh): revive (2.2.0, PLAN_010).
# With --revive (the human's standing grant) the loop launches one fresh agent for
# a plan on this machine whose lead is gone (or at a usage limit that resets more
# than 30 minutes away) and whom nobody in its succession or lanes can take over;
# the agent takes the plan with `lead takeover --reason revive`, checked by the
# helper against the daemon's one-time ticket. A stalled plan's live lead is asked
# to hand over instead. Capped, recorded, and never adopted by other machines.
# Also: the unknown-screen corpus, and the map's `revived` mark.

R_SCRIPTS="$ROOT/skills/herdr-peers/scripts"

# --- the daemon, scripted ----------------------------------------------------------------------
run python3 - "$R_SCRIPTS" "$ROOT/tests/fixtures/screens" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot as A
now = [100000.0]
class IO(object):
    def __init__(self):
        self.rows, self.screens, self.sent, self.events, self.log = [], {}, [], [], []
        self.plans_report = {'plans': [], 'agents': [], 'queues': []}
        self.launched, self.released, self.tickets, self.saved_unknown = [], [], [], []
        self.fail_launch = False
        self.next_pane = 9
    def sources(self): return ['local']
    def agents(self, m): return [dict(r) for r in self.rows]
    def read(self, m, p): return self.screens.get(p, '')
    def state(self, m, p): return [r for r in self.rows if r['pane'] == p][0]['state']
    def keys(self, m, p, k): self.sent.append(('keys', p, tuple(k))); return True
    def prompt(self, m, p, t): self.sent.append(('prompt', p, t)); return True
    def record(self, addr, kind, choice, outcome, dry, plan=None): self.log.append((outcome, choice.cls, choice.why, plan))
    def warn(self, a, e): raise e
    def label(self, m): return m
    def identity(self): return {}
    def plans(self, m, panes, f): return 'ok', self.plans_report
    def save_fleet(self, t): self.saved = t
    def load_fleet(self): return None
    def event(self, e, dry): self.events.append((e['event'], e['plan']))
    def revive_launch(self, plan, repo, kinds):
        if self.fail_launch:
            raise RuntimeError('no account')
        pane = 'w%d:p1' % self.next_pane
        self.next_pane += 1
        self.launched.append((plan, repo, list(kinds), pane))
        return {'pane': pane, 'terminal': 't', 'workspace': pane.split(':')[0], 'kind': 'claude', 'profile': '@work1'}
    def revive_release(self, kind, profile, ws): self.released.append((kind, profile, ws))
    def revive_ticket(self, plan, pane, epoch, ttl, workspace=None): self.tickets.append((plan, pane, epoch, ttl, workspace))
    def save_unknown(self, kind, text): self.saved_unknown.append((kind, text))
row = lambda pane, state='idle', agent='claude': {'pane': pane, 'state': state, 'agent': agent, 'seq': 1, 'turn': 1,
                                                  'you': False, 'cwd': '/r'}
def plan(pid='P1', lead='local:w1:p1', epoch=1, succession=(), lanes=(), repo='/r', progress='a' * 16):
    return {'plan': pid, 'class': 'open', 'lead': lead, 'epoch': epoch, 'succession': list(succession),
            'lanes': list(lanes), 'repo_root': repo, 'blocker_class': None, 'progress': progress,
            'updated_at': None, 'lead_in_repo': True, 'open_asks': 0, 'tasks_done': 1, 'tasks_total': 3,
            'current_task': None, 'detail': None, 'appoint': None, 'appointed': False}
def fresh(**kw):
    io = IO()
    kw.setdefault('revive', True)
    return io, A.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, loop=True, grace=0, **kw)
def step(ap, s=60):
    now[0] += s; ap.run_pass()
prompts_to = lambda io, pane: [t for k, p, t in io.sent if k == 'prompt' and p == pane]
classes = lambda io: [o[1] for o in io.log]

# 1. An orphan plan here: lead gone, its successor gone, no lane. With --revive one agent is launched
#    in the plan's checkout, briefed with the ticket when it is up, and reported once it leads.
io, ap = fresh()
io.plans_report['plans'] = [plan(succession=['local:w1:p8'])]
for _ in range(3):
    step(ap)
assert io.launched == [('P1', '/r', ['claude'], 'w9:p1')], io.launched
assert 'plan_revive_launched' in classes(io) and ('plan_no_lead', 'P1') not in io.events, (io.log, io.events)
step(ap)
assert io.tickets == [], 'no ticket before the new agent is up'
io.rows = [row('w9:p1', 'idle')]
io.screens['w9:p1'] = 'Claude Code\n\n❯ \n'
step(ap)
assert io.tickets == [('P1', 'w9:p1', 1, A.REVIVE_TICKET_TTL, 'w9')], io.tickets
brief = prompts_to(io, 'w9:p1')
assert len(brief) == 1 and 'lead takeover --plan P1 --reason revive' in brief[0] and 'lead verify --plan P1' in brief[0], brief
assert 'lost its lead (no_agent)' in brief[0], brief
step(ap)
assert len(prompts_to(io, 'w9:p1')) == 1, 'briefed once'
io.plans_report['plans'] = [plan(lead='local:w9:p1', epoch=2, succession=['local:w1:p8'])]
io.plans_report['plans'][0]['revived'] = True
step(ap)
assert ('plan_revived', 'P1') in io.events and io.events.count(('plan_revived', 'P1')) == 1, io.events
assert ('left', 'plan_revived', 'no_agent', 'P1') in io.log
assert ap.plans.memos[('local', 'P1')].revive is None
assert io.released == [] and not any(k == 'keys' for k, _p, _t in io.sent), 'the old pane is never touched'
assert '"revived": true' in io.saved, 'the map marks the revived lead'

# 2. Without --revive: the notice, as before; nothing launched.
io, ap = fresh(revive=False)
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert io.launched == [] and ('plan_no_lead', 'P1') in io.events, (io.launched, io.events)

# 3. A member here and free (a successor alive): the takeover prompt, never a revive.
io, ap = fresh()
io.rows = [row('w1:p8', 'idle')]
io.screens['w1:p8'] = 'Claude Code\n\n❯ \n'
io.plans_report['plans'] = [plan(succession=['local:w1:p8'])]
for _ in range(3):
    step(ap)
assert io.launched == [] and any('lead takeover --plan P1' in t and '--reason revive' not in t
                                for t in prompts_to(io, 'w1:p8')), io.sent

# 4. D1: a member on another machine, or a plan led from another machine: not this daemon's.
io, ap = fresh()
io.plans_report['plans'] = [plan(lanes=['m2:w3:p1'])]
for _ in range(3):
    step(ap)
assert io.launched == [] and ('plan_no_lead', 'P1') in io.events
io, ap = fresh()
io.plans_report['plans'] = [plan(repo=None)]
for _ in range(3):
    step(ap)
assert io.launched == [], 'no repository, no checkout to start in'

# 5. Caps: one revive per plan per 6 h, two per plan in all, two an hour fleet-wide.
io, ap = fresh()
io.plans_report['plans'] = [plan(pid='P%d' % i) for i in range(1, 4)]
for _ in range(3):
    step(ap)
assert [l[0] for l in io.launched] == ['P1', 'P2'], io.launched
assert ('plan_no_lead', 'P3') not in io.events, 'the third waits for the hourly cap, quietly'
io.rows = []
for _ in range(4):
    step(ap)      # no agent comes up: both abort after REVIVE_START
assert sorted(r[2] for r in io.released) == ['w10', 'w9'], io.released
assert ('plan_no_lead', 'P1') in io.events and classes(io).count('revive_failed') >= 2, io.log
now[0] += 3601
step(ap)
assert [l[0] for l in io.launched] == ['P1', 'P2', 'P3'], 'the hour passed: the third is launched'
step(ap, A.REVIVE_EVERY - 7200)
assert [l[0] for l in io.launched].count('P1') == 1, 'one revive per plan per 6 h'
step(ap, 7200)
step(ap); step(ap)
assert [l[0] for l in io.launched].count('P1') == 2, 'after 6 h, a second'
assert A.MAX_REVIVES == 2

# 6. A briefed agent that does not take the plan in time: released, the notice follows.
io, ap = fresh()
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
io.rows = [row('w9:p1', 'idle')]
io.screens['w9:p1'] = 'Claude Code\n\n❯ \n'
step(ap)
assert io.tickets
step(ap, A.REVIVE_TICKET_TTL + 1)
assert io.released == [], 'L1: a margin past the ticket before giving up'
step(ap, A.REVIVE_ABORT_MARGIN)
assert io.released == [('claude', '@work1', 'w9')] and ('left', 'revive_failed', 'takeover_timeout', 'P1') in io.log

# 7. A failed launch is recorded; the notice follows.
io, ap = fresh()
io.fail_launch = True
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert ('left', 'revive_failed', 'launch', 'P1') in io.log and ('plan_no_lead', 'P1') in io.events

# 8. D3: a lead at its usage limit counts as gone only when its banner resets more than 30 min away.
for banner, want in (("You've hit your usage limit. Try again in 2 hours 13 minutes.", 1),
                     ("You've hit your usage limit. Try again in 10 minutes.", 0),
                     ("You've hit your usage limit.", 0)):
    io, ap = fresh()
    io.rows = [row('w1:p1', 'blocked')]
    io.screens['w1:p1'] = banner + '\n'
    io.plans_report['plans'] = [plan()]
    for _ in range(3):
        step(ap)
    assert io.launched == [], 'M1: not before the appointment grace has held with the plan frozen'
    step(ap, A.APPOINT_GRACE); step(ap)
    assert len(io.launched) == want, (banner, io.launched, io.log)
# M1: progress during the grace starts it over
io, ap = fresh()
io.rows = [row('w1:p1', 'blocked')]
io.screens['w1:p1'] = "You've hit your usage limit. Try again in 3 hours.\n"
io.plans_report['plans'] = [plan()]
step(ap); step(ap)
step(ap, A.APPOINT_GRACE - 120)
io.plans_report['plans'] = [plan(progress='b' * 16)]
step(ap, 200)
assert io.launched == [], 'the plan moved: the grace starts over'
# M1/T49: a banner in tool output, or a stray 'reset N' line, is not a limit to revive on
for screen in ("  ⎿  You've hit your usage limit · resets in 9 hours\n",
               "You've hit your usage limit\nI will try again 7 times\n",
               "You've hit your limit\ngit reset 2 files\n"):
    io, ap = fresh()
    io.rows = [row('w1:p1', 'blocked')]
    io.screens['w1:p1'] = screen
    io.plans_report['plans'] = [plan()]
    step(ap); step(ap); step(ap, A.APPOINT_GRACE); step(ap)
    assert io.launched == [], (screen, io.launched)
# M2: the excluded lead's plan is left to the human
io, ap = fresh(exclude=['local:w1:p1'])
io.rows = [row('w1:p1', 'blocked')]
io.screens['w1:p1'] = "You've hit your usage limit. Try again in 3 hours.\n"
io.plans_report['plans'] = [plan()]
step(ap); step(ap); step(ap, A.APPOINT_GRACE); step(ap)
assert io.launched == [], 'an excluded lead is never revived away'

# 9. D2: a stalled plan whose lead is alive: a fresh agent, and the lead asked once to hand over.
io, ap = fresh()
io.rows = [row('w1:p1', 'idle')]
io.screens['w1:p1'] = 'Claude Code\n\n❯ \n'
io.plans_report['plans'] = [plan()]
step(ap)
ap.plans.memos[('local', 'P1')].situation = 'plan_stalled'
step(ap)
assert io.launched and io.launched[0][3] == 'w9:p1', io.launched
io.rows = [row('w1:p1', 'idle'), row('w9:p1', 'idle')]
io.screens['w9:p1'] = 'Claude Code\n\n❯ \n'
io.screens['w1:p1'] = 'Claude Code\n\n❯ half-typed by the human'
step(ap)
assert not [t for t in prompts_to(io, 'w1:p1') if 'lead handover' in t], 'H1: never over a draft'
io.screens['w1:p1'] = 'Claude Code\n\n❯ \n'
step(ap)
ask = [t for t in prompts_to(io, 'w1:p1') if 'lead handover' in t]
assert len(ask) == 1 and 'lead handover --plan P1 --to local:w9:p1' in ask[0], io.sent
assert io.tickets == [], 'a handover needs no ticket: it is the lead\'s own act'
io.plans_report['plans'] = [plan(lead='local:w9:p1', epoch=2)]
step(ap)
handed = [t for t in prompts_to(io, 'w9:p1') if 'You now lead' in t]
assert len(handed) == 1 and 'You now lead plan P1' in handed[0], io.sent
assert ('plan_revived', 'P1') in io.events
# a stalled lead that does not hand over: released after the window
io, ap = fresh()
io.rows = [row('w1:p1', 'idle')]
io.screens['w1:p1'] = 'Claude Code\n\n❯ \n'
io.plans_report['plans'] = [plan()]
step(ap)
ap.plans.memos[('local', 'P1')].situation = 'plan_stalled'
step(ap)
io.rows = [row('w1:p1', 'idle'), row('w9:p1', 'idle')]
io.screens['w9:p1'] = 'Claude Code\n\n❯ \n'
step(ap)
step(ap, A.REVIVE_HANDOVER + 1)
assert io.released and ('left', 'revive_failed', 'handover_timeout', 'P1') in io.log

# H1: the brief waits while the new pane shows a dialog, a login or a draft
for screen in (open('%s/claude__blocked__login_menu.screen' % sys.argv[2]).read(),
               open('%s/claude__blocked__permission_bash.screen' % sys.argv[2]).read(),
               'Claude Code\n\n❯ something typed\n'):
    io, ap = fresh()
    io.plans_report['plans'] = [plan()]
    for _ in range(3):
        step(ap)
    io.rows = [row('w9:p1', 'idle')]
    io.screens['w9:p1'] = screen
    step(ap)
    assert io.tickets == [] and prompts_to(io, 'w9:p1') == [], (screen[:40], io.sent)
    io.screens['w9:p1'] = 'Claude Code\n\n❯ \n'
    step(ap)
    assert len(io.tickets) == 1 and len(prompts_to(io, 'w9:p1')) == 1
# M2: after a revive, the old lead at its limit is never resumed beside the new lead
io, ap = fresh()
io.rows = [row('w1:p1', 'blocked')]
io.screens['w1:p1'] = "You've hit your usage limit. Try again in 3 hours.\n"
io.plans_report['plans'] = [plan()]
step(ap); step(ap); step(ap, A.APPOINT_GRACE); step(ap)
assert io.launched
io.rows = [row('w1:p1', 'blocked'), row('w9:p1', 'idle')]
io.screens['w9:p1'] = 'Claude Code\n\n❯ \n'
step(ap)
io.plans_report['plans'] = [plan(lead='local:w9:p1', epoch=2)]
step(ap)
assert 'local:w1:p1' in ap.plans.revived_away
sent = len(io.sent)
step(ap, A.LIMIT_RETRY + 1); step(ap, A.LIMIT_RETRY + 1)
assert not [x for x in io.sent[sent:] if x[1] == 'w1:p1'], io.sent[sent:]
# M4: the caps also read the lead record (a restart resets nothing)
io, ap = fresh()
p_ = plan(); p_['revives'] = 2
io.plans_report['plans'] = [p_]
for _ in range(3):
    step(ap)
assert io.launched == [], 'two revives recorded: only the human'
io, ap = fresh()
p_ = plan(); p_['revived_at'] = __import__('time').strftime('%Y-%m-%dT%H:%M:%SZ', __import__('time').gmtime(now[0] - 3600))
io.plans_report['plans'] = [p_]
for _ in range(3):
    step(ap)
assert io.launched == [], 'revived an hour ago: not again within 6 h'
io, ap = fresh()
io.revive_history = lambda plan=None: [now[0] - 60, now[0] - 120] if plan is None else []
io.revive_note = lambda t, plan=None: None
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert io.launched == [], 'two launches this hour on record: the fleet-wide cap holds after a restart'
# the launch log counts handover and failed launches of a plan, which the lead record never sees
io, ap = fresh()
io.revive_history = lambda plan=None: [now[0] - 8 * 3600, now[0] - 7 * 3600] if plan == 'P1' else []
io.revive_note = lambda t, plan=None: None
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert io.launched == [], 'two launches of P1 in the log: the per-plan cap holds after a restart'
io, ap = fresh()
io.revive_history = lambda plan=None: [now[0] - 3600] if plan == 'P1' else []
io.revive_note = lambda t, plan=None: None
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert io.launched == [], 'a launch of P1 an hour ago in the log: not again within 6 h'
io, ap = fresh()
notes = []
io.revive_history = lambda plan=None: []
io.revive_note = lambda t, plan=None: notes.append(plan)
io.fail_launch = True
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert notes == ['P1'], ('a failed launch is written to the log', notes)
# a pane Herdr labels idle but showing an unknown prompt never gets the brief typed in
io, ap = fresh()
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert io.launched
io.rows = [row('w9:p1', 'idle')]
io.screens['w9:p1'] = 'Overwrite config? (y/N)\n'
step(ap)
assert io.tickets == [] and prompts_to(io, 'w9:p1') == [], 'no known input line: nothing typed'
assert A.shows_input_row('claude', 'Claude Code\n\n❯ \n') and A.shows_input_row('codex', 'x\n› Ask Codex\n')
assert not A.shows_input_row('claude', 'Overwrite config? (y/N)\n') and not A.shows_input_row('gemini', '❯ \n')

# 10. A dry run launches nothing and says so.
io, ap = fresh(dry_run=True)
io.plans_report['plans'] = [plan()]
for _ in range(3):
    step(ap)
assert io.launched == [] and 'plan_revive' in classes(io)

# 11. An unknown screen: a sanitized copy is kept for new fixtures; no key is sent.
io, ap = fresh(revive=False)
io.rows = [row('w1:p2', 'blocked')]
io.screens['w1:p2'] = 'some odd full-screen thing\nwith no menu we know\n'
ap.run_pass()
assert io.saved_unknown == [('claude', io.screens['w1:p2'])] and not any(k == 'keys' for k, _p, _t in io.sent)

# 12. The daemon's own reading of a reset.
t0 = 1700000000.0
assert A.limit_reset_seconds("You've hit your usage limit. Try again in 1 hour", t0) == 3600
assert A.limit_reset_seconds("You've hit your session limit · resets in 45m", t0) == 2700
assert A.limit_reset_seconds('no limit line · resets in 45m', t0) is None
assert A.limit_reset_seconds("You've hit your session limit · resets 25:99", t0) is None
tm = __import__('time')
t13 = tm.mktime((2026, 11, 16, 13, 0, 0, 0, 0, -1))
z = 'America/Bogota'
assert A.limit_reset_seconds("You've hit your session limit · resets 3pm", t13, zone=z) == 7200
assert A.limit_reset_seconds("You've hit your session limit · resets 11am", t13, zone=z) is None, 'passed: never next day'
assert A.limit_reset_seconds("You've hit your session limit · resets 11pm", t13, zone=z) is None, 'more than 6 h: unknown'
assert A.limit_reset_seconds("You've hit your session limit · resets 3pm (Europe/Berlin)", t13, zone=z) is None
assert A.limit_reset_seconds("You've hit your session limit · resets 3pm (America/Bogota)", t13, zone=z) == 7200
assert A.limit_reset_seconds("You've hit your limit\ngit reset 2 files", t13, zone=z) is None
assert A.limit_reset_seconds("You've hit your limit\nprogress: reset 9 of 12", t13, zone=z) is None
assert A.limit_reset_seconds("You've hit your limit\nTry again in 45 minutes", t13, zone=z) == 2700
assert A.limit_reset_seconds("You've hit your limit\nok\nTry again in 9 hours", t13, zone=z) is None, 'banner line or the next only'
assert A.limit_reset_seconds("You've hit your limit\nok\nalarm resets at 2:30pm", t13, zone=z) is None
assert A.limit_reset_seconds("  ⎿  You've hit your usage limit · resets in 9 hours", t13, zone=z) is None
print('ok')
PY
assert_rc "revive: launched for an orphan, briefed with a ticket, reported; capped; timed out; D1-D3; stalled handover" 0
assert_eq "(scripted revive checks ran to their end)" "ok" "$OUT"

# --- the protocol: the ticket, the helper's revive takeover, receivers ---------------------------
new_world revive_protocol
run python3 - "$R_SCRIPTS" <<'PY'
import argparse, json, os, sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
os.environ['HERDR_PEERS_APPOINT_PROBE_GAP'] = '0'
import herdr_peers as H
store = H.Store(); store.ensure()

# lead-v2 accepts via: revive; receivers never adopt one
rec = H.new_lead_record('P1', 'local:w9:p1', 4, [], [], '/r', via=H.REVIVE_VIA)
assert H.lead_record_error(rec) is None, H.lead_record_error(rec)
bad = dict(rec, via='coup')
assert H.lead_record_error(bad)
prev = {'lead': 'local:w1:p1', 'epoch': 3, 'succession': ['local:w1:p8'], 'lanes': [], 'appoint': None}
st, why, _, _ = H.transition(prev, rec, 'local:w9:p1', lambda a: (True, 'no_agent', False))
assert st == 'rejected' and 'only on the machine whose daemon granted it' in why, (st, why)

# the ticket: exact plan, pane and epoch; unexpired; private; one time
path = H.write_revive_ticket(store, 'P1', 'w9:p1', 3, 600, pid=4242)
assert oct(os.stat(path).st_mode & 0o777) == '0o600'
assert H.find_revive_ticket(store, 'P1', 'w9:p1', 3)[0] == path
for other in (('P2', 'w9:p1', 3), ('P1', 'w9:p2', 3), ('P1', 'w9:p1', 4)):
    assert H.find_revive_ticket(store, *other) is None, other
os.unlink(path)
old = H.write_revive_ticket(store, 'P9', 'w9:p1', 1, -5, pid=4242)
assert H.find_revive_ticket(store, 'P9', 'w9:p1', 1) is None and not os.path.exists(old), 'expired: removed'
loose = H.write_revive_ticket(store, 'P8', 'w9:p1', 1, 600, pid=4242)
os.chmod(loose, 0o644)
assert H.find_revive_ticket(store, 'P8', 'w9:p1', 1) is None, 'a ticket others can read is ignored'
real = H.write_revive_ticket(store, 'P7', 'w9:p1', 1, 600, pid=4242)
link = os.path.join(store.dir, 'revive-%s.json' % ('0' * 16))
os.symlink(real, link); os.unlink(real)
assert H.find_revive_ticket(store, 'P7', 'w9:p1', 1) is None, 'a symlinked ticket is ignored'

# lead_revive, with the daemon and the probes stubbed
H.save_lead(store, H.new_lead_record('P1', 'local:w1:p1', 3, ['local:w1:p8'], ['local:w1:p7'], '/r'), None, 'claim')
H.git_root = lambda common=False: '/r'
H.pane_workspace = lambda pane: pane.split(':')[0]
H.finish_lead = lambda args, store, pane, record, what, best_effort=(), required=(): 0
state = {'gone': lambda a: (True, 'no_agent', False), 'pid': 4242, 'opts': {'revive': True},
         'screen': ''}
H.gone = lambda a: state['gone'](a)
H.autopilot_pid = lambda s: state['pid']
H.autopilot_options = lambda s, pid: {'pid': pid, 'options': state['opts']}
H.herdr = lambda argv, machine=None, timeout=None: (0, state['screen'], '')
args = argparse.Namespace(reason='revive', plan='P1')
def attempt():
    try:
        H.lead_revive(args, 'P1', store, 'w9:p1', 'local:w9:p1', H.load_lead(store, 'P1'))
        return None
    except H.Stop as exc:
        return exc.message
assert 'no revive ticket' in attempt(), 'no ticket, no revive'
for bad in ({'revives': 'x'}, {'revives': True}, {'revives': -1}, {'revived_at': 7}, {'revived_at': '2026-13-45T99:99:99Z'}):
    d = dict(H.load_lead(store, 'P1')); d.update(bad)
    try:
        H.lead_revive(args, 'P1', store, 'w9:p1', 'local:w9:p1', d)
        raise AssertionError('revived with %r' % bad)
    except H.Stop as exc:
        assert 'unreadable revive' in exc.message, (bad, exc.message)
other_ws = H.write_revive_ticket(store, 'P1', 'w9:p1', 3, 600, pid=4242, workspace='w5')
assert 'not in the workspace the autopilot created' in attempt(), 'M5: a ticket for another workspace'
os.unlink(other_ws)
H.write_revive_ticket(store, 'P1', 'w9:p1', 3, 600, pid=4242, workspace='w9')
state['pid'] = None
assert 'the ticket does not name the running autopilot' in attempt()
state['pid'], state['opts'] = 4242, {'revive': False}
assert 'the ticket does not name the running autopilot' in attempt()
state['pid'], state['opts'] = 4343, {'revive': True}
assert 'the ticket does not name the running autopilot' in attempt(), 'a ticket from another daemon process'
state['pid'] = 4242
state['gone'] = lambda a: (a != 'local:w1:p7', 'idle', False)
assert 'local:w1:p7 is idle' in attempt(), 'a live lane refuses'
state['gone'] = lambda a: (True, 'unreachable', False)
assert 'cannot be reached' in attempt(), 'an unreachable machine is not proof'
state['gone'] = lambda a: (True, 'usage_limit', True) if a == 'local:w1:p1' else (True, 'no_agent', False)
state['screen'] = "You've hit your usage limit. Try again in 10 minutes.\n"
assert 'resets soon' in attempt(), 'a limit that resets soon is not gone'
H.git_root = lambda common=False: '/elsewhere'
assert 'another repository' in attempt()
H.git_root = lambda common=False: '/r'
state['screen'] = "You've hit your usage limit. Try again in 3 hours.\n"
assert attempt() is None, 'the lead at a long limit, every member gone: revived'
data = H.load_lead(store, 'P1')
assert data['record']['lead'] == 'local:w9:p1' and data['record']['epoch'] == 4 and data['record_via'] == 'revive', data
assert data['record']['succession'] == ['local:w1:p8'] and data['record']['lanes'] == ['local:w1:p7']
assert H.find_revive_ticket(store, 'P1', 'w9:p1', 3) is None, 'the ticket is consumed'
assert data['revives'] == 1 and data['revived_at'], 'M4: the revive is counted in the lead record'
logged = [r for r in store.records() if r.get('state') == 'revived']
assert logged and 'revive granted by the daemon' in logged[-1]['note'] and 'weak' in logged[-1]['note'], logged
args2 = argparse.Namespace(reason='revive', plan='P1')
H.write_revive_ticket(store, 'P1', 'w9:p2', 4, 600, pid=4242, workspace='w9')
try:
    H.lead_revive(args2, 'P1', store, 'w9:p2', 'local:w9:p2', H.load_lead(store, 'P1'))
    raise AssertionError('a second revive within 6 h')
except H.Stop as exc:
    assert 'less than 6 hours ago' in exc.message, exc.message
# the count survives later writes (a handover) and caps at two
data = H.load_lead(store, 'P1')
H.save_lead(store, H.new_lead_record('P1', 'local:w9:p3', 5, [], [], '/r'), None, 'handover')
assert H.load_lead(store, 'P1')['revives'] == 1, 'kept across a handover'
raw = json.load(open(H.lead_path(store, 'P1'))); raw['revives'] = 2; raw['revived_at'] = '2020-01-01T00:00:00Z'
H.write_private(H.lead_path(store, 'P1'), json.dumps(raw))
H.write_revive_ticket(store, 'P1', 'w9:p2', 5, 600, pid=4242, workspace='w9')
try:
    H.lead_revive(args2, 'P1', store, 'w9:p2', 'local:w9:p2', H.load_lead(store, 'P1'))
    raise AssertionError('a third revive')
except H.Stop as exc:
    assert 'already revived 2 times' in exc.message, exc.message
print('ok')
PY
assert_rc "revive protocol: via revive, receivers refuse it, the one-time ticket, the helper's checks" 0
assert_eq "(scripted revive protocol checks ran to their end)" "ok" "$OUT"

# --- through the helper ---------------------------------------------------------------------------
loop_world revive_cli
# shellcheck disable=SC2153 # REPO is set by loop_world (autopilot_loop.sh)
mkstate "$REPO" PLAN_990_revive "$V5_OPEN"; pane_claim w2:p1 "$REPO" PLAN_990_revive
run sh -c "cd '$REPO' && HERDR_PANE_ID=w1:p2 '$HELPER' lead takeover --plan PLAN_990_revive --reason revive"
assert_rc "a revive takeover with no ticket is refused" 4
assert_contains "and says why" "$ERR" "no revive ticket"
run "$HELPER" autopilot --once --revive
assert_rc "--revive without --loop is a usage error" 2
run "$HELPER" autopilot --loop --once --revive --dry-run
assert_rc "--revive without coding-agents-kit refuses to start" 2
assert_contains "and says what to install" "$ERR" "--revive needs coding-agents-kit (\`ak\`) on PATH"
run "$HELPER" autopilot --loop --once --dry-run
assert_rc "autopilot without --revive starts without coding-agents-kit" 0
assert_contains "and suggests it, once, as optional" "$ERR" "coding-agents-kit (\`ak\`) is not installed. Autopilot works without it"
export FAKE_AK_DIR="$WORLD/ak"; mkdir -p "$FAKE_AK_DIR"
KBIN="$WORLD/bin"; mkdir -p "$KBIN"; ln -s "$ROOT/tests/fakes/agentkit/ak" "$KBIN/ak"
K_OLDPATH=$PATH; export PATH="$KBIN:$PATH"
echo 1.2.0 >"$FAKE_AK_DIR/version"
run "$HELPER" autopilot --loop --once --revive --dry-run
assert_rc "--revive refuses a coding-agents-kit older than 1.3.0" 2
assert_contains "and names the version it needs" "$ERR" "--revive needs coding-agents-kit 1.3.0 or later"
rm -f "$FAKE_AK_DIR/version"
run "$HELPER" autopilot --loop --once --revive --dry-run
assert_rc "--revive with --loop and coding-agents-kit runs" 0
run "$HELPER" autopilot --loop --once --dry-run
assert_not_contains "with the kit installed nothing is suggested" "$ERR" "is not installed"
export PATH=$K_OLDPATH

# --- the launch, against the fakes ---------------------------------------------------------------
new_world revive_launch
export FAKE_AK_DIR="$WORLD/ak"; mkdir -p "$FAKE_AK_DIR"
RBIN="$WORLD/bin"; mkdir -p "$RBIN"; ln -s "$ROOT/tests/fakes/agentkit/ak" "$RBIN/ak"
R_OLDPATH=$PATH; export PATH="$RBIN:$PATH"
cat >"$FAKE_AK_DIR/pick-v2.json" <<'JSON'
{"schema": "pick-v2", "interface": 1, "qualifies": true, "kind": "claude", "cli": "claude", "profile": "@work1",
 "launch": {"argv": ["ak", "claude", "@work1", "--ask"], "env_names": [], "permissions": "ask"}}
JSON
RREPO="$WORLD/repo"; mkdir -p "$RREPO"
run python3 - "$R_SCRIPTS" "$(cd "$RREPO" && pwd -P)" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr_peers as H
io = H.AutopilotIO(H.Store(), 'w1:p1', None, None, quiet=True)
info = io.revive_launch('PLAN_990_revive', sys.argv[2], ['claude,codex', 'cl aude', '', 7, 'claude'])
assert info['pane'] == 'w9:p1' and info['kind'] == 'claude' and info['profile'] == '@work1', info
assert H.pane_workspace(info['pane']) == info['workspace'], (H.pane_workspace(info['pane']), info)
assert H.pane_workspace('w1:p404') is None, 'a pane Herdr does not know has no workspace'
try:
    io.revive_launch('P', sys.argv[2], ['claude,codex', 'x y'])
    raise AssertionError('launched with no valid kind')
except H.Stop as exc:
    assert 'no agent kind' in exc.message
io.revive_release(info['kind'], info['profile'], info['workspace'])
for bad in ('/no/such/dir', 'relative/path', sys.argv[2] + '/../' + sys.argv[2].rsplit('/', 1)[-1]):
    try:
        io.revive_launch('P', bad, ['claude'])
        raise AssertionError('launched in %r' % bad)
    except H.Stop:
        pass
print('ok')
PY
assert_eq "a revive launch picks with ask mode, leases for revive and starts in the plan's checkout" "ok" "$OUT"
assert_contains "the lease names its purpose" "$(cat "$FAKE_AK_DIR/argv.log")" "--purpose revive"
assert_contains "L6: only kinds that pass KIND_RE reach ak pick" "$(cat "$FAKE_AK_DIR/argv.log")" "pick --kinds claude --owner"
assert_contains "and is released when the revive does not take" "$(cat "$FAKE_AK_DIR/argv.log")" "lease release claude @work1"
assert_contains "the workspace starts in the plan's checkout" "$(cat "$FAKE_HERDR_DIR/local/workspaces.log")" "$(cd "$RREPO" && pwd -P)"
assert_contains "and is closed with it" "$(cat "$FAKE_HERDR_DIR/local/workspaces.log")" '"verb": "close"'
export PATH=$R_OLDPATH

# --- the unknown-screen corpus -------------------------------------------------------------------
new_world revive_corpus
run python3 - "$R_SCRIPTS" <<'PY'
import os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr_peers as H
io = H.AutopilotIO(H.Store(), 'w1:p1', None, None, quiet=True)
fake = 'github_pat_' + 'A' * 44   # a fake token, built at run time
path = io.save_unknown('claude', 'odd screen\x1b[31m red\n' + 'token ' + fake + '\nlast line‮\n')
body = open(path).read()
assert '\x1b' not in body and '[31m' not in body and '‮' not in body and fake not in body and '[redacted]' in body, body
assert oct(os.stat(path).st_mode & 0o777) == '0o600'
assert oct(os.stat(os.path.dirname(path)).st_mode & 0o777) == '0o700'
assert io.save_unknown('claude', 'odd screen\x1b[31m red\n' + 'token ' + fake + '\nlast line‮\n') is None, 'kept once'
for i in range(H.UNKNOWN_MAX + 5):
    io.save_unknown('codex', 'screen number %s\n' % chr(65 + i % 26) * (i + 1))
kept = [n for n in os.listdir(os.path.dirname(path)) if H.UNKNOWN_NAME_RE.fullmatch(n)]
assert len(kept) <= H.UNKNOWN_MAX, len(kept)
assert io.save_unknown('claude', '\n\n') is None
# H3: a private key block is dropped whole; a wrapped or cut token never escapes
pem = '-----BEGIN ' + 'OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmU\nAAAAAAAAAAEAAAAz\n-----END ' + 'OPENSSH PRIVATE KEY-----\n'
path = io.save_unknown('claude', 'before\n' + pem + 'after\n')
body = open(path).read()
assert 'b3BlbnNzaC1rZXktdjEAAAAABG5vbmU' not in body and 'AAAAAAAAAAEAAAAz' not in body and 'before' in body and 'after' in body, body
cut = 'github_pat_' + 'B' * 20          # a token cut by the screen edge: prefix only
wrapped = 'github_pat_' + 'C' * 30 + '\n' + 'C' * 30
path = io.save_unknown('codex', 'x1\n' + cut + '\ny1\nkey ' + wrapped + '\nz1\n')
body = open(path).read()
assert 'github_pat_' not in body and 'C' * 30 not in body and 'x1' in body and 'z1' in body, body
unclosed = '-----BEGIN ' + 'RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA\n'
path = io.save_unknown('claude', 'top\n' + unclosed)
assert 'MIIEpAIBAAKCAQEA' not in open(path).read()
# H3: a key whose BEGIN scrolled off (only the body and END are shown)
body20 = ['K%02dx' % i + 'Q' * 60 for i in range(20)]
path = io.save_unknown('claude', '\n'.join(body20) + '\n-----END ' + 'RSA PRIVATE KEY-----\nafter the key\n')
saved = open(path).read()
assert not any(l in saved for l in body20) and 'after the key' in saved, saved
# H3: a BEGIN more than 60 lines above the end of the screen
body70 = ['L%02dy' % i + 'R' * 60 for i in range(70)]
path = io.save_unknown('claude', 'head\n-----BEGIN ' + 'OPENSSH PRIVATE KEY-----\n' + '\n'.join(body70) + '\n-----END ' + 'OPENSSH PRIVATE KEY-----\ntail line\n')
saved = open(path).read()
assert not any(l in saved for l in body70) and 'tail line' in saved, saved
# H3: the same, with the END not shown yet: only a check before the cut sees the BEGIN
open_key = io.save_unknown('claude', 'head2\n-----BEGIN ' + 'OPENSSH PRIVATE KEY-----\n' + '\n'.join(body70) + '\n')
assert open_key is None or not any(l in open(open_key).read() for l in body70)
# M4: the real launch log — per plan and hourly, private, junk tolerated
import time as _t
t = _t.time()
io.revive_note(t - 7200, 'P1'); io.revive_note(t - 30, 'P1'); io.revive_note(t - 10, 'P2')
assert sorted(io.revive_history('P1')) == [t - 7200, t - 30] and io.revive_history('P2') == [t - 10]
assert sorted(io.revive_history()) == [t - 30, t - 10], 'the hourly view keeps the last hour'
log = os.path.join(io.store.dir, H.REVIVE_LOG)
assert oct(os.stat(log).st_mode & 0o777) == '0o600'
H.write_private(log, '{"launches": [[1, "P1"], ["x", "P1"], [true, "P1"], [2, "../evil"], "junk"]}')
assert io.revive_history('P1') == [1.0], io.revive_history('P1')
H.write_private(log, 'not json')
assert io.revive_history('P1') == [] and io.revive_history() == []
# L8: a corpus directory with loose permissions is closed again
folder = os.path.dirname(path)
os.chmod(folder, 0o755)
io.save_unknown('claude', 'another odd screen\n')
assert oct(os.stat(folder).st_mode & 0o777) == '0o700'
print('ok')
PY
assert_eq "unknown screens: a sanitized, private, capped corpus, each screen once" "ok" "$OUT"

# --- the map's revived mark -------------------------------------------------------------------------
run python3 - "$R_SCRIPTS" <<'PY'
import json, sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_report, fleet_ui
row = {'plan': 'P1', 'class': 'open', 'lead': 'local:w9:p1', 'epoch': 2, 'succession': [], 'lanes': [],
       'repo_root': '/r', 'blocker_class': None, 'situation': None, 'tasks_done': 1, 'tasks_total': 3,
       'current_task': None, 'detail': None, 'progress': None, 'updated_at': None, 'revived': True}
doc = {'schema': fleet_report.FLEET_SCHEMA, 'daemon': {}, 'machines': [{'machine': 'local', 'label': 'Mac',
       'agents_state': 'ok', 'plans_state': 'ok', 'agents': [], 'plans': [row]}]}
assert fleet_report.valid_fleet(doc)
bad = json.loads(json.dumps(doc)); bad['machines'][0]['plans'][0]['revived'] = 'yes'
assert not fleet_report.valid_fleet(bad), 'revived is a boolean'
ix = fleet_ui.Index(doc)
text = '\n'.join(l.text() for l in fleet_ui.render_list(fleet_ui.build_view(ix, 'plan', '', 'all', time.time()), time.time(), 120))
assert '↻ revived' in text, text
assert fleet_report.lead_record({'record': {'schema': 'herdr-peers/lead-v1', 'plan': 'P1', 'lead': 'local:w9:p1',
    'epoch': 2, 'succession': [], 'lanes': [], 'updated_at': '2026-11-16T00:00:00Z'},
    'record_via': 'revive'})['revived'] is True
print('ok')
PY
assert_eq "the map marks a revived lead; fleet ui shows it" "ok" "$OUT"
