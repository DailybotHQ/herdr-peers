# shellcheck shell=bash
# Scope `fleet_ui`: the live watcher `herdr-peers fleet ui` — its pure model
# (grouping by plan, repository and machine; counts; the age of the picture;
# filtering; sorting plans that need the developer first; the idle group),
# its rendering (width, wide characters, neutralised text), the application
# driven through a fake terminal (keys, mouse, map changes, stale map, small
# terminal, plan and agent views, the live screen and focus with fixed argv),
# the text snapshot, and its performance budget.

UI_SCRIPTS="$ROOT/skills/herdr-peers/scripts"

run python3 - "$UI_SCRIPTS" <<'PY'
import json, os, sys, tempfile, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_ui as ui

NOW = 2_000_000_000.0
def ts(ago): return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(NOW - ago))

def agent(pane, state='idle', kind='claude', repo='/src/app', branch='main', title='', plans=(), since=60):
    return {'pane': pane, 'kind': kind, 'state': state, 'cwd': repo or '/tmp', 'repo_root': repo,
            'branch': branch, 'title': title, 'state_since': ts(since),
            'plans': [{'plan': p, 'role': r} for p, r in plans]}

def plan(pid, cls='open', lead='local:w1:p1', situation=None, done=1, total=4, current='Write the parser',
         detail=True):
    d = None
    if detail:
        d = {'title': 'Ship %s' % pid, 'tasks_from': 0, 'blocker': None,
             'tasks': [{'id': 'T-%d' % i, 'title': 'task %d' % i,
                        'status': 'completed' if i < done else ('in_progress' if i == done else 'pending')}
                       for i in range(total)],
             'summary': ['Goal: ship it', 'Next action: tests'], 'summary_at': ts(120)}
    return {'plan': pid, 'class': cls, 'lead': lead, 'epoch': 1, 'succession': [], 'lanes': [],
            'repo_root': '/src/app', 'blocker_class': None, 'situation': situation,
            'tasks_done': done, 'tasks_total': total, 'current_task': {'id': 'T-%d' % done, 'title': current},
            'detail': d}

FLEET = {'schema': 'herdr-peers/fleet-v1', 'generated_at': ts(30),
         'daemon': {'pane': 'w9:p9', 'local_is': None, 'server': 'abc'},
         'machines': [
    {'machine': 'local', 'label': 'Mac', 'agents_state': 'ok', 'plans_state': 'ok',
     'agents': [agent('w1:p1', 'working', plans=[('PLAN_1_api', 'lead')], title='Refactor the API'),
                agent('w1:p2', 'idle', 'codex', plans=[('PLAN_1_api', 'lane')]),
                agent('w1:p3', 'blocked', plans=[('PLAN_2_web', 'lead')], repo='/src/web'),
                agent('w1:p4', 'idle', repo='/src/web'),
                agent('w1:p5', 'working', 'grok', repo=None, branch=None)],
     'plans': [plan('PLAN_1_api'), plan('PLAN_2_web', 'blocked', 'local:w1:p3', 'plan_blocked'),
               plan('PLAN_3_old', 'completed', None, None, 4, 4, None, False)]},
    {'machine': 'm2', 'label': 'API · WS brain', 'agents_state': 'ok', 'plans_state': 'ok',
     'agents': [agent('w2:p1', 'idle', repo='/app', plans=[('PLAN_9_box', 'lead')])],
     'plans': [plan('PLAN_9_box', 'open', 'local:w2:p1', 'plan_stalled')]},
    {'machine': 'm3', 'label': 'XWin', 'agents_state': 'unknown', 'plans_state': 'unknown',
     'agents': [], 'plans': []}]}

# --- age phrases at their boundaries
assert ui.age_phrase(None) == 'never'
assert [ui.age_phrase(s) for s in (0, 9, 10, 59, 60, 179, 3599, 3600, 3660, 90000)] == \
    ['just now', 'just now', '10 s ago', '59 s ago', '1 min ago', '2 min ago', '59 min ago',
     '1 h 00 min ago', '1 h 01 min ago', '1 d ago'], 'age phrases'

# --- the index and the counts
ix = ui.Index(FLEET)
counts, plans, answering = ix.counts()
assert counts == {'working': 2, 'waiting': 1, 'idle': 3, 'unknown': 0}, counts
assert plans == {'open': 1, 'needs_you': 2, 'completed': 1}, plans
assert answering == 2 and len(ix.machines) == 3
assert [(r, a.pane) for r, a in ix.plan_by_key['local/PLAN_1_api'].members] == [('lead', 'w1:p1'), ('lane', 'w1:p2')]

# --- grouping by plan: needing the developer first, then running; outside plans; doing nothing
g = ui.build_view(ix, 'plan', facet='all')
names = [x.title for x in g]
assert set(names[:2]) == {'PLAN_2_web', 'PLAN_9_box'} and names[2] == 'PLAN_1_api', names
assert 'PLAN_3_old' in names, 'All shows a finished plan'
assert 'PLAN_3_old' not in [x.title for x in ui.build_view(ix, 'plan')], 'the default view never shows Done'
busy = [x for x in g if x.kind == 'busy'][0]
idle = [x for x in g if x.kind == 'idle'][0]
assert [a.pane for _, a in busy.members] == ['w1:p5'], busy.members
assert [a.pane for _, a in idle.members] == ['w1:p4'], 'the agents doing nothing have their own group'
# by repository and by machine
r = ui.build_view(ix, 'repo', facet='all')
assert [x.title for x in r] == ['app', 'app', 'web', '(no repository)'], [x.title for x in r]
m = ui.build_view(ix, 'machine', facet='all')
assert [x.title for x in m] == ['Mac', 'API · WS brain', 'XWin'] and m[2].subtitle == 'unreachable'
# filtering
f = ui.build_view(ix, 'plan', 'codex')
assert [x.title for x in f] == ['PLAN_1_api'] and [a.pane for _, a in f[0].members] == ['w1:p2'], f
assert ui.build_view(ix, 'plan', 'nothing-matches') == []
assert [x.title for x in ui.build_view(ix, 'plan', 'ws brain')] == ['PLAN_9_box']

