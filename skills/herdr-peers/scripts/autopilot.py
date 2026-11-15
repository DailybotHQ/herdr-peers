"""herdr-peers autopilot — answer every waiting agent (stdlib only).

A human starts it once. It watches every agent on every enabled Herdr
machine and, when one waits at a question, an approval or a first-run
screen, accepts the option that lets it go on. An agent that ended its turn
asking in prose is told to continue. See ../orchestra.md §8.

Two layers:

  decide()   pure: (agent kind, Herdr state, visible screen) -> Decision.
             No I/O. Everything it knows about a screen is in this file.
  Autopilot  the loop: list agents, read a screen only when needed, key,
             re-read to confirm, record.

A screen is text written by an agent: it is matched against anchored
patterns and never executed, echoed or logged. The log carries the class,
the name of what matched, the option index and the keys.
"""
from __future__ import annotations

import hashlib
import re
import time
from concurrent.futures import ThreadPoolExecutor

SCHEMA = 'herdr-peers/autopilot-v1'
DEFAULT_INTERVAL = 60
MIN_INTERVAL = 15
MAX_STEPS = 8            # keys-then-reread rounds on one pane in one pass
MAX_ATTEMPTS = 2         # rounds without progress before a screen is left
MAX_NUDGES = 3           # prompts to one pane within NUDGE_WINDOW
NUDGE_WINDOW = 3600      # seconds; a pane that keeps asking is left after MAX_NUDGES
LIMIT_RETRY = 1800       # seconds between two tries on a pane at its usage limit
CONFIRM_DELAY = 1.5      # seconds between keys and the confirming re-read
TAIL = 40                # screen lines a decision looks at
BACKOFF_MAX = 8          # passes an unreachable machine is skipped, at most

NUDGE_TEXT = (
    '[autopilot] The developer is away and has pre-approved the recommended option for every '
    'pending decision. Continue autonomously: for each open question, take the option you '
    'recommended; where you recommended none, choose the one that best fits this repository\'s '
    'guidelines and the active plan, and record the choice. Do not wait for the developer '
    'again. If an item truly needs something only the developer can provide (a credential, a '
    'login, a fact you cannot verify), leave only that item pending, finish everything else, '
    'and list it at the end.')
RESUME_TEXT = (
    '[autopilot] Your usage limit may have reset. Continue the pending plan to its end from '
    'where you stopped, taking the recommended option at every decision. If the limit is '
    'still in force, stop and wait; you will be asked again later.')

BOX = {ord(c): ' ' for c in '│┃█'}
CURSORS = '❯›>→▶'
ROW_NUM = re.compile(r'^(?P<ind>\s*)(?:(?P<cur>[%s])\s+)?(?P<num>\d{1,2})[.)]\s+(?P<rest>\S.*)$'
                     % CURSORS)
ROW_RADIO = re.compile(r'^(?P<ind>\s*)(?P<num>\d{1,2}|[a-z])\s+\((?P<radio>[○●◯◉])\)\s+'
                       r'(?P<rest>\S.*)$')
ROW_CUR = re.compile(r'^(?P<ind>\s*)(?P<cur>[%s])\s+(?P<rest>\S.*)$' % CURSORS)
CHECK = re.compile(r'^\[(?P<mark>[ xX✔✓])\]\s+(?P<rest>\S.*)$')
RULE = re.compile(r'^[\s─━═╌▔▀▄_\-╭╮╰╯]{6,}$')

HINT = re.compile(r'(?i)enter\s*(?:to\s+)?(?:select|confirm|submit)|enter:\s*(?:select|submit|confirm)|'
                  r'press enter')
RECOMMENDED = re.compile(r'\(recommended\)', re.I)
# Rows that refuse, leave, or open free text: never chosen.
NEGATIVE = re.compile(
    r'^(?:\[[a-z]\]\s+)?(?:no\b|never\b|cancel\b|quit\b|exit\b|skip &|do not\b|don\'t\b|deny\b|'
    r'reject\b|type something|type your answer|other\b|chat about|tell \w+ what|write-in)',
    re.I)
