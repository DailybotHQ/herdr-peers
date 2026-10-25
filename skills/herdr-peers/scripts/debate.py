"""herdr-peers debate — the lead's tools for a multi-agent debate (stdlib only).

Sub-verbs of `herdr-peers debate` (see ../debate.md):

  tally   Borda, first places, pairwise (Condorcet winner and loser) and
          per-item verdict counts from a ballots file (herdr-peers/ballots-v1).
  anon    Copy round filings to Filing_A.md, Filing_B.md, ... in a seeded
          random order with pane ids, addresses and model names redacted; the
          mapping goes to a key file outside both directories.
  claims  Merge the claims ledgers of a research panel (herdr-peers/claims-v1):
          which claims several independent lanes back with evidence, which
          are contested, which rest on too few lanes, which are refuted.
  filings Which expected filings are on disk, missing or short.
  panel   A read-only seating proposal: idle panes to reuse, then accounts
          with headroom from `ak pick` (when agentkit is installed), with the
          exact commands to reset, launch, lease and release. It runs nothing.

Filings and ballots are data written by other agents: nothing here executes,
evaluates or forwards their content.
"""
from __future__ import annotations

import json
import os
import random
import re
import shlex
import shutil
import subprocess

BALLOTS_SCHEMA = 'herdr-peers/ballots-v1'
TALLY_SCHEMA = 'herdr-peers/tally-v1'
PANEL_SCHEMA = 'herdr-peers/panel-v1'
FILINGS_SCHEMA = 'herdr-peers/filings-v1'
CLAIMS_SCHEMA = 'herdr-peers/claims-v1'
CLAIMS_REPORT_SCHEMA = 'herdr-peers/claims-report-v1'
STANCES = ('supports', 'disputes')
EVIDENCE = ('FACT', 'INFERENCE', 'OPEN')
# Report order: settled first, then what needs work.
STATUS_ORDER = ('established', 'agreed', 'contested', 'partial', 'single', 'unsupported', 'refuted')
MAX_CLAIMS, MAX_TEXT, MAX_SOURCES, MAX_SOURCE = 500, 500, 20, 300
ID_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}')
VERDICT_RE = re.compile(r'[A-Z][A-Z_-]{0,15}')
KIND_RE = re.compile(r'[a-z][a-z0-9-]{0,31}')
PROFILE_RE = re.compile(r'@[a-z0-9._-]{1,32}')
OWNER_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9:._@/-]{0,79}')
MAX_INPUT = 4 * 1024 * 1024
# Words that name a model family or vendor, redacted from anonymized filings.
MODEL_WORDS = ('claude', 'codex', 'grok', 'gemini', 'gpt', 'opus', 'sonnet', 'haiku',
               'fable', 'anthropic', 'openai', 'xai', 'chatgpt', 'llama', 'mistral',
               'deepseek', 'qwen', 'glm', 'kimi')
# How a reused pane's context is cleared, per agent kind (the first word sent
# with `herdr agent prompt`; Codex also needs Enter to submit `/new`).
RESET = {'codex': ('/new', True)}
DEFAULT_RESET = ('/clear', False)
IDLE = ('idle', 'done')


class DebateError(Exception):
    def __init__(self, code, message):
        Exception.__init__(self, message)
        self.code, self.message = code, message


def _read_json(path):
    if path == '-':
        import sys
        text = sys.stdin.read(MAX_INPUT + 1)
    else:
        if os.path.islink(path):
            raise DebateError(4, '%s is a symlink; refusing to read it' % path)
        with open(path, encoding='utf-8') as fh:
            text = fh.read(MAX_INPUT + 1)
    if len(text) > MAX_INPUT:
        raise DebateError(4, 'input is larger than %d bytes' % MAX_INPUT)
    try:
        return json.loads(text)
    except ValueError as exc:
        raise DebateError(2, 'not valid JSON: %s' % exc)


# --- tally ------------------------------------------------------------------