# --- rendering: exact width, no control characters, wide characters counted
hostile = json.loads(json.dumps(FLEET))
hostile['machines'][0]['agents'][0]['title'] = 'evil\x1b[2J\x07‮ title 漢字漢字漢字 ' + 'x' * 400
hostile['machines'][0]['plans'][0]['detail']['summary'] = ['line\x1b]0;pwn\x07 end']
hx = ui.Index(hostile)
for width in (60, 100, 200):
    lines = ui.render_list(ui.build_view(hx, 'plan'), NOW, width)
    lines += ui.render_header(hx, 30, 'plan', 'x', width)
    lines += ui.render_plan(hx.plan_by_key['local/PLAN_1_api'], NOW, width)
    lines += ui.render_agent(hx.by_key['local:w1:p1'], hx, NOW, width, ['screen\x1b[31m line'], 'live')
    lines += ui.render_help(width)
    for line in lines:
        text = line.text()
        assert ui.width_of(text) == width, (width, ui.width_of(text), text)
        assert not any(ord(c) < 32 or 0x7f <= ord(c) <= 0x9f or c in '‮​' for c in text), repr(text)
assert ui.fit('漢字漢字', 5) == '漢字…' and ui.width_of(ui.fit('漢字漢字', 5)) == 5

# --- the plan view tells how a plan is going
pv = '\n'.join(l.text() for l in ui.render_plan(ix.plan_by_key['local/PLAN_1_api'], NOW, 120))
for want in ('Ship PLAN_1_api', '1 / 4 tasks', 'Now      Write the parser', '▶ T-1', 'Group (2)',
             'Summary', 'Next action: tests', 'written 2 min ago'):
    assert want in pv, (want, pv)

# --- snapshot text
path = os.path.join(tempfile.mkdtemp(), 'fleet.json')
json.dump(FLEET, open(path, 'w'))
os.utime(path, (NOW - 45, NOW - 45))
snap = ui.snapshot(ui.FileSource(path), NOW, 100)
assert 'updated 45 s ago' in snap and 'PLAN_2_web' in snap and 'Doing nothing' not in snap, snap
assert 'Doing nothing' in ui.snapshot(ui.FileSource(path), NOW, 100, 'plan', 'waiting')
assert '2 need you' in snap and '1 / 4 tasks' in snap, snap
os.utime(path, (NOW - 1000, NOW - 1000))
assert 'STALE' in ui.snapshot(ui.FileSource(path), NOW, 100)
assert 'no map on this machine' in ui.snapshot(ui.FileSource(path + '.none'), NOW, 100)

# --- performance: 1000 agents indexed, grouped and rendered within budget
big = {'schema': 'herdr-peers/fleet-v1', 'daemon': {}, 'machines': []}
for mi in range(20):
    agents = [agent('w%d:p%d' % (mi, i), ('working', 'idle', 'blocked')[i % 3], repo='/src/r%d' % (i % 7),
                    plans=[('PLAN_%d_x' % (i % 10), 'lane' if i % 10 else 'lead')]) for i in range(50)]
    big['machines'].append({'machine': 'm%d' % mi, 'label': 'box %d' % mi, 'agents_state': 'ok',
                            'plans_state': 'ok', 'agents': agents,
                            'plans': [plan('PLAN_%d_x' % k) for k in range(10)]})
t = time.perf_counter()
bx = ui.Index(big)
lines = ui.render_list(ui.build_view(bx, 'plan'), NOW, 160)
spent = time.perf_counter() - t
assert len(bx.agents) == 1000 and spent < 0.5, spent
t = time.perf_counter()
for grouping in ('repo', 'machine'):
    ui.render_list(ui.build_view(bx, grouping, 'box 1'), NOW, 160)
assert time.perf_counter() - t < 0.5
print('ok %.0f ms for 1000 agents' % (spent * 1000))
PY
assert_rc "the model, the rendering and the snapshot hold" 0
assert_contains "(scripted model checks ran to their end)" "$OUT" "ok "

# --- the application through a fake terminal ------------------------------------------------
run python3 - "$UI_SCRIPTS" <<'PY'
import json, os, sys, tempfile, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_ui as ui

class Term(object):
    def __init__(self, keys, w=120, h=40):
        self.keys, self.w, self.h = list(keys), w, h
        self.rows, self.mouse, self.flushes = {}, None, 0
    def size(self): return self.w, self.h
    def clear(self): self.rows = {}
    def draw(self, y, line): self.rows[y] = line
    def flush(self): self.flushes += 1
    def read_key(self, timeout):
        clock[0] += timeout
        if not self.keys:
            return 'q'
        k = self.keys.pop(0)
        if callable(k):
            return k()
        if isinstance(k, tuple):
            self.mouse = k
            return 'mouse'
        return k
    def last_mouse(self): return self.mouse
    def screen(self): return '\n'.join(self.rows[y].text() for y in sorted(self.rows))
    def find(self, text):
        for y in sorted(self.rows):
            if text in self.rows[y].text():
                return y
        raise AssertionError('%r not on screen:\n%s' % (text, self.screen()))

class Link(object):
    calls = []
    def __init__(self, fleet): pass
    def target(self, machine): return [] if machine == 'local' else None
    def read(self, machine, pane):
        Link.calls.append(('read', machine, pane, clock[0]))
        return ['$ make test', 'ok \x1b[32m42 passed']
    def focus(self, machine, pane):
        Link.calls.append(('focus', machine, pane)); return True

clock = [2_000_000_000.0]
def map_file(fleet, ago=20):
    path = os.path.join(tempfile.mkdtemp(), 'fleet.json')
    json.dump(fleet, open(path, 'w'))
    os.utime(path, (clock[0] - ago, clock[0] - ago))
    return path

