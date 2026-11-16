# shellcheck shell=bash
# Part of scope `autopilot` (sourced by autopilot.sh): the plan queue (.dwp/queue.json, dwp-queue-v1, written by the
# pack): the machine report reads it bounded and validated and judges each item
# (ready, approved — an approval with no amendment after it —, why it cannot
# start); the loop starts the next ready item by one fixed prompt to its lead,
# once, one at a time per repository, and reports items the human must fix.

Q_SCRIPTS="$ROOT/skills/herdr-peers/scripts"

run python3 - "$Q_SCRIPTS" <<'PY'
import json, os, sys, tempfile
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_report as F

def repo():
    base = tempfile.mkdtemp()
    os.makedirs(os.path.join(base, '.dwp', 'plans'))
    return base
import hashlib, subprocess
def cid_of(doc):
    return hashlib.sha256(json.dumps(doc, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
def plan(base, pid, status='pending', events=('approval',)):
    """A plan as the pack writes it: state, contract, markdown, and a journal
    whose 'approval' cites the live contract id and the markdown digest
    ('bare' is an approval line citing nothing)."""
    d = os.path.join(base, '.dwp', 'plans', pid)
    os.makedirs(d)
    json.dump({'status': status, 'blocked': None, 'checkpoint': None,
               'tasks': [{'id': 1, 'status': 'completed' if status == 'completed' else status}]},
              open(os.path.join(d, 'state.json'), 'w'))
    contract = {'plan': pid, 'title': 'T'}
    json.dump(contract, open(os.path.join(d, 'contract.json'), 'w'))
    open(os.path.join(d, 'README.md'), 'w').write('# %s\n' % pid)
    cid, digest = cid_of(contract), hashlib.sha256(('# %s\n' % pid).encode()).hexdigest()
    with open(os.path.join(d, 'journal.ndjson'), 'w') as fh:
        for n, t in enumerate(events):
            ev = {'seq': n + 1, 'type': 'approval' if t == 'bare' else t}
            if t == 'approval':
                ev.update(contract_id=cid, plan_digest=digest)
            fh.write(json.dumps(ev) + '\n')
    return d
def queue(base, items, **kw):
    json.dump(dict({'schema': 'dwp-queue-v1', 'items': items}, **kw),
              open(os.path.join(base, '.dwp', 'queue.json'), 'w'))
item = lambda p, **kw: dict({'plan': p, 'after': None, 'state': 'queued', 'lead': 'local:w1:p2', 'start': 'prompt-lead'}, **kw)

# no queue, an invalid queue, a symlink, an oversized queue
b = repo()
assert F.read_queue(b) == ('none', None)
for bad in ({'schema': 'other', 'items': []}, {'schema': 'dwp-queue-v1', 'items': 5},
            {'schema': 'dwp-queue-v1', 'items': [{'plan': '../x', 'state': 'queued'}]},
            {'schema': 'dwp-queue-v1', 'items': [{'plan': 'P1', 'state': 'running'}]},
            {'schema': 'dwp-queue-v1', 'items': [{'plan': 'P1', 'state': 'queued', 'lead': 'x y'}]},
            {'schema': 'dwp-queue-v1', 'items': [{'plan': 'P1', 'state': 'queued'}, {'plan': 'P1', 'state': 'queued'}]},
            {'schema': 'dwp-queue-v1', 'items': [], 'parallel': 'yes'},
            {'schema': 'dwp-queue-v1', 'items': [{'plan': 'P%d' % i, 'state': 'done'} for i in range(F.MAX_QUEUE_ITEMS + 1)]}):
    json.dump(bad, open(os.path.join(b, '.dwp', 'queue.json'), 'w'))
    assert F.read_queue(b)[0] == 'invalid', bad
queue(b, [{'plan': 'P%d' % i, 'state': 'done'} for i in range(F.MAX_QUEUE_ITEMS)])
assert F.read_queue(b)[0] != 'invalid', 'a queue of exactly the cap is read'
with open(os.path.join(b, '.dwp', 'queue.json'), 'w') as fh:
    fh.write('{"schema": "dwp-queue-v1", "items": []}' + ' ' * (F.MAX_QUEUE_BYTES + 1))
assert F.read_queue(b)[0] == 'invalid', 'oversized'
os.remove(os.path.join(b, '.dwp', 'queue.json'))
other = tempfile.mkdtemp(); json.dump({'schema': 'dwp-queue-v1', 'items': []}, open(os.path.join(other, 'q.json'), 'w'))
os.symlink(os.path.join(other, 'q.json'), os.path.join(b, '.dwp', 'queue.json'))
assert F.read_queue(b)[0] == 'invalid', 'a symlinked queue'

# judging items
b = repo()
plan(b, 'PLAN_1_now', 'in_progress'); plan(b, 'PLAN_2_next'); plan(b, 'PLAN_3_after')
queue(b, [item('PLAN_1_now', state='started'), item('PLAN_2_next'), item('PLAN_3_after', after='PLAN_2_next')])
st, q = F.read_queue(b)
items = dict((i['plan'], i) for i in q['items'])
assert not items['PLAN_2_next']['ready'] and items['PLAN_2_next']['blocked_reason'] == 'another plan of this repository is running'
assert items['PLAN_3_after']['blocked_reason'] == 'waiting for PLAN_2_next'
queue(b, [item('PLAN_1_now', state='started'), item('PLAN_2_next')], parallel=True)
assert F.read_queue(b)[1]['items'][1]['ready'], 'parallel lets the next start'
# the current plan completes: the next is ready
b = repo()
plan(b, 'PLAN_1_now', 'completed'); plan(b, 'PLAN_2_next')
queue(b, [item('PLAN_1_now', state='done'), item('PLAN_2_next', after='PLAN_1_now')])
nxt = F.read_queue(b)[1]['items'][1]
assert nxt['ready'] and nxt['approved'] is True and nxt['blocked_reason'] is None, nxt
# approval: none, an amendment after it, approved again, no journal
for events, want, reason in ((('approval', 'amendment'), False, 'not approved'), ((), False, 'not approved'),
                             (('approval', 'amendment', 'approval'), True, None)):
    b = repo(); plan(b, 'PLAN_2_next', events=events); queue(b, [item('PLAN_2_next')])
    it = F.read_queue(b)[1]['items'][0]
    assert it['approved'] is want and it['blocked_reason'] == reason, (events, it)
# the approval is bound to the plan as it is now (M2): a bare approval line, an edit of
# the plan after it, a new contract after it do not count; a stamped revision cited does
b = repo(); plan(b, 'PLAN_2_next', events=('bare',)); queue(b, [item('PLAN_2_next')])
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'not approved', 'a bare approval line'
b = repo(); d = plan(b, 'PLAN_2_next'); queue(b, [item('PLAN_2_next')])
assert F.read_queue(b)[1]['items'][0]['ready']
open(os.path.join(d, 'README.md'), 'a').write('edited after the approval\n')
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'not approved', 'markdown edited after the approval'
b = repo(); d = plan(b, 'PLAN_2_next'); queue(b, [item('PLAN_2_next')])
json.dump({'plan': 'PLAN_2_next', 'title': 'changed'}, open(os.path.join(d, 'contract.json'), 'w'))
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'not approved', 'contract changed after the approval'
b = repo(); d = plan(b, 'PLAN_2_next'); queue(b, [item('PLAN_2_next')])
ev = json.loads(open(os.path.join(d, 'journal.ndjson')).read().splitlines()[0])
with open(os.path.join(d, 'journal.ndjson'), 'a') as fh:
    fh.write(json.dumps(dict(ev, type='amendment', seq=2)) + '\n')   # cites the same contract and digest
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'not approved', 'an amendment after the approval'
b = repo(); d = plan(b, 'PLAN_2_next', events=()); queue(b, [item('PLAN_2_next')])
os.makedirs(os.path.join(d, 'contracts'))
# revision 10 sorts before revision 9 by name: the live one is the highest number
json.dump({'plan': 'PLAN_2_next', 'revision': 10, 'contract_id': 'r10'}, open(os.path.join(d, 'contracts', 'contract.r10.json'), 'w'))
json.dump({'plan': 'PLAN_2_next', 'revision': 9, 'contract_id': 'r9'}, open(os.path.join(d, 'contracts', 'contract.r9.json'), 'w'))
digest = hashlib.sha256(b'# PLAN_2_next\n').hexdigest()
with open(os.path.join(d, 'journal.ndjson'), 'w') as fh:
    fh.write(json.dumps({'type': 'approval', 'contract_id': 'r9', 'plan_digest': digest}) + '\n')
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'not approved', 'an approval of an older revision'
with open(os.path.join(d, 'journal.ndjson'), 'a') as fh:
    fh.write(json.dumps({'type': 'approval', 'contract_id': 'r10', 'plan_digest': digest}) + '\n')
assert F.read_queue(b)[1]['items'][0]['ready'], 'the live revision approved'
# the journal is read again only when it changed (L2)
path = os.path.join(d, 'journal.ndjson')
key, facts = F._JOURNALS[path]
F._JOURNALS[path] = (key, (None, False))
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'not approved', 'an unchanged journal comes from the cache'
with open(path, 'a') as fh:
    fh.write('\n')
assert F.read_queue(b)[1]['items'][0]['ready'], 'a changed journal is read again'
# a plan that began while the queue still says queued is in flight (M3): not
# prompted again (a daemon restart), and the next one waits for it
for how in ('state', 'journal'):
    b = repo(); d = plan(b, 'PLAN_2_next'); plan(b, 'PLAN_3_more')
    if how == 'state':
        json.dump({'status': 'in_progress', 'blocked': None, 'checkpoint': None,
                   'tasks': [{'id': 1, 'status': 'in_progress'}]}, open(os.path.join(d, 'state.json'), 'w'))
    else:
        with open(os.path.join(d, 'journal.ndjson'), 'a') as fh:
            fh.write(json.dumps({'type': 'task_start', 'task': 'T1'}) + '\n')
    queue(b, [item('PLAN_2_next'), item('PLAN_3_more', lead='local:w1:p3')])
    its = F.read_queue(b)[1]['items']
    assert not its[0]['ready'] and its[0]['blocked_reason'] == 'started, queue not updated', (how, its[0])
    assert its[1]['blocked_reason'] == 'another plan of this repository is running', (how, its[1])
# confinement (L1): a symlinked .dwp or plan directory leaves the repository
b = repo(); outside = repo(); plan(outside, 'PLAN_2_next'); queue(outside, [item('PLAN_2_next')])
os.rmdir(os.path.join(b, '.dwp', 'plans')); os.rmdir(os.path.join(b, '.dwp'))
os.symlink(os.path.join(outside, '.dwp'), os.path.join(b, '.dwp'))
assert F.read_queue(b)[0] == 'invalid', 'a symlinked .dwp'
b = repo(); queue(b, [item('PLAN_2_next')])
os.symlink(os.path.join(outside, '.dwp', 'plans', 'PLAN_2_next'), os.path.join(b, '.dwp', 'plans', 'PLAN_2_next'))
it = F.read_queue(b)[1]['items'][0]
assert not it['ready'] and it['approved'] is None, it
# the named lead must work in this repository and on no other open plan (M1)
def git_repo():
    r = os.path.realpath(tempfile.mkdtemp())
    subprocess.run(['git', 'init', '-q', r], check=True)
    os.makedirs(os.path.join(r, '.dwp', 'plans'))
    return r
a, other = git_repo(), git_repo()
plan(a, 'PLAN_2_next'); queue(a, [item('PLAN_2_next')])
def judged(cwd, plans=()):
    q = F.read_queue(a)[1]
    F.check_queue_leads(q, list(plans), {'w1:p2': cwd}, F.Git())
    return q['items'][0]
assert judged(a)['ready']
assert judged(other)['blocked_reason'] == 'lead works elsewhere'
busy = {'plan': 'PLAN_9_else', 'class': 'open', 'lead': 'local:w1:p7', 'succession': [], 'lanes': ['local:w1:p2']}
assert judged(a, [busy])['blocked_reason'] == 'lead busy with another plan'
assert judged(a, [dict(busy, **{'class': 'completed'})])['ready'], 'a finished plan holds nobody'
assert judged(a, [dict(busy, plan='repo/PLAN_2_next')])['ready'], 'its own plan'
b = repo(); plan(b, 'PLAN_2_next'); os.remove(os.path.join(b, '.dwp/plans/PLAN_2_next/journal.ndjson'))
queue(b, [item('PLAN_2_next')])
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'approval not readable'
# launch items and items without a lead are not started
b = repo(); plan(b, 'PLAN_2_next'); queue(b, [item('PLAN_2_next', start='launch')])
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'launch is not available yet'
b = repo(); plan(b, 'PLAN_2_next'); queue(b, [item('PLAN_2_next', lead=None)])
assert F.read_queue(b)[1]['items'][0]['blocked_reason'] == 'no lead named'
# the report carries queues and validates them
rep = F.report({}, root=tempfile.mkdtemp())
assert rep['queues'] == [] and F.valid_report(rep)
bad = dict(rep, queues=[{'repo_root': '/r', 'items': [{'plan': 'P', 'state': 'queued', 'start': 'x', 'ready': True}]}])
assert not F.valid_report(bad)
print('ok')
PY
assert_rc "queues are read bounded, validated and each item judged" 0
assert_eq "(scripted queue checks ran to their end)" "ok" "$OUT"

# --- the loop starts the next ready item ------------------------------------------------------
run python3 - "$Q_SCRIPTS" <<'PY'
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import autopilot
now = [1000.0]
class IO(object):
    self_machine = None
    def __init__(self): self.rows, self.report, self.sent, self.events, self.log, self.screens = [], None, [], [], [], {}
    def sources(self): return ['local']
    def agents(self, m): return [dict(r) for r in self.rows]
    def read(self, m, p): return self.screens.get(p, '')
    def state(self, m, p): return 'idle'
    def keys(self, *a): return True
    def prompt(self, m, p, t): self.sent.append((p, t)); return True
    def record(self, addr, kind, choice, outcome, dry, plan=None): self.log.append((outcome, choice.cls, plan))
    def warn(self, a, e): raise e
    def label(self, m): return m
    def identity(self): return {}
    def plans(self, m, panes, f): return 'ok', self.report
    def save_fleet(self, t): self.saved = t
    def load_fleet(self): return None
    def event(self, e, dry): self.events.append((e['event'], e['plan']))
row = lambda pane, state='idle': {'pane': pane, 'state': state, 'agent': 'claude', 'seq': 1, 'turn': 1, 'you': False, 'cwd': '/r'}
qi = lambda p, ready=True, reason=None, state='queued', lead='local:w1:p2': {'plan': p, 'after': None, 'state': state, 'lead': lead, 'start': 'prompt-lead', 'class': 'open', 'approved': True, 'ready': ready, 'blocked_reason': reason}
def fresh(**kw):
    io = IO()
    return io, autopilot.Autopilot(io, clock=lambda: now[0], sleep=lambda s: None, confirm=0, loop=True, grace=0, **kw)
def step(ap, s=400):
    now[0] += s; ap.run_pass()
io, ap = fresh()
io.rows = [row('w1:p2'), row('w1:p3')]
io.report = {'plans': [], 'agents': [], 'queues': [{'repo_root': '/r', 'parallel': False, 'items': [
    qi('PLAN_2_next'), qi('PLAN_3_more', lead='local:w1:p3')]}]}
ap.run_pass(); step(ap); step(ap)
assert io.sent == [('w1:p2', autopilot.QUEUE_TEXT % ('PLAN_2_next', '/r'))], io.sent
assert io.events == [('plan_queued_started', 'PLAN_2_next')], io.events
assert ("Plan PLAN_2_next is next in the queue of the repository at /r and approved. In that repository, run "
        "the plan tool's execute flow for it (its start gate checks the approval again) and execute it to its "
        "end, respecting its gates.") == autopilot.QUEUE_TEXT % ('PLAN_2_next', '/r')
# parallel: both start
io, ap = fresh()
io.rows = [row('w1:p2'), row('w1:p3')]
io.report = {'plans': [], 'agents': [], 'queues': [{'repo_root': '/r', 'parallel': True, 'items': [
    qi('PLAN_2_next'), qi('PLAN_3_more', lead='local:w1:p3')]}]}
ap.run_pass()
assert sorted(p for p, t in io.sent) == ['w1:p2', 'w1:p3'], io.sent
# a busy lead, a draft: no prompt yet; it starts when the lead is free
io, ap = fresh()
io.rows = [row('w1:p2', 'working')]
io.report = {'plans': [], 'agents': [], 'queues': [{'repo_root': '/r', 'parallel': False, 'items': [qi('PLAN_2_next')]}]}
ap.run_pass()
assert io.sent == []
io.rows = [row('w1:p2')]
step(ap)
assert len(io.sent) == 1
# blocked items: reported once per reason, never prompted
io, ap = fresh()
io.rows = [row('w1:p2')]
io.report = {'plans': [], 'agents': [], 'queues': [{'repo_root': '/r', 'parallel': False, 'items': [
    qi('PLAN_2_next', ready=False, reason='not approved')]}]}
ap.run_pass(); step(ap); step(ap)
assert io.sent == [] and io.events == [('queue_blocked', 'PLAN_2_next')], (io.sent, io.events)
io.report['queues'][0]['items'][0]['blocked_reason'] = 'no lead named'
step(ap)
assert io.events.count(('queue_blocked', 'PLAN_2_next')) == 2, 'a new reason is reported again'
io.report['queues'][0]['items'][0]['blocked_reason'] = 'waiting for PLAN_1_now'
step(ap)
assert io.events.count(('queue_blocked', 'PLAN_2_next')) == 2, 'waiting is not a block'
# dry run and --no-nudge send nothing
for kw in ({'dry_run': True}, {'nudge': False}):
    io, ap = fresh(**kw)
    io.rows = [row('w1:p2')]
    io.report = {'plans': [], 'agents': [], 'queues': [{'repo_root': '/r', 'parallel': False, 'items': [qi('PLAN_2_next')]}]}
    ap.run_pass()
    assert io.sent == [], kw
# the map carries the queue without plan content
io, ap = fresh()
io.rows = [row('w1:p2')]
io.report = {'plans': [], 'agents': [], 'queues': [{'repo_root': '/r', 'parallel': False, 'items': [qi('PLAN_2_next')]}]}
ap.run_pass()
import json
m = json.loads(io.saved)['machines'][0]
assert m['queues'][0]['items'][0] == {'plan': 'PLAN_2_next', 'state': 'queued', 'after': None, 'lead': 'local:w1:p2', 'ready': True, 'blocked_reason': None}, m['queues']
# a daemon restart between two passes: the lead began the plan but the queue still
# says queued; the new daemon does not prompt it again (prompted once in all)
import hashlib, os, tempfile
import fleet_report as F
base = tempfile.mkdtemp(); d = os.path.join(base, '.dwp', 'plans', 'PLAN_2_next'); os.makedirs(d)
contract = {'plan': 'PLAN_2_next'}
json.dump(contract, open(os.path.join(d, 'contract.json'), 'w')); open(os.path.join(d, 'PLAN.md'), 'w').write('# P\n')
json.dump({'status': 'pending', 'tasks': [{'id': 1, 'status': 'pending'}]}, open(os.path.join(d, 'state.json'), 'w'))
open(os.path.join(d, 'journal.ndjson'), 'w').write(json.dumps({'type': 'approval', 'plan_digest': hashlib.sha256(b'# P\n').hexdigest(),
    'contract_id': hashlib.sha256(json.dumps(contract, sort_keys=True, separators=(',', ':')).encode()).hexdigest()}) + '\n')
json.dump({'schema': 'dwp-queue-v1', 'items': [{'plan': 'PLAN_2_next', 'state': 'queued', 'lead': 'local:w1:p2'}]},
          open(os.path.join(base, '.dwp', 'queue.json'), 'w'))
sent = []
for restart in range(2):
    io, ap = fresh()
    io.rows = [row('w1:p2')]
    io.report = {'plans': [], 'agents': [], 'queues': [F.read_queue(base)[1]]}
    ap.run_pass(); step(ap)
    sent += io.sent
    json.dump({'status': 'in_progress', 'tasks': [{'id': 1, 'status': 'in_progress'}]}, open(os.path.join(d, 'state.json'), 'w'))
assert len(sent) == 1, sent
print('ok')
PY
assert_rc "the loop starts the next ready item once, one at a time, and reports blocked items" 0
assert_eq "(scripted queue loop checks ran to their end)" "ok" "$OUT"