# Rows that widen the agent's standing permissions: never chosen. Autopilot
# accepts one action; it does not change an agent's permission policy.
WIDENING = re.compile(
    r'always allow|don\'t ask again|run everything|always-approve|persist to settings|'
    r'switch to auto mode|switch to accept edits|to allowlist|trust parent folder|'
    r'extra usage|upgrade', re.I)

# name -> patterns; the first match decides. A screen is data.
LOGIN = [r'Select login method', r'Sign in with ChatGPT', r'Log ?in with', r'Paste (the )?code here',
         r'Please run /login', r'Invalid API key', r'Provide your own API key',
         r'(?i)authentication (required|failed)', r'(?i)enter (your )?(api key|password|token)',
         r'(?i)please sign in again', r'(?i)access token could not be refreshed']
LIMIT = [r"(?m)^[^\w>\n]{0,3}[ \t]*You['’]ve hit your (?:[\w-]+ )?limit\b",
         r'(?mi)^[^\w>\n]{0,3}[ \t]*(?:Claude )?usage limit reached\b',
         r'(?mi)^[^\w>\n]{0,3}[ \t]*(?:[\w-]+ )?limit reached[ \t]*[·∙•|-][ \t]*resets\b',
         r'(?mi)^[^\w>\n]{0,3}[ \t]*(?:API )?Error:?[ \t]*(?:429\b|rate limit (?:reached|exceeded)\b)',
         r'(?mi)^[^\w>\n]{0,3}[ \t]*rate limit (?:reached|exceeded)\b']
BYPASS = [r'Bypass Permissions mode', r'Yes, I accept']
TRUST = [r'Do you trust the (files|contents) (in|of) this (folder|directory|project)',
         r'Is this a project you created or one you trust', r'(Do you t|T)rust this folder\?',
         r'allow Codex to work in this folder', r'Trust this workspace',
         r'(?m)^\s*Do not trust\s*$']
UPDATE = [r'(?i)update available', r'(?i)a new version .* is available']
PLAN = [r'Would you like to proceed\?', r'Ready to code\?']
REVIEW = [r'Ready to submit your answers\?']
QUEUED = [r'shift\+← to answer']
# Named classes that may be keyed whatever Herdr's state says: each is
# anchored on its own text, so it does not lean on Herdr's detection.
ANCHORED = (('folder_trust', TRUST), ('update_prompt', UPDATE), ('plan_approval', PLAN),
            ('question_review', REVIEW))
PERMISSION = [r'Do you want to (proceed|make this edit|create|run|allow)', r'Run this command\?',
              r'Would you like to (run|make|apply)', r'Allow (command|once|this|creation)',
              r'Requesting permission', r'(?i)approve (this|the) ', r'Not in allowlist',
              r'(?i)permission (request|required)']

# A turn that finished: only such a pane can be asked to continue.
TURN_DONE = re.compile(r'(?m)^\s*(?:[✻✽✢✶·*]\s+\w+ for \d|Worked for \d|Took \d)')
# An empty input line or a CLI's own placeholder; anything else typed there
# is a human's draft and the pane is left alone.
PLACEHOLDERS = re.compile(
    r'^(?:|Ask Codex to do anything|Add a follow-up|Plan, search, build anything|'
    r'Ask anything.*|Try ".*)$')
INPUT_ROW = re.compile(r'^\s*[%s]\s?(?P<text>.*)$' % CURSORS)
ASKS = re.compile(
    r'[?？]\s*$|(?i:\b(?:let me know|tell me|your call|which (?:option|one)|should i\b|'
    r'do you want|waiting (?:for|on) you|please (?:choose|pick|select|confirm|advise)|'
    r'i[\'’]ll wait|once you (?:confirm|decide|choose)|dime\b|quieres que|espero tu|me dices|decide[sn]?\b|'
    r'confirm(?:a|as|e)?\b))')
CHROME = re.compile(r'shift\+tab|for shortcuts|/effort|esc to interrupt|bypass permissions|'
                    r'new task\?|Update installed|ctrl\+|recap:|Tip:|· /|tokens|\d+%')