def fleet(extra_agent=False, title='Refactor the API'):
    agents = [{'pane': 'w1:p1', 'kind': 'claude', 'state': 'working', 'cwd': '/src/app', 'repo_root': '/src/app',
               'branch': 'main', 'title': title, 'state_since': None, 'plans': [{'plan': 'PLAN_1_api', 'role': 'lead'}]},
              {'pane': 'w1:p4', 'kind': 'codex', 'state': 'idle', 'cwd': '/src/web', 'repo_root': '/src/web',
               'branch': 'dev', 'title': '', 'state_since': None, 'plans': []}]
    if extra_agent:
        agents.insert(0, {'pane': 'w1:p0', 'kind': 'grok', 'state': 'working', 'cwd': '/x', 'repo_root': None,
                          'branch': None, 'title': 'new', 'state_since': None, 'plans': []})
    return {'schema': 'herdr-peers/fleet-v1', 'generated_at': '2033-05-18T03:33:00Z', 'daemon': {},
            'machines': [{'machine': 'local', 'label': 'Mac', 'agents_state': 'ok', 'plans_state': 'ok',
                          'agents': agents,
                          'plans': [{'plan': 'PLAN_1_api', 'class': 'open', 'lead': 'local:w1:p1', 'epoch': 1,
                                     'succession': [], 'lanes': [], 'repo_root': '/src/app', 'blocker_class': None,
                                     'situation': None, 'tasks_done': 2, 'tasks_total': 5,
                                     'current_task': {'id': 'T-3', 'title': 'Write tests'},
                                     'detail': {'title': 'API refactor', 'tasks_from': 0, 'blocker': None,
                                                'tasks': [{'id': 'T-3', 'title': 'Write tests', 'status': 'in_progress'}],
                                                'summary': ['Next: tests'], 'summary_at': None}}]}]}

def app(keys, path, **kw):
    term = Term(keys, **kw)
    a = ui.App(term, ui.FileSource(path), link_factory=Link, clock=lambda: clock[0])
    return a, term

path = map_file(fleet())
# header, tabs, groups, footer
a, t = app(['q'], path); a.run()
s = t.screen()
for want in ('herdr-peers fleet', 'updated 20 s ago', '1 working', '1 idle', 'Plans', 'Repos', 'Machines',
             'PLAN_1_api', '2/5', 'now: Write tests', 'Attention 0', 'Active 1', 'q quit'):
    assert want in s, (want, s)
assert 'API refactor' in s
# switch grouping
a, t = app(['r', 'q'], path); a.run()
assert a.grouping == 'repo' and 'app' in t.screen() and '▤ web' not in t.screen(), 'by default only who needs you or moves'
a, t = app(['r', '5', 'q'], path); a.run()
assert 'app' in t.screen() and '▤ web' in t.screen()
a, t = app(['m', 'q'], path); a.run()
assert a.grouping == 'machine' and '▣ Mac' in t.screen()
a, t = app(['u', 'q'], path); a.run()
assert a.grouping == 'queue' and 'u Queues' in t.screen()
# move and open a plan, then back
a, t = app(['enter', 'q'], path); a.run()
assert a.mode == 'plan' and 'Progress' in t.screen() and 'Next: tests' in t.screen(), t.screen()
a, t = app(['enter', 'esc', 'q'], path); a.run()
assert a.mode == 'list'
# filter
a, t = app(['/', 'c', 'o', 'd', 'e', 'x', 'enter', 'q'], path); a.run()
assert a.needle == 'codex' and 'filter: codex' in t.screen() and 'PLAN_1_api' not in t.screen()
a, t = app(['/', 'z', 'esc', 'q'], path); a.run()
assert a.needle == ''
# help
a, t = app(['?', 'q'], path); a.run()
assert a.mode == 'help' and 'group by plan' in t.screen()
# a click selects; a click on the selected row opens it
a, t = app(['5', 'q'], path); a.run()
y = t.find('w1:p4')
a, t = app(['5', (5, y, 'click'), 'q'], path); a.run()
assert a.sel_target == ('agent', 'local:w1:p4'), a.sel_target
a, t = app(['5', (5, y, 'click'), (5, y, 'click'), 'q'], path); a.run()
assert a.mode == 'agent' and a.target == ('agent', 'local:w1:p4')
# the agent view reads the live screen only while open, at most every 2 s, and focuses on f
Link.calls = []
a, t = app(['down', 'enter', None, None, None, 'f', 'esc', None, None, 'q'], path); a.run()
reads = [c for c in Link.calls if c[0] == 'read']
assert reads and all(c[2] == 'w1:p1' for c in reads), Link.calls
times = [c[3] for c in reads]
assert all(b - a_ >= ui.SCREEN_EVERY for a_, b in zip(times, times[1:])), times
assert ('focus', 'local', 'w1:p1') in Link.calls
assert 'make test' in t.screen() or a.mode == 'list'
# a changed map redraws and keeps the selection on the same agent
p2 = map_file(fleet())
def change():
    new = fleet(extra_agent=True, title='Now on the docs')
    # A plan that needs the developer arrives: it sorts first and shifts every row.
    new['machines'][0]['plans'].insert(0, dict(new['machines'][0]['plans'][0], plan='PLAN_0_urgent',
                                               situation='plan_stalled', lead=None))
    json.dump(new, open(p2, 'w'))
    os.utime(p2, (clock[0], clock[0]))
    return None
a, t = app(['down', change, None, 'q'], p2); a.run()
assert a.sel_target == ('agent', 'local:w1:p1'), a.sel_target
assert a.lines[a.sel].target == ('agent', 'local:w1:p1') and a.sel > 3, (a.sel, 'the row moved, the selection followed')
assert 'Now on the docs' in t.screen() and 'just now' in t.screen() and 'PLAN_0_urgent' in t.screen(), t.screen()
# a stale map
a, t = app(['q'], map_file(fleet(), ago=2000)); a.run()
assert 'STALE' in t.screen()
# no map
a, t = app(['q'], path + '.missing'); a.run()
assert 'no map on this machine yet' in t.screen()
# a tiny terminal
a, t = app(['q'], path, w=40, h=10); a.run()
assert 'too small' in t.screen()
# the header clock ticks without the map changing; the body is not redrawn every tick
fresh_map = map_file(fleet())
a, t = app([None, None, None, 'q'], fresh_map); a.run()
assert 'updated 23 s ago' in t.screen(), t.screen().splitlines()[0]
assert t.flushes >= 4, 'the header is redrawn every tick'

# HerdrLink: fixed argv, nothing without Herdr, nothing unreachable
seen = []
class P(object):
    def __init__(self, rc, out=b''): self.returncode, self.stdout = rc, out
def fake_run(argv, **kw):
    seen.append(argv)
    if argv[1:3] == ['machine', 'list']:
        return P(0, json.dumps([{'id': 'm2', 'enabled': True}, {'id': '-bad', 'enabled': True}]).encode())
    return P(0, b'line \x1b[31mred\n')
link = ui.HerdrLink({'daemon': {'server': 'S1', 'local_is': 'm1'}}, run=fake_run,
                    environ={'HERDR_ENV': '1', 'HERDR_PEERS_UI_SERVER': 'S1'})
