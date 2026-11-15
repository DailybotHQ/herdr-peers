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
FLEET_SCHEMA = 'herdr-peers/fleet-v1'
FLEET_FILE = 'fleet.json'
MAX_FLEET_BYTES = 2 * 1024 * 1024
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


def default_server_dir():
    """The state directory name of the Herdr server at the default socket
    path. Outside a pane there is no socket in the environment, so this is
    how the report tells the current server's records from those an older
    server left behind."""
    config = os.environ.get('XDG_CONFIG_HOME') or os.path.join(os.path.expanduser('~'), '.config')
    socket_path = os.environ.get('HERDR_SOCKET_PATH') or os.path.join(config, 'herdr', 'herdr.sock')
    server_id = 'sha256:' + hashlib.sha256(('socket:' + socket_path).encode('utf-8')).hexdigest()
    return hashlib.sha256(server_id.encode('utf-8')).hexdigest()


def server_dirs(root, servers=None):
    """The server directories to read: those named by the caller (the helper
    knows its own); else the default socket's, when it exists; else every
    one — a machine with a single server keeps its records in one anyway."""
    names = [n for n in sorted(os.listdir(root)) if SERVER_DIR_RE.fullmatch(n)]
    if servers is not None:
        return [n for n in names if n in servers]
    default = default_server_dir()
    return [default] if default in names else names


def lead_records(root, servers=None):
    """Every valid lead record of the chosen server directories, as (server
    dir, record). Raises OSError when the root exists and cannot be listed."""
    out = []
    if not os.path.isdir(root):
        return out
    for server in server_dirs(root, servers):
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
    if tasks is None and state.get('status') in TASK_STATUSES:
        tasks = []  # a state that keeps only its top-level status
    if not isinstance(tasks, list) or (not tasks and state.get('status') not in TASK_STATUSES) \
            or len(tasks) > 4096:
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
    done = bool(statuses) and all(s in ('completed', 'skipped') for s in statuses) \
        and 'completed' in statuses
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
    """The plan's state.json under <base> (the `.dwp`, `plans`, <id> path
    components) when it stays inside <base>, else None."""
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
        self.common = {}

    def common_dir(self, path):
        """The repository's common git directory for `path` (the same for a
        checkout and all its linked worktrees), or None."""
        path = clean_path(path)
        if path is None:
            return None
        if path not in self.common:
            found = None
            if os.path.isdir(path):
                try:
                    proc = subprocess.run(['git', '-C', path, 'rev-parse', '--git-common-dir'],
                                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                          stdin=subprocess.DEVNULL, timeout=GIT_TIMEOUT,
                                          env=dict(os.environ, GIT_OPTIONAL_LOCKS='0'))
                    out = proc.stdout.decode('utf-8', 'replace').strip()
                    if proc.returncode == 0 and out:
                        found = os.path.realpath(os.path.join(path, out))
                except (OSError, subprocess.SubprocessError):
                    pass
            self.common[path] = found
        return self.common[path]

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


def recent(stamp, cutoff):
    """True when an ISO-8601 UTC stamp is at or after `cutoff` (same format:
    the strings order like the times); a stamp that is not one counts as
    recent, so an unparseable ask is still awaited."""
    if not isinstance(stamp, str) or not TS_RE.fullmatch(stamp):
        return True
    return stamp[:19] >= cutoff


def caller_records(path):
    """{ask id: (state, self, ts)} of the latest caller record per ask in a log file (opened without following a symlink,
    at most MAX_LOG_BYTES), streamed so memory stays flat whatever its size;
    None when it cannot be read."""
    try:
        fd = os.open(path, os.O_RDONLY | NOFOLLOW)
    except OSError:
        return None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_LOG_BYTES:
            os.close(fd)
            return None
        handle = os.fdopen(fd, 'rb')
    except OSError:
        os.close(fd)
        return None
    latest = {}
    with handle:
        try:
            for line in handle:
                if b'"caller"' not in line:
                    continue  # most lines are other roles: skip them before parsing
                try:
                    rec = json.loads(line.decode('utf-8'))
                except (ValueError, UnicodeDecodeError):
                    continue
                if isinstance(rec, dict) and rec.get('role') == 'caller' \
                        and isinstance(rec.get('id'), str):
                    # Only what the count needs is kept: memory stays flat.
                    latest[rec['id']] = (rec.get('state'), rec.get('self'), rec.get('ts'))
        except OSError:
            return None
    return latest


def launched_asks(root, server, cache):
    """The asks still `launched` in one server's delegation log, as (state,
    self, ts), parsed once per report (`cache`); [] without a log; None when
    it cannot be read."""
    if server in cache:
        return cache[server]
    path = os.path.join(root, server, 'log.ndjson')
    if not os.path.exists(path):
        cache[server] = []
        return cache[server]
    latest = caller_records(path)
    if latest is None:
        cache[server] = None
        return None
    cache[server] = [v for v in latest.values() if v[0] == 'launched']
    return cache[server]