def load_ballots(data, exclude=()):
    if not isinstance(data, dict) or data.get('schema') != BALLOTS_SCHEMA:
        raise DebateError(2, 'ballots file must be an object with "schema": "%s"' % BALLOTS_SCHEMA)
    options = data.get('options') or []
    items = data.get('items') or []
    for name, ids in (('options', options), ('items', items)):
        if not isinstance(ids, list) or not all(isinstance(i, str) and ID_RE.fullmatch(i) for i in ids):
            raise DebateError(2, '"%s" must be a list of ids ([A-Za-z0-9._-], at most 64)' % name)
        if len(set(ids)) != len(ids):
            raise DebateError(2, '"%s" has a duplicate id' % name)
    if not options and not items:
        raise DebateError(2, 'nothing to tally: give "options" (ranked) and/or "items" (verdicts)')
    ballots = data.get('ballots')
    if not isinstance(ballots, list) or not ballots:
        raise DebateError(2, '"ballots" must be a non-empty list')
    voters, kept, excluded = set(), [], []
    for b in ballots:
        if not isinstance(b, dict) or not isinstance(b.get('voter'), str) \
                or not ID_RE.fullmatch(b['voter'].replace(':', '-')):
            raise DebateError(2, 'every ballot needs a "voter" id')
        voter = b['voter']
        if voter in voters:
            raise DebateError(2, 'voter %s cast two ballots' % voter)
        voters.add(voter)
        ranking = b.get('ranking', [])
        if not isinstance(ranking, list) or len(set(ranking)) != len(ranking):
            raise DebateError(2, 'voter %s: "ranking" must list each option at most once' % voter)
        unknown = [r for r in ranking if r not in options]
        if unknown:
            raise DebateError(2, 'voter %s ranks an unknown option: %s' % (voter, unknown[0]))
        verdicts = b.get('items', {})
        if not isinstance(verdicts, dict):
            raise DebateError(2, 'voter %s: "items" must map item ids to verdicts' % voter)
        for k, v in verdicts.items():
            if k not in items:
                raise DebateError(2, 'voter %s gives a verdict on an unknown item: %s' % (voter, k))
            if not (isinstance(v, str) and VERDICT_RE.fullmatch(v)):
                raise DebateError(2, 'voter %s: verdict on %s must be an uppercase word '
                                  '(ACCEPT, AMEND, REJECT, ...)' % (voter, k))
        conf = b.get('confidence')
        if conf is not None and not (isinstance(conf, (int, float)) and not isinstance(conf, bool)
                                     and 0 <= conf <= 100):
            raise DebateError(2, 'voter %s: "confidence" must be 0-100' % voter)
        if voter == 'lead' or voter in exclude:
            excluded.append(voter)
            continue
        kept.append({'voter': voter, 'ranking': ranking, 'items': verdicts, 'confidence': conf})
    if not kept:
        raise DebateError(2, 'no ballot left after exclusions')
    return options, items, kept, excluded


def _median(values):
    vals = sorted(values)
    if not vals:
        return None
    mid = len(vals) // 2
    m = vals[mid] if len(vals) % 2 else (vals[mid - 1] + vals[mid]) / 2.0
    return int(m) if float(m).is_integer() else m


def tally(options, items, ballots, excluded=()):
    m = len(options)
    borda = dict((o, 0) for o in options)
    firsts = dict((o, 0) for o in options)
    # wins[a][b]: voters who rank a above b (a ranked option beats an unranked one).
    wins = dict((a, dict((b, 0) for b in options if b != a)) for a in options)
    for b in ballots:
        pos = dict((o, i) for i, o in enumerate(b['ranking']))
        for o, i in pos.items():
            borda[o] += m - 1 - i
        if b['ranking']:
            firsts[b['ranking'][0]] += 1
        for a in options:
            for c in options:
                if a == c:
                    continue
                pa, pc = pos.get(a), pos.get(c)
                if pa is not None and (pc is None or pa < pc):
                    wins[a][c] += 1
    order = sorted(options, key=lambda o: (-borda[o], -firsts[o], options.index(o)))
    ranked = [b for b in ballots if b['ranking']]
    winner = [a for a in options if m > 1 and all(wins[a][c] > wins[c][a] for c in wins[a])]
    loser = [a for a in options if m > 1 and all(wins[a][c] < wins[c][a] for c in wins[a])]
    pairwise = []
    for i, a in enumerate(options):
        for c in options[i + 1:]:
            pairwise.append({'a': a, 'b': c, 'a_over_b': wins[a][c], 'b_over_a': wins[c][a],
                             'winner': a if wins[a][c] > wins[c][a] else
                             c if wins[c][a] > wins[a][c] else None})
    copeland = dict((a, sum(1 for c in wins[a] if wins[a][c] > wins[c][a])
                     - sum(1 for c in wins[a] if wins[a][c] < wins[c][a])) for a in options)
    verdicts = {}
    for it in items:
        counts = {}
        for b in ballots:
            v = b['items'].get(it, 'ABSTAIN')
            counts[v] = counts.get(v, 0) + 1
        verdicts[it] = dict(sorted(counts.items()))
    confs = [b['confidence'] for b in ballots if b['confidence'] is not None]
    return {
        'schema': TALLY_SCHEMA,
        'voters': len(ballots),
        'ranked_ballots': len(ranked),
        'excluded': list(excluded),
        'options': [{'id': o, 'borda': borda[o], 'first_places': firsts[o],
                     'copeland': copeland[o]} for o in order],
        'borda_max': (m - 1) * len(ranked),
        'condorcet_winner': winner[0] if winner else None,
        'condorcet_loser': loser[0] if loser else None,
        'pairwise': pairwise,
        'items': [{'id': it, 'verdicts': verdicts[it]} for it in items],
        'median_confidence': _median(confs),
    }


