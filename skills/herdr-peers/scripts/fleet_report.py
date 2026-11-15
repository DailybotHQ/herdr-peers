"""herdr-peers machine report — the plans led on this machine (stdlib only).

Self-contained on purpose: it imports nothing from the helper, needs no
Herdr pane, socket or environment, and runs on any python3 >= 3.6. The
helper imports it for `herdr-peers plans`; the autopilot daemon sends this
very file on standard input to `python3 -` on another machine, so that
machine needs no herdr-peers installed and no particular version.

It only reads: the lead records and delegation logs under the state root,
each plan's `state.json`, and the git top level and branch of the working
directories it is given. Everything it reads is data: parsed with strict
checks, never executed, and a file it cannot trust is reported as
`unreadable`, never guessed. When the state root itself cannot be read the
report says `unknown` — never an empty list, which would mean "no plans".
"""
import base64
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time

SCHEMA = 'herdr-peers/plans-v1'
REPORT_VERSION = 1
LEAD_SCHEMA = 'herdr-peers/lead-v1'
MAX_LEAD_BYTES = 64 * 1024
MAX_STATE_BYTES = 4 * 1024 * 1024
MAX_LOG_BYTES = 64 * 1024 * 1024
MAX_PLANS = 256
MAX_PANES = 512
MAX_LIST = 32
MAX_EPOCH = 10 ** 9
GIT_TIMEOUT = 5
OPEN_ASK_WINDOW = 2 * 3600   # an ask older than this was abandoned, not awaited

MACHINE_RE = r'(?:local|[A-Za-z0-9][A-Za-z0-9._-]{0,63})'
PANE_RE = r'[A-Za-z0-9]{1,32}:[A-Za-z0-9]{1,32}'
ADDR_RE = re.compile(r'^(%s):(%s)$' % (MACHINE_RE, PANE_RE))
PLAN_RE = re.compile(r'(?=.{1,128}$)[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*')
TS_RE = re.compile(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z')
SERVER_DIR_RE = re.compile(r'[0-9a-f]{64}')
BRANCH_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._/@+-]{0,199}')
BLOCK_CLASS_RE = re.compile(r'\bC[1-7]\b')
TASK_STATUSES = ('pending', 'in_progress', 'completed', 'blocked', 'skipped')
NOFOLLOW = getattr(os, 'O_NOFOLLOW', 0)


def state_root():
    root = os.environ.get('XDG_STATE_HOME')
    if not root:
        root = os.path.join(os.path.expanduser('~'), '.local', 'state')
    return os.path.join(root, 'herdr-peers')


def clean_path(value):
    """An absolute path free of control characters, or None."""
    if not isinstance(value, str) or not value or len(value) > 4096 or not os.path.isabs(value):
        return None
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        return None
    return value


def read_small(path, limit):
    """The bytes of a regular file opened without following a symlink, or
    None when it is missing, not regular, a symlink or larger than `limit`."""
    try:
        fd = os.open(path, os.O_RDONLY | NOFOLLOW)
    except OSError:
        return None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            return None
        chunks, left = [], limit + 1
        while left > 0:
            chunk = os.read(fd, min(left, 1 << 16))
            if not chunk:
                break
            chunks.append(chunk)
            left -= len(chunk)
        data = b''.join(chunks)
        return data if len(data) <= limit else None
    except OSError:
        return None
    finally:
        os.close(fd)


def load_json(path, limit):
    data = read_small(path, limit)
    if data is None:
        return None
    try:
        return json.loads(data.decode('utf-8'))
    except (ValueError, UnicodeDecodeError, RecursionError):
        return None


def valid_addresses(items):
    return (isinstance(items, list) and len(items) <= MAX_LIST
            and all(isinstance(a, str) and ADDR_RE.match(a) for a in items))


def lead_record(data):
    """The lead-v1 record inside a stored lead file, or None when it is not
    one. Strict: the file is data until it proves well formed."""
    if not isinstance(data, dict) or not isinstance(data.get('record'), dict):
        return None
    rec = dict(data['record'])
    if 'repo_root' in data:
        rec['repo_root'] = data['repo_root']
    if rec.get('schema') != LEAD_SCHEMA:
        return None
    if not isinstance(rec.get('plan'), str) or not PLAN_RE.fullmatch(rec['plan']):
        return None
    lead = rec.get('lead')
    if lead is not None and not (isinstance(lead, str) and ADDR_RE.match(lead)):
        return None
    epoch = rec.get('epoch')
    if not isinstance(epoch, int) or isinstance(epoch, bool) or not 1 <= epoch <= MAX_EPOCH:
        return None
    if not valid_addresses(rec.get('succession')) or not valid_addresses(rec.get('lanes')):
        return None
    if not isinstance(rec.get('updated_at'), str) or not TS_RE.fullmatch(rec['updated_at']):
        return None
    root = rec.get('repo_root')
    rec['repo_root'] = clean_path(root) if root is not None else None
    return rec