class Decision(object):
    """What autopilot does with one screen. `action` is `keys`, `prompt`,
    `leave` (recognised, deliberately untouched) or `none`."""

    def __init__(self, action, cls, why, keys=None, option=None, text=None):
        self.action, self.cls, self.why = action, cls, why
        self.keys, self.option, self.text = keys or [], option, text

    def as_dict(self):
        out = {'action': self.action, 'class': self.cls, 'why': self.why}
        if self.keys:
            out['keys'] = self.keys
        if self.option is not None:
            out['option'] = self.option
        return out


def tail_lines(text, count=TAIL):
    lines = [ln.translate(BOX).rstrip() for ln in (text or '').splitlines()]
    while lines and not lines[-1].strip():
        lines.pop()
    return lines[-count:]


def first_match(patterns, text):
    """The first pattern found in `text`, also tried on the text with its
    line breaks folded: a narrow pane wraps a phrase across two lines."""
    flat = re.sub(r'\s+', ' ', text)
    for pattern in patterns:
        if re.search(pattern, text) or re.search(pattern, flat):
            return pattern
    return None


def _row(label, selected, num=None):
    check = CHECK.match(label)
    return {'label': check.group('rest') if check else label, 'selected': selected, 'num': num,
            'checked': None if not check else check.group('mark') != ' '}


def parse_menu(text):
    """The option block lowest on the screen, or None.

    Returns {'style', 'rows': [{'label', 'selected', 'num', 'checked'}],
    'first', 'last' (line indexes in the tail), 'below' (non-empty lines
    under the block), 'hint' (a line under it says Enter selects)}.
    A block needs two option rows and a selection mark: a cursor glyph on
    one row, or radio marks on all of them. A numbered list in an agent's
    prose has neither and is not a menu.
    """
    lines = tail_lines(text)
    for end in range(len(lines) - 1, -1, -1):
        menu = _menu_at(lines, end)
        if menu:
            return menu
    return None


def _menu_at(lines, at):
    line = lines[at]
    radio, numbered, cursor = ROW_RADIO.match(line), ROW_NUM.match(line), ROW_CUR.match(line)
    if radio:
        return _collect(lines, at, 'radio')
    if numbered and numbered.group('cur'):
        return _collect(lines, at, 'numbered')
    if cursor and not numbered:
        return _collect(lines, at, 'plain', cursor.start('rest'))
    return None


def _collect(lines, at, style, column=None):
    """Walk up and down from the row at `at`, gathering its sibling rows."""
    def parse(index):
        line = lines[index]
        if style == 'radio':
            m = ROW_RADIO.match(line)
            return _row(m.group('rest'), m.group('radio') in '●◉', m.group('num')) if m else None
        if style == 'numbered':
            m = ROW_NUM.match(line)
            return _row(m.group('rest'), bool(m.group('cur')), m.group('num')) if m else None
        m = ROW_CUR.match(line)
        if m and not ROW_NUM.match(line):
            return _row(m.group('rest'), True)
        if len(line) > column and not line[:column].strip() and line[column] != ' ':
            return _row(line[column:], False)
        return None

    span = [at, at]

    def walk(step):
        found, index, misses = [], at + step, 0
        while 0 <= index < len(lines) and misses <= 3:
            line = lines[index]
            if not line.strip() or RULE.match(line):
                if style != 'numbered' or not line.strip():
                    break
                index += step
                continue
            row = parse(index)
            if row:
                found.append(row)
                misses = 0
                span[0], span[1] = min(span[0], index), max(span[1], index)
            else:
                misses += 1  # a wrapped label or a description line
            index += step
        return found

    here = parse(at)
    if not here:
        return None
    rows = list(reversed(walk(-1))) + [here] + walk(1)
    if style == 'numbered':
        rows = _ascending(rows)
    if len(rows) < 2:
        return None
    if style != 'radio' and sum(1 for r in rows if r['selected']) != 1:
        return None
    under = [ln for ln in lines[span[1] + 1:] if ln.strip()]
    return {'style': style, 'rows': rows, 'first': span[0], 'last': span[1],
            'below': len(under), 'hint': any(HINT.search(ln) for ln in under[:5])}