def render_tally(t):
    lines = ['voters: %d (ranked ballots: %d)%s' % (
        t['voters'], t['ranked_ballots'],
        '; excluded: %s' % ', '.join(t['excluded']) if t['excluded'] else '')]
    if t['options']:
        lines.append('')
        lines.append('%-24s %7s %7s %9s' % ('OPTION', 'BORDA', 'FIRSTS', 'COPELAND'))
        for o in t['options']:
            lines.append('%-24s %7s %7d %+9d' % (o['id'], '%d/%d' % (o['borda'], t['borda_max']),
                                                 o['first_places'], o['copeland']))
        lines.append('')
        lines.append('condorcet winner: %s' % (t['condorcet_winner'] or 'none (no option beats every other)'))
        lines.append('condorcet loser:  %s' % (t['condorcet_loser'] or 'none (no option loses to every other)'))
        lines.append('pairwise:')
        for p in t['pairwise']:
            lines.append('  %s vs %s: %d-%d%s' % (p['a'], p['b'], p['a_over_b'], p['b_over_a'],
                                                 ' (tie)' if p['winner'] is None else ''))
    if t['items']:
        lines.append('')
        lines.append('items:')
        for it in t['items']:
            lines.append('  %-12s %s' % (it['id'], ' '.join('%s %d' % kv for kv in it['verdicts'].items())))
    if t['median_confidence'] is not None:
        lines.append('')
        lines.append('median confidence: %s' % t['median_confidence'])
    return '\n'.join(lines)


# --- anon -------------------------------------------------------------------

def letters(n):
    out = ''
    n += 1
    while n:
        n, r = divmod(n - 1, 26)
        out = chr(65 + r) + out
    return out


def _inside(path, parent):
    path, parent = os.path.realpath(path), os.path.realpath(parent)
    return path == parent or path.startswith(parent.rstrip(os.sep) + os.sep)


def anonymize(src, dst, key, seed=None, redact=(), addr_re=None):
    if not os.path.isdir(src) or os.path.islink(src):
        raise DebateError(2, '%s is not a directory' % src)
    if _inside(dst, src) or _inside(src, dst):
        raise DebateError(4, 'the output directory must not contain or sit inside the filings')
    if _inside(key, dst) or _inside(key, src):
        raise DebateError(4, 'the key file must sit outside both directories: panes read the '
                          'anonymized directory, and the key would undo the blinding')
    if os.path.exists(key) or os.path.islink(key):
        raise DebateError(4, '%s exists; refusing to overwrite a key' % key)
    if os.path.lexists(dst) and (os.path.islink(dst) or not os.path.isdir(dst) or os.listdir(dst)):
        raise DebateError(4, '%s exists and is not an empty directory' % dst)
    names = sorted(n for n in os.listdir(src) if n.endswith('.md')
                   and os.path.isfile(os.path.join(src, n))
                   and not os.path.islink(os.path.join(src, n)))
    if not names:
        raise DebateError(2, 'no .md filings in %s' % src)
    if seed is None:
        seed = '%08d' % random.SystemRandom().randrange(10 ** 8)
    order = list(names)
    random.Random(seed).shuffle(order)
    words = [os.path.splitext(n)[0] for n in names] + list(MODEL_WORDS) + list(redact)
    words = sorted(set(w for w in words if w), key=len, reverse=True)
    word_re = re.compile(r'(?<![A-Za-z0-9])(?:%s)(?:[-.]?[0-9][A-Za-z0-9.]*)?(?![A-Za-z0-9])'
                         % '|'.join(re.escape(w) for w in words), re.I)
    os.makedirs(dst, exist_ok=True)
    mapping, report = {}, []
    for i, name in enumerate(order):
        label = 'Filing_%s' % letters(i)
        with open(os.path.join(src, name), encoding='utf-8', errors='replace') as fh:
            text = fh.read(MAX_INPUT + 1)
        if len(text) > MAX_INPUT:
            raise DebateError(4, '%s is larger than %d bytes' % (name, MAX_INPUT))
        hits = 0
        if addr_re is not None:
            text, n = addr_re.subn('[pane]', text)
            hits += n
        text, n = word_re.subn('[redacted]', text)
        hits += n
        out = os.path.join(dst, label + '.md')
        with open(out, 'w', encoding='utf-8') as fh:
            fh.write('<!-- %s: anonymized filing; author, pane and model names redacted. -->\n\n%s'
                     % (label, text))
        mapping[label] = name
        report.append({'filing': label, 'redactions': hits})
    fd = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as fh:
        json.dump({'schema': 'herdr-peers/anon-key-v1', 'seed': seed, 'map': mapping}, fh,
                  indent=1, sort_keys=True)
        fh.write('\n')
    return {'seed': seed, 'filings': report, 'out': dst, 'key': key}


