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
g = ui.build_view(ix, 'plan')
names = [x.title for x in g]
assert set(names[:2]) == {'PLAN_2_web', 'PLAN_9_box'} and names[2] == 'PLAN_1_api', names
assert 'PLAN_3_old' not in names, 'a finished plan with nobody on it is not shown'
busy = [x for x in g if x.kind == 'busy'][0]
idle = [x for x in g if x.kind == 'idle'][0]
assert [a.pane for _, a in busy.members] == ['w1:p5'], busy.members
assert [a.pane for _, a in idle.members] == ['w1:p4'], 'the agents doing nothing have their own group'
# by repository and by machine
r = ui.build_view(ix, 'repo')
assert [x.title for x in r] == ['app', 'app', 'web', '(no repository)'], [x.title for x in r]
m = ui.build_view(ix, 'machine')
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
assert 'updated 45 s ago' in snap and 'PLAN_2_web' in snap and 'Doing nothing' in snap, snap
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
             'PLAN_1_api', '2/5', 'now: Write tests', 'Doing nothing', 'q quit'):
    assert want in s, (want, s)
assert 'API refactor' in s
# switch grouping
a, t = app(['r', 'q'], path); a.run()
assert a.grouping == 'repo' and 'app' in t.screen() and 'web' in t.screen()
a, t = app(['m', 'q'], path); a.run()
assert a.grouping == 'machine' and '▣ Mac' in t.screen()
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
a, t = app(['q'], path); a.run()
y = t.find('w1:p4')
a, t = app([(5, y, 'click'), 'q'], path); a.run()
assert a.sel_target == ('agent', 'local:w1:p4'), a.sel_target
a, t = app([(5, y, 'click'), (5, y, 'click'), 'q'], path); a.run()
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
assert_contains "of the map" "$OUT" "Doing nothing"
assert_eq "at the asked width" "90" "$(printf '%s\n' "$OUT" | sed -n 4p | python3 -c 'import sys,unicodedata; t=sys.stdin.read().rstrip("\n"); print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in t))' 2>/dev/null || echo "?")"
run "$HELPER" fleet ui --snapshot --width 10
assert_rc "an absurd width is a usage error" 2
run "$HELPER" fleet ui --snapshot --group machine
assert_contains "--group machine groups by machine" "$OUT" "▣ Mac"
export XDG_STATE_HOME=$UI_XDG_STATE