def open_asks(root, server, pane, now=None, cache=None):
    """How many asks this pane still awaits, from the delegation log of its
    server directory; None when the log cannot be counted. An ask launched
    more than OPEN_ASK_WINDOW ago is not awaited any more."""
    now = time.time() if now is None else now
    latest = launched_asks(root, server, {} if cache is None else cache)
    if latest is None:
        return None
    cutoff = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(now - OPEN_ASK_WINDOW))
    count = 0
    for _state, self_addr, stamp in latest:
        match = ADDR_RE.match(self_addr or '') if isinstance(self_addr, str) else None
        if match and match.group(2) == pane and recent(stamp, cutoff):
            count += 1
    return count


def describe_plan(root, server, rec, panes, git, now=None, logs=None):
    plan_id = rec['plan'].rsplit('/', 1)[-1]
    lead = rec['lead']
    lead_pane = ADDR_RE.match(lead).group(2) if lead else None
    lead_local = bool(lead) and ADDR_RE.match(lead).group(1) == 'local'
    bases = []
    lead_top = None
    if lead_local and lead_pane in panes:
        lead_top, _branch = git.lookup(panes[lead_pane])
        if lead_top:
            bases.append(lead_top)
    if rec.get('repo_root') and rec['repo_root'] not in bases:
        bases.append(rec['repo_root'])
    path = found_at = None
    for base in bases:
        path = plan_state_path(base, plan_id)
        if path:
            found_at = base
            break
    # Does the pane the record names still work in the plan's repository? A
    # reused pane id (after a Herdr restart) would not. None when unknown.
    lead_in_repo = None
    if lead_top and (rec.get('repo_root') or found_at):
        # Known only when the pane's directory is in a git repository here. The
        # same repository is the same common git directory, so a lead in a
        # linked worktree still counts; another repository means the pane does
        # something else now.
        mine = git.common_dir(panes[lead_pane])
        theirs = git.common_dir(found_at or rec.get('repo_root'))
        if mine and theirs:
            lead_in_repo = mine == theirs
        else:
            lead_in_repo = lead_top == found_at or lead_top == rec.get('repo_root')
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
        'updated_at': rec['updated_at'], 'lead_in_repo': lead_in_repo,
        'open_asks': open_asks(root, server, lead_pane, now, logs) if lead_local else None,
    }


def clean_panes(panes):
    """{pane id: working directory} with only well-formed entries."""
    out = {}
    if isinstance(panes, dict):
        for pane, cwd in list(panes.items())[:MAX_PANES]:
            if isinstance(pane, str) and re.fullmatch(PANE_RE, pane) and clean_path(cwd):
                out[pane] = cwd
    return out


def store_fleet(root, text):
    """Keep the daemon's merged snapshot where `herdr-peers fleet` reads it:
    <state root>/fleet.json, 0600, replaced atomically. The text must be one
    fleet-v1 JSON object; it is stored as data and never executed. Returns
    `stored`, `unchanged` or `failed`."""
    try:
        if not isinstance(text, str) or len(text.encode('utf-8')) > MAX_FLEET_BYTES:
            return 'failed'
        doc = json.loads(text)
        if not isinstance(doc, dict) or doc.get('schema') != FLEET_SCHEMA:
            return 'failed'
        os.makedirs(root, 0o700, exist_ok=True)
        path = os.path.join(root, FLEET_FILE)
        if os.path.islink(path):
            return 'failed'
        old = read_small(path, MAX_FLEET_BYTES)
        if old is not None and old.decode('utf-8', 'replace') == text:
            os.utime(path, None)  # still current: only its age is refreshed
            return 'unchanged'
        tmp = '%s.%d.tmp' % (path, os.getpid())
        try:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW, 0o600)
            try:
                data = text.encode('utf-8')
                while data:
                    data = data[os.write(fd, data):]
                os.fsync(fd)
            finally:
                os.close(fd)
            os.replace(tmp, path)
        except OSError:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return 'failed'
        return 'stored'
    except (OSError, ValueError, RecursionError):
        return 'failed'


def read_fleet(root=None):
    """(snapshot dict, age in seconds) of the stored fleet file, or (None, None)."""
    path = os.path.join(root or state_root(), FLEET_FILE)
    doc = load_json(path, MAX_FLEET_BYTES)
    if not isinstance(doc, dict) or doc.get('schema') != FLEET_SCHEMA:
        return None, None
    try:
        return doc, max(0, int(time.time() - os.stat(path).st_mtime))
    except OSError:
        return None, None