# --- claims -----------------------------------------------------------------

def _claim_files(paths):
    files = []
    for path in paths:
        if os.path.islink(path):
            raise DebateError(4, '%s is a symlink; refusing to read it' % path)
        if os.path.isdir(path):
            for n in sorted(os.listdir(path)):
                full = os.path.join(path, n)
                if n.endswith('.claims.json') and os.path.isfile(full) and not os.path.islink(full):
                    files.append(full)
        elif os.path.isfile(path):
            files.append(path)
        else:
            raise DebateError(2, '%s is neither a claims file nor a directory' % path)
    if not files:
        raise DebateError(2, 'no claims ledgers found (*.claims.json)')
    return files


def _norm_source(src):
    """A source's identity: its URL or path (the first word, when it is one),
    lowercased, without trailing slashes or a fragment; any other source is
    compared as whole lowercased text. "(read 2026-10-25)" notes do not count."""
    words = src.split()
    head = words[0] if words else ''
    if '://' in head or '/' in head:
        return re.sub(r'/+$', '', head.split('#')[0].lower())
    return ' '.join(words).lower()


def load_claims(paths, aliases=None):
    """Read every lane's ledger; returns {lane: {...}} keyed by canonical claim key."""
    aliases = dict((k.lower(), v.lower()) for k, v in (aliases or {}).items())
    lanes = {}
    for path in _claim_files(paths):
        data = _read_json(path)
        where = os.path.basename(path)
        if not isinstance(data, dict) or data.get('schema') != CLAIMS_SCHEMA:
            raise DebateError(2, '%s: not a %s ledger' % (where, CLAIMS_SCHEMA))
        lane = data.get('lane')
        if not (isinstance(lane, str) and ID_RE.fullmatch(lane.replace(':', '-'))):
            raise DebateError(2, '%s: "lane" must be a lane id' % where)
        if lane in lanes:
            raise DebateError(2, 'lane %s has two ledgers' % lane)
        claims = data.get('claims')
        if not isinstance(claims, list) or len(claims) > MAX_CLAIMS:
            raise DebateError(2, '%s: "claims" must be a list of at most %d' % (where, MAX_CLAIMS))
        vendor = data.get('vendor') if isinstance(data.get('vendor'), str) and \
            ID_RE.fullmatch(data['vendor']) else None
        angle = data.get('angle') if isinstance(data.get('angle'), str) else None
        seen = {}
        for c in claims:
            if not isinstance(c, dict) or not isinstance(c.get('key'), str) \
                    or not ID_RE.fullmatch(c['key']):
                raise DebateError(2, '%s: every claim needs a "key" ([A-Za-z0-9._-])' % where)
            key = c['key'].lower()
            key = aliases.get(key, key)
            if key in seen:
                raise DebateError(2, '%s: claim %s appears twice (after --map)' % (where, key))
            stance = c.get('stance', 'supports')
            if stance not in STANCES:
                raise DebateError(2, '%s: claim %s: "stance" must be supports or disputes' % (where, key))
            evidence = c.get('evidence', 'OPEN')
            if evidence not in EVIDENCE:
                raise DebateError(2, '%s: claim %s: "evidence" must be FACT, INFERENCE or OPEN' % (where, key))
            text = c.get('text', '')
            if not isinstance(text, str) or len(text) > MAX_TEXT:
                raise DebateError(2, '%s: claim %s: "text" must be at most %d characters' % (where, key, MAX_TEXT))
            sources = c.get('sources', [])
            if not isinstance(sources, list) or len(sources) > MAX_SOURCES or not all(
                    isinstance(x, str) and 0 < len(x) <= MAX_SOURCE for x in sources):
                raise DebateError(2, '%s: claim %s: "sources" must be at most %d strings of %d characters'
                                  % (where, key, MAX_SOURCES, MAX_SOURCE))
            conf = c.get('confidence')
            if conf is not None and not (isinstance(conf, (int, float)) and not isinstance(conf, bool)
                                         and 0 <= conf <= 100):
                raise DebateError(2, '%s: claim %s: "confidence" must be 0-100' % (where, key))
            seen[key] = {'stance': stance, 'evidence': evidence, 'text': ' '.join(text.split()),
                         'sources': sources, 'confidence': conf}
        lanes[lane] = {'vendor': vendor, 'angle': angle, 'claims': seen}
    return lanes


