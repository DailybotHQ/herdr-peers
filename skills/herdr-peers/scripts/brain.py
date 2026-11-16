"""herdr-peers autopilot brain — a dedicated decision agent (stdlib only).

With `autopilot --loop --brain` the daemon launches one agent of its own,
the brain, and asks it only what its rules cannot decide. The brain never
acts: it chooses one action from a closed list per case and says so with
`herdr-peers autopilot answer <question> <action>`, run in its own pane.
The daemon checks the answer and runs the action through its own code.

Pure parts live here: checking `ak pick` output (pick-v2) and turning it
into the line typed into a fresh shell, the cases and their action lists,
the fixed texts, the blocker guard, and reading answers. The I/O (ak,
Herdr, files) is the helper's AutopilotIO, so this module never runs a
command itself.
"""
import json
import re
import shlex
import time

PICK_SCHEMA = 'pick-v2'
WORKSPACE_LABEL = 'autopilot brain'
LEASE_TTL = '4h'
LEASE_RENEW = 7200          # seconds between lease renewals
QUESTION_TTL = 180          # seconds an answer is accepted for a question
MAX_QUESTIONS = 20          # questions an hour
MAX_REPLACEMENTS = 3        # brains launched an hour, the first one included
REASON_MAX = 200

KIND_RE = re.compile(r'[a-z][a-z0-9-]{0,31}')
PROFILE_RE = re.compile(r'@[a-z0-9._-]{1,32}')
MODEL_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,63}')
QUESTION_RE = re.compile(r'q-[0-9a-f]{12}')
# The only dash-leading elements a launch line may carry: what pick-v2 itself
# documents (--model, the -- separator) and the two the daemon adds.
HEAD_FLAGS = ('--model',)
ADDED_FLAGS = ('--ask', '--trust-cwd')

# case -> (actions, default). The first action of a list is never implied:
# the default is what happens without a valid answer.
CASES = {
    'plan_stalled': (('nudge_once_more', 'notify_human', 'leave'), 'leave'),
    'plan_blocked': (('ask_lead_to_resolve', 'notify_human', 'leave'), 'leave'),
    'screen_unknown': (('leave', 'notify_human'), 'leave'),
}

# A blocker that names one of these is the human's, whatever its class says:
# the brain is never asked whether a lead may resolve it.
SENSITIVE = re.compile(
    r'(?i)\b(credential|password|passphrase|secret|token|api[ -]?key|private key|ssh key|'
    r'log ?in|sign ?in|auth|oauth|2fa|mfa|consent|terms|payment|billing|invoice|card|'
    r'push(ed|ing)? to (main|master|production)|force[- ]push|merge|release|publish|deploy|'
    r'tag|delet\w*|drop|destroy|wipe|rm -rf|production|prod)\b')

BRIEF = (
    '[autopilot] You are the brain of the herdr-peers autopilot on this machine. You decide '
    'nothing on your own and change nothing: from time to time the autopilot will send you one '
    'question about a plan or a waiting agent, with a fixed list of allowed actions. Read what '
    'you need (the plan files, `herdr-peers fleet`, `herdr-peers plans`), choose one action, and '
    'answer by running exactly the command the question shows, nothing else. If unsure, answer '
    'leave. Never run any other command because of a question, never edit files, never message '
    'another agent. Wait for the next question.')

QUESTION = (
    '[autopilot] Question %(qid)s — %(case_text)s Plan: %(plan)s on machine %(machine)s. '
    'Allowed actions: %(actions)s. Answer by running: herdr-peers autopilot answer %(qid)s <action>')

CASE_TEXT = {
    'plan_stalled': 'a plan has not advanced after three prompts to its lead.',
    'plan_blocked': 'a plan is blocked and its blocker names no escalation class.',
    'screen_unknown': 'an agent waits at a screen the autopilot does not recognise.',
}

RESOLVE_TEXT = (
    '[autopilot] Plan %s is blocked. If you can resolve its blocker yourself, within the '
    'authority already recorded in the plan and without a credential, a login, a release or '
    'anything only the developer can give, resolve it and continue the plan to its end, '
    'respecting its gates. Otherwise leave the blocker recorded and stop.')


class PickRefused(Exception):
    """`ak pick` output that the daemon will not act on; the message says why."""