assert link.read('local', 'w1:p1') == ['line [31mred']
assert seen[-1] == ['herdr', 'pane', 'read', 'w1:p1', '--source', 'recent', '--lines', '20'], seen[-1]
assert link.focus('m2', 'w2:p2') and seen[-1] == ['herdr', '--machine', 'm2', 'agent', 'focus', 'w2:p2']
n = len(seen)
assert link.read('m9', 'w1:p1') is None and link.read('m2', 'w1:p1; rm') is None and len(seen) == n
away = ui.HerdrLink({'daemon': {'server': 'S1', 'local_is': 'm2'}}, run=fake_run,
                    environ={'HERDR_ENV': '1', 'HERDR_PEERS_UI_SERVER': 'S2'})
away.read('local', 'w1:p1')
assert seen[-1][:3] == ['herdr', '--machine', 'm2'], 'from another server, local is the daemon\'s machine id'
none = ui.HerdrLink({}, run=fake_run, environ={})
assert none.read('local', 'w1:p1') is None and none.target('local') is None
print('ok')
PY
assert_rc "the watcher's keys, mouse, map changes, views and Herdr calls hold" 0
assert_eq "(scripted app checks ran to their end)" "ok" "$OUT"

# --- through the helper -------------------------------------------------------------------------
new_world fleet_ui
UI_XDG_STATE=$XDG_STATE_HOME
export XDG_STATE_HOME="$WORLD/xdg-state"   # a state root of its own: no map from other scopes
run "$HELPER" fleet ui --snapshot
assert_rc "fleet ui --snapshot without a map exits 0" 0
assert_contains "and says how to get one" "$OUT" "no map on this machine yet"
mkdir -p "$XDG_STATE_HOME/herdr-peers"
python3 - "$XDG_STATE_HOME/herdr-peers/fleet.json" <<'PY'
import json, sys
json.dump({'schema': 'herdr-peers/fleet-v1', 'generated_at': '2026-01-01T00:00:00Z', 'daemon': {},
           'machines': [{'machine': 'local', 'label': 'Mac', 'agents_state': 'ok', 'plans_state': 'ok',
                         'agents': [{'pane': 'w1:p1', 'kind': 'claude', 'state': 'idle', 'cwd': '/a',
                                     'repo_root': '/a', 'branch': 'main', 'title': 't', 'state_since': None,
                                     'plans': []}], 'plans': []}]}, open(sys.argv[1], 'w'))
PY
run "$HELPER" fleet ui --width 90
assert_rc "fleet ui without a terminal prints a snapshot" 0
assert_contains "of the map: the default view says why it is empty" "$OUT" "Nothing needs you and nothing is moving"
assert_contains "and where the free agent is" "$OUT" "1 free agent under Waiting"
assert_eq "at the asked width" "90" "$(printf '%s\n' "$OUT" | sed -n 5p | python3 -c 'import sys,unicodedata; t=sys.stdin.read().rstrip("\n"); print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in t))' 2>/dev/null || echo "?")"
run "$HELPER" fleet ui --snapshot --width 10
assert_rc "an absurd width is a usage error" 2
run "$HELPER" fleet ui --snapshot --group machine --filter all
assert_contains "--group machine groups by machine" "$OUT" "▣ Mac"
run "$HELPER" fleet ui --snapshot --filter waiting
assert_rc "--filter waiting" 0
assert_contains "--filter waiting shows the free agents" "$OUT" "Doing nothing"
assert_contains "and marks the view it shows" "$OUT" "Waiting 0"
run "$HELPER" fleet ui --snapshot --filter nope
assert_rc "an unknown --filter is a usage error" 2

# --- a malformed or hostile map never takes the watcher down ------------------------------------
run python3 - "$UI_SCRIPTS" <<'PY'
import json, os, sys, tempfile, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_ui as ui
def base():
    return {'schema': 'herdr-peers/fleet-v1', 'daemon': {}, 'machines': [{
        'machine': 'local', 'label': 'Mac', 'agents': [{'pane': 'w1:p1', 'plans': []}],
        'plans': [{'plan': 'P', 'class': 'open', 'detail': {
            'title': 't', 'tasks': [{'id': '1', 'title': 'x', 'status': 'pending'}], 'summary': [],
            'summary_at': None, 'blocker': None, 'tasks_from': 0}}]}]}
def write(doc):
    path = os.path.join(tempfile.mkdtemp(), 'fleet.json')
    json.dump(doc, open(path, 'w'))
    return path
cases = {}
b = base(); b['machines'][0]['agents'] = 5; cases['agents is a number'] = b
b = base(); b['machines'][0]['plans'] = 7; cases['plans is a number'] = b
b = base(); b['machines'][0]['machine'] = ['x']; cases['an unhashable machine'] = b
b = base(); b['machines'][0]['agents'][0]['plans'] = 3; cases['agent roles is a number'] = b
b = base(); b['machines'][0]['plans'][0]['detail']['tasks'] = [{'status': ['x']}]; cases['an unhashable task status'] = b
b = base(); b['machines'][0]['plans'][0]['detail']['summary'] = [1, 2]; cases['a summary of numbers'] = b
for name, doc in cases.items():
    out = ui.snapshot(ui.FileSource(write(doc)), time.time(), 100)
    assert 'map unreadable' in out, (name, out[:200])
# the live app keeps running on such a map
class Term(object):
    keys = ['q']
    def size(self): return 120, 40
    def clear(self): pass
    def draw(self, y, line): self.last = line
    def flush(self): pass
    def read_key(self, t): return self.keys.pop(0) if self.keys else 'q'
    def last_mouse(self): return None
app = ui.App(Term(), ui.FileSource(write(cases['agents is a number'])), link_factory=lambda f: None)
assert app.run() == 0
# a symlink and an oversized file are refused
good = write(base())
link = good + '.link'
os.symlink(good, link)
assert 'map unreadable' in ui.snapshot(ui.FileSource(link), time.time(), 100), 'a symlinked map is refused'
big = os.path.join(tempfile.mkdtemp(), 'fleet.json')
with open(big, 'w') as fh:
    fh.write(' ' * (ui.MAX_MAP_BYTES + 10))