PLAN_KEYS = frozenset(('plan', 'server', 'lead', 'epoch', 'succession', 'lanes', 'repo_root',
                       'plan_dir', 'class', 'blocker_class', 'progress', 'state_updated_at',
                       'updated_at', 'lead_in_repo', 'open_asks'))
AGENT_KEYS = frozenset(('pane', 'cwd', 'repo_root', 'branch'))


def valid_report(doc):
    """True when `doc` is a well-formed plans-v1 report. The daemon checks
    every answer with this before using a single field of it."""
    if not isinstance(doc, dict) or doc.get('schema') != SCHEMA:
        return False
    if doc.get('state') not in ('ok', 'unknown'):
        return False
    plans, agents = doc.get('plans'), doc.get('agents')
    if not isinstance(plans, list) or not isinstance(agents, list):
        return False
    if len(plans) > MAX_PLANS or len(agents) > MAX_PANES:
        return False
    for plan in plans:
        if not isinstance(plan, dict) or not PLAN_KEYS <= set(plan):
            return False
        if plan.get('lead_in_repo') not in (True, False, None):
            return False
        if not isinstance(plan.get('plan'), str) or not PLAN_RE.fullmatch(plan['plan']):
            return False
        lead = plan.get('lead')
        if lead is not None and not (isinstance(lead, str) and ADDR_RE.match(lead)):
            return False
        epoch = plan.get('epoch')
        if not isinstance(epoch, int) or isinstance(epoch, bool) or not 1 <= epoch <= MAX_EPOCH:
            return False
        if not valid_addresses(plan.get('succession')) or not valid_addresses(plan.get('lanes')):
            return False
        if plan.get('class') not in ('open', 'blocked', 'completed', 'unreadable'):
            return False
        progress = plan.get('progress')
        if progress is not None and not (isinstance(progress, str)
                                         and re.fullmatch(r'[0-9a-f]{16}', progress)):
            return False
        block = plan.get('blocker_class')
        if block is not None and not (isinstance(block, str) and re.fullmatch(r'C[1-7]', block)):
            return False
        asks = plan.get('open_asks')
        if asks is not None and (not isinstance(asks, int) or isinstance(asks, bool) or asks < 0):
            return False
        for key in ('repo_root', 'plan_dir'):
            if plan.get(key) is not None and clean_path(plan[key]) is None:
                return False
        stamp = plan.get('state_updated_at')
        if stamp is not None and not (isinstance(stamp, str) and TS_RE.fullmatch(stamp)):
            return False
    for agent in agents:
        if not isinstance(agent, dict) or not AGENT_KEYS <= set(agent):
            return False
        if not isinstance(agent.get('pane'), str) or not re.fullmatch(PANE_RE, agent['pane']):
            return False
        if clean_path(agent.get('cwd')) is None:
            return False
        if agent.get('repo_root') is not None and clean_path(agent['repo_root']) is None:
            return False
        branch = agent.get('branch')
        if branch is not None and not (isinstance(branch, str) and BRANCH_RE.fullmatch(branch)):
            return False
    return True


def report(panes=None, root=None, now=None, servers=None):
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
        found = lead_records(root, servers)
    except OSError as exc:
        out['state'], out['reason'] = 'unknown', 'state root unreadable (%s)' % type(exc).__name__
        found = []
    logs = {}
    for server, rec in newest_per_plan(found):
        out['plans'].append(describe_plan(root, server, rec, panes, git, now, logs))
    for pane in sorted(panes):
        top, branch = git.lookup(panes[pane])
        out['agents'].append({'pane': pane, 'cwd': panes[pane], 'repo_root': top, 'branch': branch})
    return out


def decoded(encoded):
    """The text behind a base64 string, or None. Data only."""
    if not encoded:
        return None
    try:
        return base64.b64decode(encoded.encode('ascii'), validate=True).decode('utf-8')
    except (ValueError, UnicodeError):
        return None


def main(encoded=None, fleet=None):
    """Print the report as one JSON line. `encoded` is base64 of the JSON
    {pane: cwd} map and `fleet` base64 of the daemon's snapshot to keep on
    this machine; both are decoded as data and nothing in them is executed."""
    panes = None
    text = decoded(encoded)
    if text is not None:
        try:
            panes = json.loads(text)
        except (ValueError, RecursionError):
            panes = None
    out = report(panes)
    snapshot = decoded(fleet)
    if snapshot is not None:
        out['fleet'] = store_fleet(state_root(), snapshot)
    sys.stdout.write(json.dumps(out, sort_keys=True) + '\n')
    return 0


PANES_B64 = None  # replaced by the daemon when it sends this file to another machine
FLEET_B64 = None  # replaced by the daemon when it sends this file to another machine

if __name__ == '__main__':
    sys.exit(main(PANES_B64 or (sys.argv[1] if len(sys.argv) > 1 else None), FLEET_B64))