def blind_lanes(lanes, seed=None):
    """Rename lanes Lane_A, Lane_B, ... in a seeded random order and drop their
    vendor, so a triangulation round judges claims, not authors."""
    order = sorted(lanes)
    random.Random(seed if seed is not None else random.SystemRandom().random()).shuffle(order)
    return dict(('Lane_%s' % letters(i), dict(lanes[lane], vendor=None))
                for i, lane in enumerate(order))


def merge_claims(lanes, min_lanes=2):
    keys = sorted(set(k for l in lanes.values() for k in l['claims']))
    rows = []
    for key in keys:
        sup, dis, srcs, facts, confs, vendors, statements = [], [], set(), 0, [], set(), []
        for lane in sorted(lanes):
            c = lanes[lane]['claims'].get(key)
            if c is None:
                continue
            statements.append({'lane': lane, 'stance': c['stance'], 'evidence': c['evidence'],
                               'text': c['text'], 'sources': c['sources']})
            if c['stance'] == 'disputes':
                dis.append(lane)
                continue
            sup.append(lane)
            srcs.update(_norm_source(x) for x in c['sources'])
            if c['evidence'] == 'FACT' and c['sources']:
                facts += 1
            if c['confidence'] is not None:
                confs.append(c['confidence'])
            if lanes[lane]['vendor']:
                vendors.add(lanes[lane]['vendor'])
        if sup and dis:
            status = 'contested'
        elif not sup:
            status = 'refuted' if len(dis) >= min_lanes else 'unsupported'
        elif len(sup) >= min_lanes:
            status = 'established' if facts >= 1 and len(srcs) >= 2 else 'agreed'
        else:
            status = 'partial' if len(sup) > 1 else 'single'
        text = next((s['text'] for s in statements if s['stance'] == 'supports' and s['text']),
                    next((s['text'] for s in statements if s['text']), ''))
        rows.append({'key': key, 'status': status, 'text': text, 'supporters': sup,
                     'disputers': dis, 'distinct_sources': len(srcs), 'fact_backed': facts,
                     'vendors': sorted(vendors), 'median_confidence': _median(confs),
                     'statements': statements})
    rows.sort(key=lambda r: (STATUS_ORDER.index(r['status']), -len(r['supporters']),
                             -len(r['disputers']), r['key']))
    counts = dict((st, sum(1 for r in rows if r['status'] == st)) for st in STATUS_ORDER)
    coverage = []
    for lane in sorted(lanes):
        mine = lanes[lane]['claims']
        unique = sorted(k for k in mine if mine[k]['stance'] == 'supports' and all(
            k not in lanes[o]['claims'] for o in lanes if o != lane))
        coverage.append({'lane': lane, 'angle': lanes[lane]['angle'], 'vendor': lanes[lane]['vendor'],
                         'claims': len(mine), 'unique': unique})
    return {'schema': CLAIMS_REPORT_SCHEMA, 'lanes': len(lanes), 'min_lanes': min_lanes,
            'counts': counts, 'claims': rows, 'coverage': coverage}


def render_claims(r):
    lines = ['%d lanes, %d claims (established needs >= %d lanes, a FACT with a source and '
             '>= 2 distinct sources)' % (r['lanes'], len(r['claims']), r['min_lanes']),
             '  ' + '  '.join('%s %d' % (st, r['counts'][st]) for st in STATUS_ORDER), '',
             '%-28s %-12s %4s %4s %4s %5s  %s' % ('CLAIM', 'STATUS', '+', '-', 'SRC', 'CONF', 'TEXT')]
    for c in r['claims']:
        text = c['text'] if len(c['text']) <= 60 else c['text'][:59] + '…'
        lines.append('%-28s %-12s %4d %4d %4d %5s  %s' % (
            c['key'][:28], c['status'], len(c['supporters']), len(c['disputers']),
            c['distinct_sources'], '-' if c['median_confidence'] is None else c['median_confidence'],
            text))
    lines.append('')
    lines.append('coverage:')
    for cv in r['coverage']:
        lines.append('  %-16s %-18s %3d claims, %d only here%s' % (
            cv['lane'], (cv['angle'] or '-')[:18], cv['claims'], len(cv['unique']),
            ' (%s)' % ', '.join(cv['unique'][:5]) + (' …' if len(cv['unique']) > 5 else '')
            if cv['unique'] else ''))
    todo = [c['key'] for c in r['claims'] if c['status'] in ('contested', 'partial', 'single', 'agreed')]
    if todo:
        lines.append('')
        lines.append('next round: verify or cross-examine %s' % ', '.join(todo[:12])
                     + (' …' if len(todo) > 12 else ''))
    return '\n'.join(lines)