assert 'map unreadable' in ui.snapshot(ui.FileSource(big), time.time(), 100), 'an oversized map is refused'
assert 'map unreadable' not in ui.snapshot(ui.FileSource(good), time.time(), 100)
# format characters never reach the screen
dirty = 'a؜b­c\U000E0041d‮e​f'
assert ui.clean(dirty) == 'a b c d e f', repr(ui.clean(dirty))
print('ok')
PY
assert_eq "malformed maps, symlinks, oversized files and format characters are handled" "ok" "$OUT"

# One validator for the map (issue #44): what `fleet ui` refuses is never
# written by the daemon, nor read by `fleet`.
bad_map='{"schema":"herdr-peers/fleet-v1","machines":[{"machine":"m","agents":5}]}'
out=$(python3 - "$ROOT/skills/herdr-peers/scripts" "$WORK" "$bad_map" <<'PY'
import os, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_report, fleet_ui
root, text = sys.argv[2], sys.argv[3]
print(fleet_ui.valid_fleet is fleet_report.valid_fleet,
      fleet_report.store_fleet(root, text),
      os.path.exists(os.path.join(root, fleet_report.FLEET_FILE)))
open(os.path.join(root, fleet_report.FLEET_FILE), 'w').write(text)
print(fleet_report.read_fleet(root)[0])
PY
)
assert_eq "one validator: the UI's, the writer's and the reader's are the same function" "True failed False
None" "$out"

# --- the plan queues --------------------------------------------------------------------------------
run python3 - "$UI_SCRIPTS" <<'PY'
import sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_ui as ui, fleet_report
fleet = {'schema': 'herdr-peers/fleet-v1', 'daemon': {}, 'machines': [{
    'machine': 'local', 'label': 'Mac', 'agents_state': 'ok', 'plans_state': 'ok', 'agents': [],
    'plans': [{'plan': 'PLAN_2_next', 'class': 'open', 'lead': 'local:w1:p2', 'tasks_done': 0, 'tasks_total': 3}],
    'queues': [{'repo_root': '/src/app', 'parallel': False, 'invalid': False, 'items': [
        {'plan': 'PLAN_1_now', 'state': 'done', 'after': None, 'lead': None, 'ready': False, 'blocked_reason': None},
        {'plan': 'PLAN_2_next', 'state': 'queued', 'after': 'PLAN_1_now', 'lead': 'local:w1:p2', 'ready': True, 'blocked_reason': None},
        {'plan': 'PLAN_3_later', 'state': 'queued', 'after': None, 'lead': None, 'ready': False, 'blocked_reason': 'no lead named'}]}]}]}
assert fleet_report.valid_fleet(fleet)
ix = ui.Index(fleet)
view = ui.build_view(ix, 'queue', facet='all')
assert [g.title for g in view] == ['app'] and 'one at a time' in view[0].subtitle
text = '\n'.join(l.text() for l in ui.render_list(view, time.time(), 120))
for want in ('☰ app', '1. ✓ PLAN_1_now', 'ready — starts next', 'no lead named', 'lead local:w1:p2'):
    assert want in text, (want, text)
plans = '\n'.join(l.text() for l in ui.render_list(ui.build_view(ix, 'plan', facet='all'), time.time(), 140))
assert 'queue 2/3' in plans, plans
bad = {'schema': 'herdr-peers/fleet-v1', 'daemon': {}, 'machines': [dict(fleet['machines'][0], queues=[{'repo_root': '/r', 'items': 5}])]}
assert not fleet_report.valid_fleet(bad), 'a malformed queue on the map is refused'
print('ok')
PY
assert_eq "the Queues view lists each repository's queue; plans show their place in it" "ok" "$OUT"
# --- the facets: one model in every grouping (2.1.0) -------------------------------------------------
run python3 - "$UI_SCRIPTS" <<'PY'
import json, sys, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_ui as ui, fleet_report

NOW = 2_000_000_000.0
def ts(ago): return time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(NOW - ago))
def prow(pid, cls='open', situation=None, moved=60, lead='local:w1:p1'):
    return {'plan': pid, 'class': cls, 'lead': lead, 'epoch': 1, 'succession': [], 'lanes': [],
            'repo_root': '/src/app', 'blocker_class': None, 'situation': situation, 'tasks_done': 1,
            'tasks_total': 3, 'current_task': None, 'detail': None, 'progress': None, 'updated_at': None,
            'state_updated_at': ts(moved) if moved is not None else None}
def arow(pane, state, plans=()):
    return {'pane': pane, 'kind': 'claude', 'state': state, 'cwd': '/src/app', 'repo_root': '/src/app',
            'branch': 'main', 'title': '', 'state_since': None, 'plans': [{'plan': p, 'role': r} for p, r in plans]}
def qi(pid, state, reason=None, ready=False):
    return {'plan': pid, 'state': state, 'after': None, 'lead': None, 'ready': ready, 'blocked_reason': reason}
FLEET = {'schema': 'herdr-peers/fleet-v1', 'generated_at': ts(5), 'daemon': {}, 'machines': [
    {'machine': 'local', 'label': 'Mac', 'agents_state': 'ok', 'plans_state': 'ok',
     'agents': [arow('w1:p1', 'working', [('P_moving', 'lead')]), arow('w1:p2', 'blocked', [('P_blocked', 'lead')]),
                arow('w1:p3', 'idle'), arow('w1:p4', 'done'), arow('w1:p5', 'working'), arow('w1:p6', 'weird')],
     'plans': [prow('P_moving'), prow('P_blocked', 'blocked'), prow('P_stalled', situation='plan_stalled'),
               prow('P_nolead', situation='plan_no_lead'), prow('P_still', moved=2 * 86400 + 4 * 3600),
               prow('P_queued', moved=9 * 86400), prow('P_done', 'completed'), prow('P_unread', 'unreadable', moved=None),
               prow('P_oldmap', moved=None)],
     'queues': [{'repo_root': '/src/app', 'parallel': False, 'invalid': False, 'items': [
         qi('P_finished', 'done'), qi('P_skipped', 'skipped'), qi('P_moving', 'started'),
         qi('P_queued', 'queued', ready=True), qi('P_next', 'queued', 'waiting for P_queued'),
         qi('P_stuck', 'queued', 'no lead named')]}]},
    {'machine': 'm2', 'label': 'XWin', 'agents_state': 'unknown', 'plans_state': 'unknown',
     'agents': [], 'plans': [], 'queues': [{'repo_root': '/r', 'parallel': False, 'invalid': True, 'items': []}]}]}