def _ascending(rows):
    """Keep the run of numbered rows whose numbers go up by one."""
    out = []
    for row in rows:
        if out and int(row['num']) != int(out[-1]['num']) + 1:
            if any(r['selected'] for r in out):
                break
            out = []
        out.append(row)
    return out


def acceptable(row):
    return not NEGATIVE.match(row['label']) and not WIDENING.search(row['label'])


def choose(menu, prefer=None):
    """Index of the row to accept, or None.

    Order: a class's own preference, the row marked recommended, the row the
    CLI pre-selected, the first row — skipping refusals, free text and rows
    that widen the agent's permissions.
    """
    rows = menu['rows']
    order = []
    if prefer:
        order += [i for i, r in enumerate(rows) if prefer.search(r['label'])]
    order += [i for i, r in enumerate(rows) if RECOMMENDED.search(r['label'])]
    order += [i for i, r in enumerate(rows) if r['selected']]
    order += list(range(len(rows)))
    for index in order:
        if acceptable(rows[index]) or (prefer and prefer.search(rows[index]['label'])):
            return index
    return None


def keys_for(menu, target):
    rows = menu['rows']
    current = next((i for i, r in enumerate(rows) if r['selected']), 0)
    if any(r['checked'] is not None for r in rows):
        # Multi-select: Enter toggles and stays, so toggle once, then leave.
        if any(r['checked'] for r in rows):
            return ['tab']
    move = ['down'] * (target - current) if target >= current else ['up'] * (current - target)
    return move + ['enter']


def menu_decision(menu, cls, why, prefer=None):
    target = choose(menu, prefer)
    if target is None:
        return Decision('leave', cls, 'no acceptable option')
    return Decision('keys', cls, why, keys_for(menu, target), target + 1)


LOGIN_ROW = re.compile(r'(?i)sign in|log ?in|api key|chatgpt|console account|subscription')
NEAR = 14          # an anchor counts only this close above its menu
FOOTER_MAX = 6     # a live menu sits at the bottom: few lines under it


def live(menu, state):
    """Is this block a menu that waits now? It must sit at the bottom of the
    screen. A block of unnumbered rows looks exactly like an agent's input
    line with wrapped text under it, so outside a blocked state it also
    needs a line saying that Enter selects — otherwise an Enter could send a
    human's half-written message."""
    if menu['below'] > FOOTER_MAX:
        return False
    return menu['style'] != 'plain' or state == 'blocked' or menu['hint']


def near_menu(patterns, lines, menu):
    """An anchored class counts only when its text sits right above a menu
    that is at the bottom of the screen — not somewhere in old scrollback."""
    if menu['below'] > FOOTER_MAX:
        return None
    return first_match(patterns, '\n'.join(lines[max(0, menu['first'] - NEAR):menu['last'] + 4]))


def decide(agent, state, text):
    """The action for one pane. Pure: no I/O, nothing from `text` is run."""
    lines = tail_lines(text)
    tail = '\n'.join(lines)
    menu = parse_menu(text)
    labels = [r['label'] for r in menu['rows']] if menu else []
    hit = first_match(LOGIN, tail)
    if hit and (not menu or any(LOGIN_ROW.search(label) for label in labels)):
        return Decision('leave', 'login', hit)
    if any(re.search(r'Yes, I accept', label) for label in labels):
        return Decision('leave', 'bypass_ack', 'Yes, I accept')
    if first_match(QUEUED, tail) and not menu:
        return Decision('keys', 'queued_question', 'shift+← to answer', ['shift+left'])
    hit = first_match(LIMIT, '\n'.join(lines[-15:]))
    if hit:
        return Decision('leave', 'usage_limit', hit)
    if menu and not live(menu, state):
        menu = None
    if menu:
        for cls, patterns in ANCHORED:
            hit = near_menu(patterns, lines, menu)
            if not hit:
                continue
            if cls == 'update_prompt':
                skip = re.compile(r'^skip\b', re.I)
                if not any(skip.search(label) for label in labels):
                    continue  # a passive banner, not a prompt
                return menu_decision(menu, cls, hit, skip)
            return menu_decision(menu, cls, hit)
        if state == 'blocked':
            hit = near_menu(PERMISSION, lines, menu)
            return menu_decision(menu, 'permission' if hit else 'question', hit or 'menu')
        return Decision('none', 'none', 'no live menu of a known class')
    if state == 'blocked':
        return Decision('leave', 'unknown', 'blocked without a recognised menu')
    return Decision('none', 'none', 'nothing waits')