def lead_records(root):
    """Every valid lead record under the state root, as (server dir, record).
    Raises OSError when the root exists and cannot be listed."""
    out = []
    if not os.path.isdir(root):
        return out
    for server in sorted(os.listdir(root)):
        if not SERVER_DIR_RE.fullmatch(server):
            continue
        leads = os.path.join(root, server, 'leads')
        try:
            names = sorted(os.listdir(leads))
        except OSError:
            continue
        for name in names:
            if not name.endswith('.json'):
                continue
            rec = lead_record(load_json(os.path.join(leads, name), MAX_LEAD_BYTES))
            if rec is not None:
                out.append((server, rec))
    return out


def newest_per_plan(found):
    """One record per plan id: the highest epoch, then the latest update."""
    best = {}
    for server, rec in found:
        key = rec['plan']
        cur = best.get(key)
        if cur is None or (rec['epoch'], rec['updated_at']) > (cur[1]['epoch'], cur[1]['updated_at']):
            best[key] = (server, rec)
    return [best[k] for k in sorted(best)][:MAX_PLANS]


def classify(state):
    """(class, blocker class, progress digest) of a parsed state.json.

    Two shapes are accepted: the v5 state (top-level `status`, `blocked`,
    `checkpoint`, `completed_count`) and the v6/v7 snapshot (`tasks[].status`,
    `blocker`). Anything else is unreadable: a status is never guessed."""
    if not isinstance(state, dict):
        return 'unreadable', None, None
    tasks = state.get('tasks')
    if not isinstance(tasks, list) or not tasks or len(tasks) > 4096:
        return 'unreadable', None, None
    statuses, satisfied = [], 0
    for task in tasks:
        if not isinstance(task, dict) or task.get('status') not in TASK_STATUSES:
            return 'unreadable', None, None
        statuses.append(task['status'])
        criteria = task.get('criteria')
        if isinstance(criteria, list):
            satisfied += sum(1 for c in criteria if isinstance(c, dict) and c.get('satisfied') is True)
    top = state.get('status')
    if top is not None and top not in TASK_STATUSES:
        return 'unreadable', None, None
    blocker = state.get('blocked') if 'blocked' in state else state.get('blocker')
    if blocker is not None and not isinstance(blocker, dict):
        return 'unreadable', None, None
    done = all(s in ('completed', 'skipped') for s in statuses) and 'completed' in statuses
    if top == 'completed' or (top is None and done):
        cls = 'completed'
    elif blocker or top == 'blocked' or 'blocked' in statuses:
        cls = 'blocked'
    else:
        cls = 'open'
    block_class = None
    if cls == 'blocked' and blocker:
        text = ' '.join(str(blocker.get(k) or '') for k in ('class', 'needs', 'reason'))[:2000]
        found = BLOCK_CLASS_RE.search(text)
        block_class = found.group(0) if found else None
    progress = hashlib.sha256(json.dumps(
        [top, statuses, satisfied, state.get('checkpoint'), blocker, state.get('completed_count')],
        sort_keys=True, default=str).encode('utf-8')).hexdigest()[:16]
    return cls, block_class, progress


def plan_state_path(base, plan_id):
    """<base>/.dwp/plans/<id>/state.json when it stays inside <base>, else None."""
    if not base:
        return None
    path = os.path.join(base, '.dwp', 'plans', plan_id, 'state.json')
    try:
        real_base = os.path.realpath(base)
        real = os.path.realpath(path)
    except OSError:
        return None
    if real != os.path.join(real_base, '.dwp', 'plans', plan_id, 'state.json'):
        return None  # a symlink somewhere on the way leaves the repository
    return path if os.path.isfile(path) else None


class Git(object):
    """Top level and branch of a directory, asked once per directory."""

    def __init__(self):
        self.seen = {}

    def lookup(self, cwd):
        cwd = clean_path(cwd)
        if cwd is None:
            return None, None
        if cwd in self.seen:
            return self.seen[cwd]
        top = branch = None
        if os.path.isdir(cwd):
            try:
                proc = subprocess.run(
                    ['git', '-C', cwd, 'rev-parse', '--show-toplevel', '--abbrev-ref', 'HEAD'],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
                    timeout=GIT_TIMEOUT, env=dict(os.environ, GIT_OPTIONAL_LOCKS='0'))
                lines = proc.stdout.decode('utf-8', 'replace').splitlines()
                if proc.returncode == 0 and lines:
                    top = clean_path(lines[0])
                    if len(lines) > 1 and BRANCH_RE.fullmatch(lines[1]):
                        branch = lines[1]
                elif lines:
                    # A repository with no commit yet: the top level is still known.
                    top = clean_path(lines[0])
            except (OSError, subprocess.SubprocessError):
                pass
        self.seen[cwd] = (top, branch)
        return top, branch