assert fleet_report.valid_fleet(FLEET), 'state_updated_at is a valid map field'
bad = json.loads(json.dumps(FLEET)); bad['machines'][0]['plans'][0]['state_updated_at'] = 5
assert not fleet_report.valid_fleet(bad), 'a non-string state_updated_at is refused'
old = json.loads(json.dumps(FLEET))
for p in old['machines'][0]['plans']:
    del p['state_updated_at']
assert fleet_report.valid_fleet(old), 'a 2.0 map without state_updated_at is still read'
ix = ui.Index(FLEET)
P = ix.plan_by_key

# plan_facet, case by case
q = lambda pid: (ix.queue_pos.get('local/' + pid) or (0, 0, None))[2]
want = {'P_moving': 'active', 'P_blocked': 'attention', 'P_stalled': 'attention', 'P_nolead': 'attention',
        'P_still': 'attention', 'P_queued': 'waiting', 'P_done': 'done', 'P_unread': 'unreadable',
        'P_oldmap': 'active'}
got = dict((pid, ui.plan_facet(P['local/' + pid], NOW, q(pid))) for pid in want)
assert got == want, got
assert ui.stale_for(P['local/P_still'], NOW) == 2 * 86400 + 4 * 3600 and ui.span(ui.stale_for(P['local/P_still'], NOW)) == '2d 4h'
assert ui.stale_for(P['local/P_moving'], NOW) is None and ui.stale_for(P['local/P_oldmap'], NOW) is None
assert ui.plan_facet(P['local/P_still'], None) == 'active', 'no clock, no staleness'
assert ui.plan_facet(P['local/P_still'], NOW, stale_after=3 * 86400) == 'active', 'the threshold is a parameter'
assert ui.plan_facet(P['local/P_moving'], NOW, 'queued') == 'waiting'
assert [ui.span(x) for x in (0, 59, 2400, 18720, 86400)] == ['0m', '0m', '40m', '5h 12m', '1d 0h']
# agent_facet and queue_item_facet
assert dict((a.pane, ui.agent_facet(a)) for a in ix.agents) == {
    'w1:p1': 'active', 'w1:p2': 'attention', 'w1:p3': 'waiting', 'w1:p4': 'waiting', 'w1:p5': 'active',
    'w1:p6': 'attention'}
items = dict((it['plan'], it) for it in ix.machines[0]['queues'][0]['items'])
assert dict((k, ui.queue_item_facet(v)) for k, v in items.items()) == {
    'P_finished': 'done', 'P_skipped': 'done', 'P_moving': 'active', 'P_queued': 'waiting',
    'P_next': 'waiting', 'P_stuck': 'attention'}
assert ui.queue_item_facet({'state': 'queued', 'blocked': 'another plan of this repository runs'}) == 'waiting'
assert ui.queue_item_facet({'state': 'odd'}) == 'attention'

# counts, per grouping, and under a search
c = ui.facet_counts(ix, 'plan', '', NOW)
# plans: 9 rows + P_next and P_stuck (queued, no plan row); P_finished/P_skipped are not queued
assert c == {'attention': 5, 'active': 2, 'waiting': 2, 'done': 1, 'unreadable': 1, 'all': 11}, c
assert ui.facet_counts(ix, 'repo', '', NOW) == {'attention': 2, 'active': 2, 'waiting': 2, 'done': 0, 'unreadable': 0, 'all': 6}
assert ui.facet_counts(ix, 'machine', '', NOW) == {'attention': 3, 'active': 2, 'waiting': 2, 'done': 0, 'unreadable': 0, 'all': 7}, \
    'an unreachable machine counts as attention'
assert ui.facet_counts(ix, 'queue', '', NOW) == {'attention': 2, 'active': 1, 'waiting': 2, 'done': 2, 'unreadable': 0, 'all': 7}, \
    'an invalid queue file counts as attention'
assert ui.facet_counts(ix, 'plan', 'p_st', NOW) == {'attention': 3, 'active': 0, 'waiting': 0, 'done': 0, 'unreadable': 0, 'all': 3}
assert ui.facet_counts(None, 'plan') == {'attention': 0, 'active': 0, 'waiting': 0, 'done': 0, 'unreadable': 0, 'all': 0}

# views: the default is attention + active, never done
titles = lambda g, f, n='': [x.title for x in ui.build_view(ix, g, n, f, NOW)]
focus = titles('plan', ui.FOCUS)
assert set(focus) >= {'P_blocked', 'P_stalled', 'P_nolead', 'P_still', 'P_stuck', 'P_moving', 'P_oldmap'}, focus
assert 'P_unread' not in focus and 'P_unread' not in titles('plan', 'attention'), 'Attention means you can act on it now'
assert titles('plan', 'all')[-1] == 'P_unread', 'an unreadable plan comes at the very end, under All'
assert 'P_done' not in focus and 'P_queued' not in focus and 'Doing nothing — free to take work' not in focus
assert titles('plan', 'done') == ['P_done']
assert set(titles('plan', 'waiting')) == {'P_queued', 'P_next', 'Doing nothing — free to take work'}
assert set(titles('plan', 'active')) == {'P_moving', 'P_oldmap', 'Working outside any plan'}
assert len([t for t in titles('plan', 'all') if t.startswith('P_')]) == 11
v = ui.build_view(ix, 'plan', '', 'attention', NOW)
assert [g.facet for g in v if g.kind in ('plan', 'queued')] == ['attention'] * 5
assert [g.stale for g in v if g.title == 'P_still'] == [2 * 86400 + 4 * 3600]
text = '\n'.join(l.text() for l in ui.render_list(v, NOW, 120))
assert 'no movement for 2d 4h' in text and 'QUEUED' in text and 'no lead named' in text, text
assert [m.title for m in ui.build_view(ix, 'machine', '', 'attention', NOW)] == ['Mac', 'XWin']
assert [m.title for m in ui.build_view(ix, 'machine', '', 'waiting', NOW)] == ['Mac']
assert ui.build_view(ix, 'repo', '', 'done', NOW) == [], 'an agent is never done'
qv = ui.build_view(ix, 'queue', '', 'waiting', NOW)
assert [[it['plan'] for it in g.plan[1]] for g in qv] == [['P_queued', 'P_next']]
qt = '\n'.join(l.text() for l in ui.render_list(qv, NOW, 120))
assert ' 4. ' in qt and ' 5. ' in qt and ' 1. ' not in qt, 'a filtered queue keeps each item\'s real place'
assert [g.subtitle.endswith('INVALID queue file') for g in ui.build_view(ix, 'queue', '', 'attention', NOW)] == [False, True]