# --- filings ----------------------------------------------------------------

def filings(directory, expect, min_words=0):
    if not os.path.isdir(directory):
        raise DebateError(2, '%s is not a directory' % directory)
    rows, expected = [], []
    for e in expect:
        if not ID_RE.fullmatch(e):
            raise DebateError(2, 'expected filing %r is not a plain name' % e)
        name = e if e.endswith('.md') else e + '.md'
        expected.append(name)
        path = os.path.join(directory, name)
        if not os.path.isfile(path) or os.path.islink(path):
            rows.append({'name': name, 'state': 'missing', 'words': 0})
            continue
        with open(path, encoding='utf-8', errors='replace') as fh:
            words = len(fh.read(MAX_INPUT).split())
        rows.append({'name': name, 'words': words,
                     'state': 'short' if words < min_words else 'present'})
    extra = sorted(n for n in os.listdir(directory) if n.endswith('.md') and n not in expected)
    complete = all(r['state'] == 'present' for r in rows)
    return {'schema': FILINGS_SCHEMA, 'dir': directory, 'min_words': min_words,
            'complete': complete, 'filings': rows, 'unexpected': extra}


def render_filings(f):
    lines = ['%-28s %-8s %s' % ('FILING', 'STATE', 'WORDS')]
    for r in f['filings']:
        lines.append('%-28s %-8s %d' % (r['name'], r['state'], r['words']))
    if f['unexpected']:
        lines.append('unexpected: %s' % ', '.join(f['unexpected']))
    todo = [r['name'] for r in f['filings'] if r['state'] != 'present']
    lines.append('complete' if f['complete'] else
                 'incomplete: re-ask only %s (read every other filing from disk)' % ', '.join(todo))
    return '\n'.join(lines)


# --- panel ------------------------------------------------------------------