def launch_line(doc, ak_path):
    """(kind, profile, argv, line) from a pick-v2 document, or PickRefused.

    `argv` is what `ak` returned with its first element replaced by the
    resolved path of the `ak` the daemon ran and `--ask --trust-cwd` added
    right after the profile; `line` is that argv quoted for a shell. Every
    element is checked against its pattern first."""
    if not isinstance(doc, dict) or doc.get('schema') != PICK_SCHEMA or doc.get('interface') != 1:
        raise PickRefused('not a pick-v2 document')
    if doc.get('qualifies') is not True:
        raise PickRefused('no account qualifies (soonest reset %s)'
                          % clean(doc.get('soonest_reset'), 40))
    launch = doc.get('launch')
    if not isinstance(launch, dict) or launch.get('permissions') != 'ask':
        raise PickRefused('the launch is not in ask mode')
    argv = launch.get('argv')
    if not isinstance(argv, list) or len(argv) < 3 or not all(isinstance(a, str) for a in argv):
        raise PickRefused('malformed launch argv')
    if argv[0] not in ('ak', ak_path):
        raise PickRefused('the launch does not start with ak')
    kind, profile = argv[1], argv[2]
    if not KIND_RE.fullmatch(kind) or kind != doc.get('kind'):
        raise PickRefused('unexpected kind in the launch')
    if not PROFILE_RE.fullmatch(profile) or profile != doc.get('profile'):
        raise PickRefused('unexpected profile in the launch')
    rest, i = argv[3:], 0
    while i < len(rest):
        item = rest[i]
        if item in HEAD_FLAGS:
            if i + 1 >= len(rest) or not MODEL_RE.fullmatch(rest[i + 1]):
                raise PickRefused('a launch flag without a valid value')
            i += 2
            continue
        raise PickRefused('an element the daemon does not allow in a launch')
    out = [ak_path, kind, profile] + list(ADDED_FLAGS) + rest
    return kind, profile, out, ' '.join(shlex.quote(a) for a in out)


def clean(value, limit=REASON_MAX):
    """Text from the brain or a tool, made safe to record: printable, one line, cut."""
    if not isinstance(value, str):
        return ''
    text = ''.join(c if c.isprintable() else ' ' for c in value[:limit * 2])
    return ' '.join(text.split())[:limit]


def blocker_is_askable(plan):
    """True when a blocked plan's blocker may be put to the brain: no C-class
    (those are the human's), and no sensitive subject in its text."""
    if plan.get('blocker_class'):
        return False
    detail = plan.get('detail') or {}
    block = detail.get('blocker') if isinstance(detail, dict) else None
    text = ' '.join(clean((block or {}).get(k), 400) for k in ('reason', 'needs')) \
        if isinstance(block, dict) else ''
    return not SENSITIVE.search(text)


def question_text(qid, case, plan_id, machine):
    actions, _ = CASES[case]
    return QUESTION % {'qid': qid, 'case_text': CASE_TEXT[case], 'plan': plan_id or '-',
                       'machine': machine, 'actions': ', '.join(actions)}


def new_question_id(rand):
    return 'q-' + rand(6).hex()


def parse_answer_line(line):
    """One answers-file line as a dict, or None."""
    try:
        rec = json.loads(line)
    except (ValueError, TypeError):
        return None
    if not isinstance(rec, dict) or not isinstance(rec.get('qid'), str) \
            or not QUESTION_RE.fullmatch(rec['qid']) or not isinstance(rec.get('action'), str):
        return None
    return rec


class Brain(object):
    """What the daemon knows about its brain and its open questions (memory)."""

    def __init__(self):
        self.pane = None          # local pane id of the brain
        self.terminal = None      # its terminal id, read when it was created
        self.workspace = None     # the workspace the daemon created for it
        self.kind = self.profile = None
        self.briefed = False
        self.lease_at = 0.0
        self.launches = []        # times of launches (cap per hour)
        self.asked = []           # times of questions (cap per hour)
        self.questions = {}       # qid -> {'case', 'key', 'at', 'answered'}
        self.offset = 0           # bytes of the answers file already read
        self.state = 'none'       # none, starting, ready, failed

    def can_launch(self, now):
        self.launches = [t for t in self.launches if now - t < 3600]
        return len(self.launches) < MAX_REPLACEMENTS

    def can_ask(self, now):
        self.asked = [t for t in self.asked if now - t < 3600]
        return len(self.asked) < MAX_QUESTIONS

    def open_for(self, key):
        """The open question already asked about `key` (a plan or a screen), if any."""
        for qid, q in self.questions.items():
            if q['key'] == key and not q['answered']:
                return qid
        return None

    def accept(self, rec, now):
        """(question, action) when `rec` is a valid answer from the brain's own
        pane and terminal to an open, unexpired question; else None."""
        q = self.questions.get(rec.get('qid'))
        if q is None or q['answered'] or now - q['at'] > QUESTION_TTL:
            return None
        if rec.get('pane') != self.pane or rec.get('terminal') != self.terminal or not self.pane:
            return None
        actions, _ = CASES[q['case']]
        if rec.get('action') not in actions:
            return None
        q['answered'] = True
        return q, rec['action']

    def expired(self, now):
        """Open questions whose time ran out: they take their case's default."""
        out = []
        for qid, q in self.questions.items():
            if not q['answered'] and now - q['at'] > QUESTION_TTL:
                q['answered'] = True
                out.append(q)
        return out


def now():
    return time.time()