# the facet row: counts, the selected view, the alert tone, narrow fallback, mouse spans
line, spans = ui.render_facets(ui.FOCUS, c, 130, 'plan')
t = line.text()
for want_text in ('1 Attention 5', '2 Active 2', '3 Waiting 2', '4 Done 1', '5 All 11', 'needs you + moving', '←→ 1-5'):
    assert want_text in t, (want_text, t)
styles = dict((text.strip(), style) for text, style in line.segs)
assert styles['1 Attention 5'] == 'bad_badge' and styles['2 Active 2'] == 'tab_on' and styles['4 Done 1'] == 'tab'
calm, _ = ui.render_facets('done', dict(c, attention=0), 130, 'plan')
calm_styles = dict((text.strip(), style) for text, style in calm.segs)
assert calm_styles['1 Attention 0'] == 'tab' and calm_styles['4 Done 1'] == 'tab_on', 'only Attention alerts, and only when it holds something'
assert [f for _, _, f in spans] == list(ui.FACETS)
for x0, x1, f in spans:
    assert t[x0:x1].strip().split(' ')[1] == ui.FACET_LABEL[f], (t[x0:x1], f)
narrow, nspans = ui.render_facets(ui.FOCUS, c, 50, 'plan')
assert narrow.text().strip() == 'A5 Ac2 W2 D1 All11' and len(nspans) == 5, narrow.text()
mid = ui.render_facets(ui.FOCUS, c, 90, 'plan')[0].text()
assert '1 Attention 5' in mid and '←→' not in mid, 'a middle width drops the hints before the words'
for width in (50, 60, 90, 130):
    assert ui.width_of(ui.render_facets('all', c, width, 'machine')[0].text()) == width

# unreadable plans: only under All, dimmed, each saying why; Attention gets one quiet hint
assert ui.unreadable_hint('plan', ui.FOCUS, c) == '1 unreadable plan: see All (5)'
assert ui.unreadable_hint('plan', 'attention', dict(c, unreadable=14)) == '14 unreadable plans: see All (5)'
assert ui.unreadable_hint('plan', 'all', c) is None and ui.unreadable_hint('plan', 'active', c) is None
assert ui.unreadable_hint('repo', ui.FOCUS, c) is None and ui.unreadable_hint('plan', ui.FOCUS, dict(c, unreadable=0)) is None
whys = json.loads(json.dumps(FLEET))
rows = whys['machines'][0]['plans']
for pid, why in (('P_w_missing', 'missing'), ('P_w_parse', 'parse'), ('P_w_shape', 'shape'), ('P_w_none', None)):
    r = prow(pid, 'unreadable', moved=None); r['unreadable_reason'] = why; rows.append(r)
assert fleet_report.valid_fleet(whys)
bad_why = json.loads(json.dumps(whys)); bad_why['machines'][0]['plans'][-1]['unreadable_reason'] = 'because'
assert not fleet_report.valid_fleet(bad_why), 'an unknown reason is refused'
wix = ui.Index(whys)
allv = ui.build_view(wix, 'plan', '', 'all', NOW)
unr = [g for g in allv if g.kind == 'plan' and g.plan.cls == 'unreadable']
assert [g.tone for g in unr] == ['dim'] * 5 and allv.index(unr[0]) > max(allv.index(g) for g in allv
                                                                         if g.kind == 'plan' and g.plan.cls != 'unreadable')
wtext = '\n'.join(l.text() for l in ui.render_list(allv, NOW, 160))
for want_text in ('no state.json where its lead record points', 'does not parse', 'older or newer plan generation',
                  'the report does not say why'):
    assert want_text in wtext, (want_text, wtext)
# the order inside Attention: NO LEAD and blocked first, then stalled or a moved lead, then no movement;
# nearest to done first, the longest still first
order = {'schema': 'herdr-peers/fleet-v1', 'daemon': {}, 'machines': [{'machine': 'local', 'label': 'Mac',
         'agents_state': 'ok', 'plans_state': 'ok', 'agents': [], 'plans': []}]}
def orow(pid, done, cls='open', situation=None, moved=60):
    r = prow(pid, cls, situation, moved); r['tasks_done'], r['tasks_total'] = done, 10; return r
order['machines'][0]['plans'] = [
    orow('S_still_short', 1, moved=2 * 86400), orow('S_still_long', 9, moved=9 * 86400),
    orow('J_stalled', 2, situation='plan_stalled'), orow('J_moved', 8, situation='plan_lead_moved'),
    orow('N_nolead_low', 1, situation='plan_no_lead'), orow('B_blocked_high', 7, 'blocked'),
    orow('N_nolead_high', 9, situation='plan_no_lead'), orow('A_active', 5)]
oix = ui.Index(order)
assert [g.title for g in ui.build_view(oix, 'plan', '', 'attention', NOW)] == [
    'N_nolead_high', 'B_blocked_high', 'N_nolead_low', 'J_moved', 'J_stalled', 'S_still_long', 'S_still_short']
assert [g.title for g in ui.build_view(oix, 'plan', '', ui.FOCUS, NOW)][-1] == 'A_active', 'Attention before Active'
# the header's second row degrades in steps; the plans summary is never cut
brain = {'state': 'ready', 'kind': 'claude', 'profile': '@work1', 'asked_last_hour': 3,
         'last': {'action': 'ask_lead_to_resolve', 'plan': 'PLAN_123_something_long', 'case': 'c', 'at': 'x'},
         'retired': None, 'excluded': ['@a', '@b']}
cnt = {'working': 7, 'waiting': 1, 'idle': 35, 'unknown': 0}
pl = {'needs_you': 3, 'open': 1, 'completed': 15}
for width in (200, 140, 110, 90, 70, 60, 52):
    t = ui.header_counts(cnt, pl, brain, width).text()
    assert '3 need you · 1 running · 15 done' in t, (width, t)   # never cut
    assert ui.width_of(t.rstrip()) <= width, (width, t)