def input_text(lines):
    """Text on the agent's input line, '' when empty, None when not found."""
    for line in reversed(lines[-8:]):
        m = INPUT_ROW.match(line)
        if m:
            return m.group('text').strip()
    return ''


def asks_in_prose(text):
    """True when a finished turn ends by asking the human something."""
    lines = tail_lines(text, 30)
    body = '\n'.join(lines)
    if not TURN_DONE.search(body):
        return False
    draft = input_text(lines)
    if draft is None or not PLACEHOLDERS.match(draft):
        return False  # a human is typing there
    said = [ln for ln in lines if ln.strip() and not RULE.match(ln) and not CHROME.search(ln)
            and not INPUT_ROW.match(ln) and not TURN_DONE.search(ln)]
    return any(ASKS.search(ln) for ln in said[-5:])


def screen_digest(text):
    return hashlib.sha256('\n'.join(tail_lines(text)).encode('utf-8', 'replace')).hexdigest()[:16]


def engaged(text):
    """A dialog autopilot is already inside: a numbered or radio block, or
    one that says Enter selects. Never a bare block of unnumbered rows —
    that is what an input line with wrapped text looks like."""
    menu = parse_menu(text)
    return bool(menu) and (menu['style'] != 'plain' or menu['hint'])


class Pane(object):
    """What the loop remembers about one pane between passes (memory only)."""

    def __init__(self):
        self.state = None
        self.seq = None        # Herdr's state_change_seq at the last pass
        self.turn = None       # Herdr's completion_seq when last seen or prompted
        self.seen_working = False
        self.nudges = []       # times of the prompts sent to it
        self.limit_at = 0.0
        self.left = None       # digest of a screen autopilot gave up on