def age_seconds(stamp, now):
    """Seconds since an ISO-8601 UTC stamp, or None when it is not one."""
    if not isinstance(stamp, str) or not TS_RE.fullmatch(stamp):
        return None
    try:
        import calendar
        return now - calendar.timegm(time.strptime(stamp[:19], '%Y-%m-%dT%H:%M:%S'))
    except ValueError:
        return None


def open_asks(root, server, pane, now=None):
    """How many asks this pane still awaits, from the delegation log of its
    server directory; None when the log cannot be counted. An ask launched
    more than OPEN_ASK_WINDOW ago is not awaited any more."""
    now = time.time() if now is None else now
    path = os.path.join(root, server, 'log.ndjson')
    if not os.path.exists(path):
        return 0
    data = read_small(path, MAX_LOG_BYTES)
    if data is None:
        return None
    latest = {}
    for line in data.split(b'\n'):
        if not line.strip():
            continue
        try:
            rec = json.loads(line.decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(rec, dict) and rec.get('role') == 'caller' and isinstance(rec.get('id'), str):
            latest[rec['id']] = rec
    count = 0
    for rec in latest.values():
        if rec.get('state') != 'launched':
            continue
        match = ADDR_RE.match(rec.get('self') or '')
        age = age_seconds(rec.get('ts'), now)
        if match and match.group(2) == pane and (age is None or age < OPEN_ASK_WINDOW):
            count += 1
    return count


def describe_plan(root, server, rec, panes, git, now=None):
    plan_id = rec['plan'].rsplit('/', 1)[-1]
    lead = rec['lead']
    lead_pane = ADDR_RE.match(lead).group(2) if lead else None
    lead_local = bool(lead) and ADDR_RE.match(lead).group(1) == 'local'
    bases = []
    if lead_local and lead_pane in panes:
        top, _branch = git.lookup(panes[lead_pane])
        if top:
            bases.append(top)
    if rec.get('repo_root') and rec['repo_root'] not in bases:
        bases.append(rec['repo_root'])
    path = None
    for base in bases:
        path = plan_state_path(base, plan_id)
        if path:
            break
    cls, block_class, progress, updated = 'unreadable', None, None, None
    if path:
        state = load_json(path, MAX_STATE_BYTES)
        cls, block_class, progress = classify(state)
        if isinstance(state, dict) and isinstance(state.get('updated_at'), str) \
                and TS_RE.fullmatch(state['updated_at']):
            updated = state['updated_at']
    return {
        'plan': rec['plan'], 'server': server, 'lead': lead, 'epoch': rec['epoch'],
        'succession': rec['succession'], 'lanes': rec['lanes'], 'repo_root': rec.get('repo_root'),
        'plan_dir': os.path.dirname(path) if path else None, 'class': cls,
        'blocker_class': block_class, 'progress': progress, 'state_updated_at': updated,
        'updated_at': rec['updated_at'],
        'open_asks': open_asks(root, server, lead_pane, now) if lead_local else None,
    }


def clean_panes(panes):
    """{pane id: working directory} with only well-formed entries."""
    out = {}
    if isinstance(panes, dict):
        for pane, cwd in list(panes.items())[:MAX_PANES]:
            if isinstance(pane, str) and re.fullmatch(PANE_RE, pane) and clean_path(cwd):
                out[pane] = cwd
    return out


def report(panes=None, root=None, now=None):
    """The plans-v1 report of this machine. `panes` maps a pane id to its
    working directory, as Herdr lists them; it lets the report resolve each
    agent's repository and a plan kept in a linked worktree."""
    root = root or state_root()
    panes = clean_panes(panes)
    git = Git()
    out = {'schema': SCHEMA, 'report_version': REPORT_VERSION,
           'generated_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(now)),
           'state': 'ok', 'reason': None, 'plans': [], 'agents': []}
    try:
        found = lead_records(root)
    except OSError as exc:
        out['state'], out['reason'] = 'unknown', 'state root unreadable (%s)' % type(exc).__name__
        found = []
    for server, rec in newest_per_plan(found):
        out['plans'].append(describe_plan(root, server, rec, panes, git, now))
    for pane in sorted(panes):
        top, branch = git.lookup(panes[pane])
        out['agents'].append({'pane': pane, 'cwd': panes[pane], 'repo_root': top, 'branch': branch})
    return out


def main(encoded=None):
    """Print the report as one JSON line. `encoded` is base64 of the JSON
    {pane: cwd} map; it is decoded as data and nothing in it is executed."""
    panes = None
    if encoded:
        try:
            panes = json.loads(base64.b64decode(encoded.encode('ascii'), validate=True).decode('utf-8'))
        except (ValueError, UnicodeError):
            panes = None
    sys.stdout.write(json.dumps(report(panes), sort_keys=True) + '\n')
    return 0


PANES_B64 = None  # replaced by the daemon when it sends this file to another machine

if __name__ == '__main__':
    sys.exit(main(PANES_B64 or (sys.argv[1] if len(sys.argv) > 1 else None)))