assert 'last: ask_lead_to_resolve' in ui.header_counts(cnt, pl, brain, 260).text()
assert '● 7 working' in ui.header_counts(cnt, pl, brain, 140).text()
assert '●7 ◆1 ○35 ?0' in ui.header_counts(cnt, pl, brain, 70).text()
assert 'brain' not in ui.header_counts(cnt, pl, brain, 52).text()
for width in (60, 110):
    assert ui.width_of(ui.render_header(ix, 30, 'plan', '', width)[1].text()) == width

# empty states say why, and where the rest is
assert ui.empty_note('plan', 'attention', {'active': 7}) == 'Nothing needs you · 7 plans moving'
assert ui.empty_note('plan', ui.FOCUS, {'waiting': 3, 'done': 21}, '', 2) == \
    'Nothing needs you and nothing is moving · 3 waiting · 21 done · 2 free agents under Waiting'
assert ui.empty_note('repo', 'done', {}) == 'Agents are never done: the free ones are under Waiting'
assert ui.empty_note('queue', 'attention', {'active': 1, 'waiting': 2}) == 'No queued plan is stuck · 1 started · 2 waiting'
assert ui.empty_note('machine', 'active', {}, 'zzz') == 'nothing here matches "zzz" · 0 in All'
print('ok')
PY
assert_eq "facets: each item classified, counted, filtered and drawn the same way in every grouping" "ok" "$OUT"

# --- the facets in the live watcher ----------------------------------------------------------------
run python3 - "$UI_SCRIPTS" <<'PY'
import json, os, sys, tempfile, time
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import fleet_ui as ui
clock = [2_000_000_000.0]
class Term(object):
    def __init__(self, keys, w=130, h=30):
        self.keys, self.w, self.h, self.rows, self.mouse = list(keys), w, h, {}, None
    def size(self): return self.w, self.h
    def clear(self): self.rows = {}
    def draw(self, y, line): self.rows[y] = line
    def flush(self): pass
    def read_key(self, timeout):
        clock[0] += timeout
        if not self.keys:
            return 'q'
        k = self.keys.pop(0)
        if isinstance(k, tuple):
            self.mouse = k
            return 'mouse'
        return k
    def last_mouse(self): return self.mouse
    def screen(self): return '\n'.join(self.rows[y].text() for y in sorted(self.rows))
agents = [{'pane': 'w1:p1', 'kind': 'claude', 'state': 'working', 'cwd': '/a', 'repo_root': '/a', 'branch': 'm',
           'title': '', 'state_since': None, 'plans': [{'plan': 'P_run', 'role': 'lead'}]},
          {'pane': 'w1:p2', 'kind': 'codex', 'state': 'idle', 'cwd': '/b', 'repo_root': '/b', 'branch': 'm',
           'title': '', 'state_since': None, 'plans': []}]
def prow(pid, cls):
    return {'plan': pid, 'class': cls, 'lead': 'local:w1:p1', 'epoch': 1, 'succession': [], 'lanes': [],
            'repo_root': '/a', 'blocker_class': None, 'situation': None, 'tasks_done': 1, 'tasks_total': 2,
            'current_task': None, 'detail': None}
fleet = {'schema': 'herdr-peers/fleet-v1', 'generated_at': '2033-05-18T03:33:00Z', 'daemon': {},
         'machines': [{'machine': 'local', 'label': 'Mac', 'agents_state': 'ok', 'plans_state': 'ok',
                       'agents': agents, 'plans': [prow('P_run', 'open'), prow('P_old', 'completed')]}]}
path = os.path.join(tempfile.mkdtemp(), 'fleet.json')
json.dump(fleet, open(path, 'w'))
def app(keys, **kw):
    t = Term(keys, **kw)
    a = ui.App(t, ui.FileSource(path), link_factory=lambda f: None, clock=lambda: clock[0], **kw.get('app', {}))
    a.run()
    return a, t
a, t = app([])
assert a.facet == ui.FOCUS and 'P_run' in t.screen() and 'P_old' not in t.screen(), t.screen()
assert t.rows[ui.HEADER_ROWS - 1].text().startswith('  1 Attention 0') and '─' in t.rows[ui.HEADER_ROWS].text()
a, t = app(['4'])
assert a.facet == 'done' and 'P_old' in t.screen() and 'P_run' not in t.screen()
a, t = app([']'])
assert a.facet == 'attention' and 'Nothing needs you · 1 plan moving' in t.screen(), t.screen()
a, t = app(['right', 'right'])
assert a.facet == 'active'
a, t = app(['['])
assert a.facet == 'all', 'left from the default wraps to All'
a, t = app(['left', 'left'])
assert a.facet == 'done'
# remembered per grouping for the session
a, t = app(['3', 'r', 'p'])
assert a.grouping == 'plan' and a.facet == 'waiting' and a.facets['repo'] == ui.FOCUS
a, t = app(['3', 'r', '5', 'p', 'r'])
assert a.facets == dict(a.facets, plan='waiting', repo='all') and a.facet == 'all'
# digits typed into a search are text, not a view
a, t = app(['/', '3', 'enter'])
assert a.needle == '3' and a.facet == ui.FOCUS
# a click on the facet row picks that view
a, t = app([])
row = t.rows[ui.HEADER_ROWS - 1].text()
x = row.index('Done')
a, t = app([(x, ui.HEADER_ROWS - 1, 'click')])
assert a.facet == 'done', a.facet
# the counts are computed when the view changes, not every tick
calls = []
real = ui.facet_counts
ui.facet_counts = lambda *args, **kw: (calls.append(1), real(*args, **kw))[1]
a, t = app([None, None, None, None])
assert len(calls) == 1, calls
ui.facet_counts = real
# a narrow terminal keeps the short form
a, t = app([], w=52, h=20)
assert 'A0 Ac1 W0 D1 All2' in t.rows[ui.HEADER_ROWS - 1].text(), t.rows[ui.HEADER_ROWS - 1].text()
# the starting view can be given
t = Term([])
a = ui.App(t, ui.FileSource(path), link_factory=lambda f: None, clock=lambda: clock[0], facet='done'); a.run()
assert a.facet == 'done' and all(v == 'done' for v in a.facets.values())
print('ok')
PY
assert_eq "facets in the watcher: keys, mouse, per-grouping memory, search, counts once per change" "ok" "$OUT"

export XDG_STATE_HOME=$UI_XDG_STATE