class Autopilot(object):
    """The loop. `io` supplies Herdr and the record writer, so the loop is
    testable and this module never imports the helper."""

    def __init__(self, io, dry_run=False, nudge=True, catch_up=False, exclude=(),
                 clock=time.time, sleep=time.sleep, confirm=CONFIRM_DELAY):
        self.io, self.dry_run, self.nudge, self.catch_up = io, dry_run, nudge, catch_up
        self.exclude = set(exclude)
        self.clock, self.sleep, self.confirm = clock, sleep, confirm
        self.panes = {}
        self.backoff = {}      # machine -> [passes to skip, last penalty]
        self.first_pass = True
        self.actions = 0

    # -- one pass ---------------------------------------------------------
    def run_pass(self):
        sources = self.io.sources()
        due = []
        for machine in sources:
            wait = self.backoff.get(machine)
            if wait and wait[0] > 0:
                wait[0] -= 1
                continue
            due.append(machine)
        with ThreadPoolExecutor(max_workers=min(8, max(1, len(due)))) as pool:
            listed = list(pool.map(self.io.agents, due))
        seen = set()
        for machine, agents in zip(due, listed):
            if agents is None:
                penalty = min(BACKOFF_MAX, (self.backoff.get(machine) or [0, 0])[1] * 2 or 1)
                self.backoff[machine] = [penalty, penalty]
                continue
            self.backoff.pop(machine, None)
            for agent in agents:
                addr = '%s:%s' % (machine, agent['pane'])
                seen.add(addr)
                if agent.get('you') or addr in self.exclude:
                    continue
                self.visit(machine, agent, addr)
        for addr in [a for a in self.panes if a not in seen
                     and a.split(':', 1)[0] in due]:
            del self.panes[addr]
        self.first_pass = False

    def visit(self, machine, agent, addr):
        memo = self.panes.setdefault(addr, Pane())
        state, before, fresh = agent.get('state'), memo.state, memo.state is None
        changed = state != before or agent.get('seq') != memo.seq
        memo.state, memo.seq = state, agent.get('seq')
        if fresh:
            memo.turn = agent.get('turn')
        elif agent.get('turn') != memo.turn:
            memo.seen_working, memo.turn = True, agent.get('turn')  # a turn finished meanwhile
        if state == 'working':
            memo.seen_working, memo.left = True, None
            return
        limit_due = memo.limit_at and self.clock() - memo.limit_at >= LIMIT_RETRY
        if state != 'blocked' and not changed and not limit_due:
            return  # an idle pass reads no pane
        self.attend(machine, agent, addr, memo, fresh)

    def attend(self, machine, agent, addr, memo, fresh):
        pane, kind = agent['pane'], agent.get('agent')
        attempts, last = 0, None
        for _step in range(MAX_STEPS):
            text = self.io.read(machine, pane)
            if text is None:
                return
            digest = screen_digest(text)
            if digest == memo.left:
                return
            if digest == last:
                attempts += 1
                if attempts >= MAX_ATTEMPTS:
                    memo.left = digest
                    self.record(addr, kind, Decision('leave', 'stuck', 'no progress'), 'gave_up')
                    return
            else:
                attempts = 0
            last = digest
            state = self.io.state(machine, pane) if _step else agent.get('state')
            if state == 'working':
                return
            # Once a dialog was keyed, its next step is part of the same
            # dialog even when Herdr briefly reports another state.
            choice = decide(kind, 'blocked' if _step and engaged(text) else state, text)
            if choice.action == 'keys':
                self.record(addr, kind, choice, 'keyed')
                if self.dry_run:
                    return
                if not self.io.keys(machine, pane, choice.keys):
                    return
                self.sleep(self.confirm)
                continue
            if choice.cls == 'usage_limit':
                self.limit(machine, pane, addr, kind, memo, choice, text)
            elif choice.action == 'leave':
                if memo.left != digest:
                    memo.left = digest
                    self.record(addr, kind, choice, 'left')
            elif state in ('idle', 'done'):
                self.maybe_nudge(machine, pane, addr, kind, memo, text, fresh)
            return

    def limit(self, machine, pane, addr, kind, memo, choice, text):
        """A pane at its usage limit: noted once, then tried again every
        LIMIT_RETRY seconds — accept the menu if one is shown, then ask it to
        go on."""
        now = self.clock()
        if not memo.limit_at:
            memo.limit_at = now
            self.record(addr, kind, choice, 'left')
            return
        if now - memo.limit_at < LIMIT_RETRY:
            return
        memo.limit_at = now
        menu = parse_menu(text)
        target = choose(menu) if menu and menu['below'] <= FOOTER_MAX else None
        keys = keys_for(menu, target) if target is not None else []
        self.record(addr, kind, Decision('prompt', 'usage_limit', 'retry after the wait', keys,
                                         None if target is None else target + 1), 'nudged')
        if self.dry_run:
            return
        if keys:
            self.io.keys(machine, pane, keys)
            self.sleep(self.confirm)
        self.io.prompt(machine, pane, RESUME_TEXT)

    def maybe_nudge(self, machine, pane, addr, kind, memo, text, fresh):
        if not self.nudge:
            return
        if fresh and not self.catch_up:
            return  # stopped before autopilot started: not ours to restart
        if not fresh and not memo.seen_working:
            return  # no turn of its own since the last prompt
        now = self.clock()
        memo.nudges = [t for t in memo.nudges if now - t < NUDGE_WINDOW]
        if len(memo.nudges) >= MAX_NUDGES:
            return
        if not asks_in_prose(text):
            return
        memo.nudges.append(now)
        memo.seen_working = False
        self.record(addr, kind, Decision('prompt', 'prose_question', 'turn ended asking'),
                    'nudged')
        if not self.dry_run:
            self.io.prompt(machine, pane, NUDGE_TEXT)

    def record(self, addr, kind, choice, outcome):
        self.actions += 1
        self.io.record(addr, kind, choice, outcome, self.dry_run)