def ak_pick(kind, count, owner, run=None):
    """Accounts with headroom for KIND from `ak pick` (pick-v1), best first."""
    cmd = ['ak', 'pick', kind, '--count', str(count), '--allow-unknown', '--json']
    if owner:
        cmd += ['--owner', owner]
    try:
        proc = (run or subprocess.run)(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return [], 'ak pick %s failed: %s' % (kind, exc.__class__.__name__)
    try:
        data = json.loads(proc.stdout.decode('utf-8', 'replace'))
    except ValueError:
        return [], 'ak pick %s: exit %d, no JSON' % (kind, proc.returncode)
    if not isinstance(data, dict) or data.get('schema') != 'pick-v1' or data.get('interface') != 1:
        return [], 'ak pick %s: not a pick-v1 (interface 1) document' % kind
    chosen = []
    for c in data.get('chosen') or []:
        if isinstance(c, dict) and isinstance(c.get('profile'), str) and PROFILE_RE.fullmatch(c['profile']):
            chosen.append({'profile': c['profile'],
                           'headroom_pct': c.get('headroom_pct') if isinstance(c.get('headroom_pct'), (int, float)) else None,
                           'verdict': c.get('verdict') if isinstance(c.get('verdict'), str) else None})
    note = None
    if not chosen:
        reset = data.get('soonest_reset')
        note = 'ak pick %s: no account qualifies%s' % (
            kind, ' (soonest reset %s)' % reset if isinstance(reset, str) and len(reset) < 40 else '')
    return chosen, note


def reset_commands(kind, pane):
    word, enter = RESET.get(kind, DEFAULT_RESET)
    cmds = ['herdr agent prompt %s %s' % (pane, word)]
    if enter:
        cmds.append('herdr pane send-keys %s Enter' % pane)
    return cmds


# Model provider per agent kind; an agentkit kind like codex-xai runs another
# provider's models through that CLI, so its suffix wins.
PROVIDERS = {'claude': 'anthropic', 'codex': 'openai', 'grok': 'xai', 'gemini': 'google',
             'antigravity': 'google', 'cursor': 'cursor', 'opencode': 'opencode', 'pi': 'pi',
             'cline': 'cline'}
PROVIDER_SUFFIXES = {'xai': 'xai', 'glm': 'zhipu', 'azure': 'azure-openai'}


def provider_of(kind):
    base, _, suffix = kind.partition('-')
    return PROVIDER_SUFFIXES.get(suffix) or PROVIDERS.get(base, kind)


def _new_seat(kind, acct, owner, n, cwd):
    launch = 'ak %s %s --trust-cwd' % (kind, acct['profile'])
    return {
        'source': 'new', 'kind': kind, 'provider': provider_of(kind), 'profile': acct['profile'],
        'headroom_pct': acct['headroom_pct'], 'verdict': acct['verdict'],
        'commands': [
            'ak lease %s %s --owner %s --ttl 12h --purpose debate' % (kind, acct['profile'], owner),
            'herdr pane split --current --direction right --cwd %s --no-focus '
            '--env HERDR_PEERS_BRIEFER=%s   # -> new pane id <pane%d>' % (shlex.quote(cwd), owner, n),
            'herdr pane run <pane%d> "%s"' % (n, launch),
        ],
        'release': 'ak lease release %s %s --owner %s' % (kind, acct['profile'], owner),
    }


def _pct(cap):
    return cap.get('headroom_pct') if isinstance(cap, dict) and \
        isinstance(cap.get('headroom_pct'), (int, float)) else None


def plan_panel(agents, me, seats, kinds, owner, busy=(), all_workspaces=False, use_ak=True,
               pick=None, cwd='.', capacity=None):
    """Seat a panel with as many model providers as are available: seats go
    round-robin over providers (in --kinds order, then any other idle kind);
    within a provider the seat with the most quota goes first: idle panes
    whose last reported capacity is ok or unknown (most headroom first), then
    new panes on the accounts `ak pick` ranks highest, then idle panes that
    reported low capacity. A pane that reported critical is never seated.
    CAPACITY maps a pane id to its last `capacity=` report."""
    capacity = capacity or {}
    workspace = me.split(':')[0]
    idle, skipped = [], []
    for a in agents:
        pane = a.get('pane_id')
        if not isinstance(pane, str) or pane == me or a.get('agent_status') not in IDLE:
            continue
        if not all_workspaces and pane.split(':')[0] != workspace:
            continue
        if pane in busy:
            skipped.append(pane)
            continue
        kind = a.get('agent') if isinstance(a.get('agent'), str) and KIND_RE.fullmatch(a['agent']) else 'unknown'
        idle.append((kind, pane))
    notes, exhausted = [], []
    verdict = lambda pane: (capacity.get(pane) or {}).get('verdict')
    exhausted = sorted(p_ for _, p_ in idle if verdict(p_) == 'critical')
    idle = [(k, p_) for k, p_ in idle if verdict(p_) != 'critical']
    # Most reported headroom first; unknown after any known ok; low last.
    idle.sort(key=lambda kp: (verdict(kp[1]) == 'low', _pct(capacity.get(kp[1])) is None,
                              -(_pct(capacity.get(kp[1])) or 0)))
    if exhausted:
        notes.append('not seated (reported critical capacity): %s' % ', '.join(exhausted))
    if skipped:
        notes.append('not reused (another plan\'s lead or lane, or --exclude): %s'
                     % ', '.join(sorted(skipped)))
    # Per provider: a queue of idle panes, then (lazily) accounts from ak pick.
    order = []
    for kind in list(kinds) + sorted(set(k for k, _ in idle)):
        prov = provider_of(kind)
        if prov not in order:
            order.append(prov)
    panes = dict((p, [(k, pane) for k, pane in idle
                      if provider_of(k) == p and verdict(pane) != 'low']) for p in order)
    low = dict((p, [(k, pane) for k, pane in idle
                    if provider_of(k) == p and verdict(pane) == 'low']) for p in order)
    ak = use_ak and (pick is not None or shutil.which('ak'))
    accounts, picked = dict((p, []) for p in order), set()

    def fetch(prov):
        for kind in kinds:
            if provider_of(kind) == prov and kind not in picked:
                picked.add(kind)
                chosen, note = (pick or ak_pick)(kind, seats, owner)
                accounts[prov].extend((kind, c) for c in chosen)
                if note:
                    notes.append(note)

    reuse, new = [], []
    while len(reuse) + len(new) < seats:
        progressed = False
        for prov in order:
            if len(reuse) + len(new) >= seats:
                break
            if panes[prov]:
                kind, pane = panes[prov].pop(0)
            else:
                if ak and not accounts[prov]:
                    fetch(prov)
                if accounts[prov]:
                    kind, acct = accounts[prov].pop(0)
                    new.append(_new_seat(kind, acct, owner, len(new) + 1, cwd))
                    progressed = True
                    continue
                if not low[prov]:
                    continue
                kind, pane = low[prov].pop(0)
            reuse.append({'source': 'reuse', 'kind': kind, 'provider': prov, 'pane': pane,
                          'address': 'local:%s' % pane, 'reset': reset_commands(kind, pane),
                          'capacity': capacity.get(pane)})
            progressed = True
        if not progressed:
            break
    unfilled = seats - len(reuse) - len(new)
    if unfilled and not ak:
        notes.append('agentkit (ak) is not installed — recommended: coding-agents-kit (v1.0.1 or later) adds account quota (ak usage, ak pick), leases and one-command launches per account, so a panel gets more providers and the seats with the most quota. Without it, start %d more agent(s) with '
                     '`herdr agent start <name> --kind <kind> --pane <id>` (launcher.md), '
                     'or seat fewer panes' % unfilled if use_ak else
                     '%d seat(s) left unfilled (--no-ak)' % unfilled)
    elif unfilled:
        notes.append('%d seat(s) left unfilled: no more idle panes or accounts with headroom'
                     % unfilled)
    seated = reuse + new
    mix, providers = {}, {}
    for s_ in seated:
        mix[s_['kind']] = mix.get(s_['kind'], 0) + 1
        providers[s_['provider']] = providers.get(s_['provider'], 0) + 1
    largest = max(providers.values()) if providers else 0
    diverse = len(seated) < 2 or (len(providers) >= min(3, len(seated))
                                  and largest * 2 <= len(seated))
    if seated and not diverse:
        notes.append('low provider diversity (%d provider(s), largest share %d of %d): add '
                     'another provider\'s agents if any are available, or say so in the '
                     'deliverable' % (len(providers), largest, len(seated)))
    # Successors: the seats with the most known headroom, other providers
    # preferred when the headroom ties, so the debate outlives its lead.
    ranked = sorted(
        [(_pct(s_.get('capacity')), s_['address']) for s_ in reuse] +
        [(s_['headroom_pct'], 'local:<pane%d>' % (i + 1)) for i, s_ in enumerate(new)],
        key=lambda t: -(t[0] if isinstance(t[0], (int, float)) else -1))
    succession = [addr for pct, addr in ranked if isinstance(pct, (int, float))][:2]
    return {'schema': PANEL_SCHEMA, 'lead': owner, 'seats': seats, 'filled': len(seated),
            'reuse': reuse, 'new': new, 'mix': dict(sorted(mix.items())),
            'providers': dict(sorted(providers.items())), 'diverse': diverse,
            'succession': succession, 'notes': notes, 'executed': False}


def render_panel(p):
    lines = ['panel for %s: %d of %d seats (providers: %s; kinds: %s)' % (
        p['lead'], p['filled'], p['seats'],
        ', '.join('%s %d' % kv for kv in p['providers'].items()) or 'none',
        ', '.join('%s %d' % kv for kv in p['mix'].items()) or 'none')]
    if p['reuse']:
        lines.append('')
        lines.append('reuse idle panes (idle is not free: confirm each with the human, '
                     'then clear its context before the brief):')
        for s in p['reuse']:
            cap = s.get('capacity') or {}
            lines.append('  %-16s %-8s %-14s %s' % (
                s['address'], s['kind'],
                '%s %s%%' % (cap.get('verdict'), cap.get('headroom_pct'))
                if cap.get('headroom_pct') is not None else (cap.get('verdict') or 'quota unknown'),
                ' ; '.join(s['reset'])))
    if p['new']:
        lines.append('')
        lines.append('new panes (only with the human\'s go-ahead):')
        for s in p['new']:
            lines.append('  %s %s (headroom %s%%, %s)' % (
                s['kind'], s['profile'], s['headroom_pct'] if s['headroom_pct'] is not None else '?',
                s['verdict'] or 'unknown'))
            for c in s['commands']:
                lines.append('    %s' % c)
            lines.append('    at close: %s' % s['release'])
    if p['succession']:
        lines.append('')
        lines.append('successors (most quota): herdr-peers lead claim --plan <id> --lanes <seats> '
                     '--succession %s' % ','.join(p['succession']))
    for n in p['notes']:
        lines.append('note: %s' % n)
    lines.append('')
    lines.append('A proposal only: nothing was reset, launched or leased.')
    return '\n'.join(lines)
