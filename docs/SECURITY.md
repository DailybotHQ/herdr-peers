# Security — herdr-peers threat model

This document is the threat model of herdr-peers protocol 1 and its helper:
what is protected, from whom, how, and what risk remains. The normative rules
are in [`skills/herdr-peers/protocol.md`](../skills/herdr-peers/protocol.md);
every mitigation below is exercised by `bash tests/run.sh security` (and the
`protocol`, `helper` and `templates` scopes).

## Reporting a vulnerability

Report suspected vulnerabilities privately, never in a public issue — the
channels and response targets are in the [security policy](../SECURITY.md).

## Threat model

### What the system is

An agent in a Herdr pane runs `herdr-peers ask`, which sends text into
another agent's pane with `herdr agent prompt` (locally, or through
`herdr --machine <id>` to a saved SSH machine). The other agent may answer
once with `herdr-peers reply`. `herdr-peers notify` sends a one-way notice
that is never answered. `herdr-peers lead …` keeps a per-plan lead record
(who leads, at which epoch, who succeeds it) and broadcasts changes as lead
notices. Both sides keep an append-only local record.

### Assets

1. **The receiving agent's authority** — what it may do in its repository and
   on its machine (files, commands, credentials it can reach).
2. **The caller's decisions** — a reply feeds the caller's next actions.
3. **Secrets** in either environment (`*_API_KEY`, `*_TOKEN`, keys, passwords).
4. **The human's terminal and panes** — focus, layout, other agents' work.
5. **The record** — the delegation log, stored replies and lead records.
6. **Leadership** — which agent acts as a plan's lead (merges, tags and
   releases are performed only by the current-epoch lead).

### Trust boundaries and adversaries

- **Herdr has no sender authentication.** Any process that can run `herdr`
  against a server — the same user on that machine, or any machine that has
  it saved as an SSH machine — can type into any pane on it. herdr-peers
  cannot change that; it limits what an *honest* agent does with what it
  receives.
- **A hostile or confused peer** — an agent that sends crafted asks or
  replies, quotes stamps, or tries to make the receiver act.
- **Hostile text from Herdr itself** — pane titles, agent kinds, machine
  labels and error output are attacker-influenced strings (a remote pane can
  set its own title).
- **Out of scope:** a compromised Herdr binary or server, a compromised SSH
  configuration, an attacker with write access to the user's repository or
  home directory (they can already change the helper itself).

### Threats and mitigations

| # | Threat | Mitigation | Tested in |
|---|---|---|---|
| T1 | **Prompt injection** — an ask tells the receiver to run commands, leak data or escalate. | Received text is data, not instructions (protocol §5): an ask is a request within the receiver's existing authority; destructive, public or credential-touching actions go to the receiver's human. The grant authorizes one reply, nothing else. | docs/skill (`skill`), protocol §5 |
| T2 | **Reply loops** — two agents answering each other forever. | Reply stamps carry `reply-to=` + the asked peer's `from=` address + `depth=1` but no reply grant; `check` classifies every reply as never-answer; `reply` refuses an id this pane originated and a second reply to the same id. | `protocol`, `helper` |
| T3 | **Delegation chains** — a delegate delegating further. | Depth limit 1: `ask` refuses when `HERDR_PEERS_DEPTH>=1` (set by the launcher) or while this pane holds an unanswered ask recorded by `check`. | `helper` |
| T4 | **Fan-out storms** | At most 4 open asks per caller; raising it needs `--fanout N --reason` (recorded); the environment can lower, never raise the cap; the check-and-append runs under a file lock (8 parallel asks open exactly 4). | `helper`, `security` |
| T5 | **Stamp smuggling** — a body quoting a stamp, a mid-line stamp, a second stamp appended. | Exactly one `[herdr-peers]` marker, at the start of a line; anything else is invalid and never answered. `ask`/`reply` refuse bodies containing the marker. | `protocol`, `security` |
| T6 | **Spoofed ask** claiming `from=<victim>` so the delegate's reply lands in the victim's pane. | The victim's `check` sees a reply to an id it never sent: *unsolicited*, never answered, never recorded. The reply itself is written by the delegate's agent, not the attacker. | `security` |
| T7 | **Forged reply** to a real outstanding ask. | Ids are ULIDs with 80 random bits, known only to the asked pane; a guessed id is *unsolicited*. A second, different reply to a recorded id is flagged *conflict*. | `security`, `helper` |
| T8 | **Reply redirection** — text in an ask asks the delegate to "reply to" another pane. | `reply` sends only to the `from` of an ask that `check` recorded for this pane (or that `--message` verifies); any other target is refused. | `helper` |
| T9 | **Reply misrouting across machines** — `local` resolved on the wrong server. | A caller never sends `from=local` to another machine; it names an address the peer can reach (`HERDR_PEERS_SELF`, `--from`, or a probe matching its own `terminal_id`) or refuses with *no reply route*. | `helper` |
| T10 | **Terminal manipulation** — escape sequences, C1 controls, bidi overrides or zero-width characters that hide or fake text. | Outgoing messages with such characters are refused; received ones are never answered; every string printed from Herdr or a peer (titles, kinds, labels, errors) is neutralized. | `security` |
| T11 | **Option/argument injection into `herdr`** | Every call is an argv list (no shell); addresses and ids are validated with full-string matches (no trailing-newline tricks); machine ids never start with `-`; a message starting with `-` is shifted by one space. | `security` |
| T12 | **Oversized messages** | 16384-byte limit on send and receive; `HERDR_PEERS_MAX_BYTES` can lower it, never raise it. | `security` |
| T13 | **Secret leakage** in messages, logs or replies. | Outgoing text containing the value of any variable named `*_API_KEY`, `*_TOKEN`, `*_SECRET`, `*_SECRET_KEY`, `*_ACCESS_KEY` or `*_PASSWORD` (case-insensitive, ≥ 8 chars), a private-key block or a known token shape is refused — naming the variable, never the value. A received message carrying one is never answered and never stored. Records hold `sha256:` digests of prompts, never their text. | `security`, `templates` |
| T14 | **Scope bypass** — labels, case variants, `local` vs ids. | Scope compares exact machine ids (and workspaces); anything not listed is refused (fail-closed). | `security` |
| T15 | **Record tampering and filesystem tricks** | Files the helper writes (machine-scoped log, reply copies, `self.json`) are created `0600` without following symlinks (`O_NOFOLLOW`), directories it creates are `0700`; default state is outside the checkout; symlinked log or reply files are refused and nothing is sent when the record cannot be written; reply paths are rebuilt from the validated id, never read from the log. | `security` |
| T16 | **Malformed or hostile JSON from Herdr** | Every field is type-checked; malformed machines/agents are dropped; nothing crashes into a traceback. | `security` |
| T17 | **Panes and layout** — closing or moving others' work. | Discipline: close only panes you created; layout changes are recorded intent; launched peers get default permissions, never a bypass flag. | `skill` (marketplace rules) |
| T18 | **Stale sender address** — an agent inherits a `HERDR_PANE_ID` that names a gone pane or another session's pane, so its `from=` routes replies nowhere or into someone else's pane. | `ask` and `reply` verify their own pane first: it must exist on the local server and, when Herdr's `pane process-info` pids are visible in this process table, one of them must be an ancestor of the helper; otherwise exit 6 and nothing is sent or recorded. Pids from another PID namespace (a container) cannot be compared: the pane's existence is the check there. An agent that runs its tools from a background server (Codex: no terminal anywhere in the caller's ancestry) is never trusted on the inherited id, which names the server's first pane; it declares its pane with `--pane`, accepted only when that pane runs the same agent program and refused when it runs another. A terminal-attached caller always needs the ancestry match, with or without `--pane`. | `orchestra` |
| T20 | **Forged or replayed lead notice** — a peer claims leadership, jumps the epoch, takes over out of turn, or replays an old notice. | A receiver stores a record only through the fencing rules (protocol §12): first claim only from the briefer (`HERDR_PEERS_BRIEFER` or a recorded asker), handover only from the stored lead at epoch+1, takeover only by a listed successor at epoch+1 when every earlier successor is gone (the receiver checks), ties to the earlier position; a stale epoch, a duplicate notice id (rule 12) and anything else are rejected and recorded. Received records are validated strictly (exact keys, address and plan patterns, epoch range, list sizes) after a size (8 KiB) and nesting (2 levels) pre-check, so a hostile line cannot crash the parser; the helper also validates every record before writing it. Reachability is read before the state lock is taken; the decision is re-made under the lock from the reloaded record. A former lead on the same server (whose shared record the successor already rewrote) is still told to step down. `notify` refuses a hand-written `swarm-lead:` line. A former lead that adopts a newer epoch steps down and its lead verbs are refused. | `lead`, `helper` |
| T21 | **Notice abuse** — notices skip the fan-out cap and may be sent while holding an ask. | A notice grants nothing and is never answered, so it cannot start a loop or a chain; it has the ask's hygiene (size, control characters, marker, secrets, scope, self, blocked peer). Receivers record each id once (rule 12). | `helper`, `security`, `protocol` |
| T22 | **Lead-record file tricks** | Lead records live in the machine-scoped state (`leads/`, directory `0700`, files `0600`), are written atomically (temp file + rename) and never read or written through a symlink; a corrupt record stops every lead verb instead of being guessed at. Records hold plan ids and addresses only. | `lead` |
| T19 | **Screen reading** — `status`/`lanes` read a waiting lane's visible screen, which may show secrets or hostile text, and could be tempted to answer it. | Read-only: they print a class and the name of the matched pattern, never screen text, and never send keys (`argv.log` proves no `send-keys`). Only folder trust may be keyed through — by the lead, on a pane it launched itself, under the user's standing authorization (the only screen with keys in `UNBLOCK_KEYS`). Claude's bypass-permissions acknowledgement is never keyed by an agent: the developer accepts it once per profile. A usage-limit screen (`usage_limit`: the CLI's own banner anchored at the start of a line, also read from the last 15 lines of an idle lane) is handed off — the lead relaunches the lane's plan on an account with capacity — and never keyed. Because a peer can deliver text that looks like a banner into an idle pane, an idle-pane match never counts as "gone" for a receiver's fencing and needs a recorded `--reason` for a takeover. Login, permission and unknown screens escalate. | `orchestra` |
| T23 | **Debate inputs** — ballots and filings are written by other agents and may be hostile (huge, malformed, symlinked, instructions in prose, shell text in a verdict). | `debate tally` reads one JSON file of at most 4 MiB, never through a symlink, validates every id, ranking and verdict (uppercase word only) and refuses duplicates; `filings` accepts plain names only (no paths). Nothing in a filing or ballot is executed, evaluated or forwarded; the lead never votes (`lead` is always excluded). | `debate` |
| T24 | **Un-blinding** — the anonymization key or identities leak to the panel. | `debate anon` refuses a key inside the filings or the output directory, never overwrites a key or a non-empty output directory, writes the key `0600` with `O_EXCL`/`O_NOFOLLOW`, and redacts pane ids, Herdr addresses, filename stems, model and vendor names and each `--redact` word. | `debate` |
| T25 | **Panel provisioning** — a helper that launches agents or spends accounts on its own. | `debate panel` is read-only: it reads Herdr's agent list, this server's lead records and `ak pick` (once per call), and prints commands — lease, split, launch, release — that the lead runs only with the human's go-ahead (the fakes prove no prompt, key, split, run or lease is issued). Panes that lead or serve another plan's lead record are never offered; proposed launches carry no permission flag (agentkit's own posture, which the human controls, applies). | `debate` |

## Residual risk (accepted)

- **No sender authentication (inherent to Herdr).** A process that can drive
  Herdr can type anything into a pane, with or without a stamp. A message
  with no stamp is ordinary input to the receiving agent — exactly as if that
  process had typed it. herdr-peers only governs messages that use the
  protocol.
- **Relay through a delegate.** Because `from=` is a claim, a peer that can
  prompt a delegate can make it send **one reply, written by the delegate's
  own agent**, to any address inside the delegate's scope — including a
  machine the asker could not reach itself. The receiving pane sees an
  unsolicited reply and never answers it. Mitigation: set
  `HERDR_PEERS_SCOPE` on hosts that can reach machines they should not serve.
  The default stays unrestricted because the protocol's purpose is
  cross-machine asks and the parent contract defines scope as an optional
  allow-list.
- **Cooperative depth guard.** The depth limit relies on the delegate's
  environment mark or its `check` record; an agent that deliberately unsets
  the mark and skips `check` can still ask. The protocol forbids it; the
  helper cannot stop a process that ignores the helper.
- **Pane capture in `wait`.** `wait` accepts only a newly matched reply stamp
  whose `from=` equals the asked peer; a caller-pane capture from another
  source is ignored. The received message itself, passed to `check`, replaces
  any capture with the exact copy.
- **Secret detection is a filter, not a guarantee.** Values of other names,
  short values and unknown token formats are not recognized.
- **Fencing is not authentication.** The lead fencing rules decide which
  record a cooperating peer follows; they rest on the same `from=` claim as
  every message. A process that can type into a pane can impersonate a lead
  it can reach, within the receiver's scope — set `HERDR_PEERS_SCOPE` and
  `HERDR_PEERS_BRIEFER` on lanes that should follow only one lead. Panes on
  one Herdr server share one state directory, so a local process can rewrite
  a lead record directly; a lead record grants no authority either way —
  lanes act only within their plan's authorization.
- **Anonymization is redaction, not anonymity.** `debate anon` removes
  names it can recognize; a filing's style, a self-description in other
  words, or a quoted fact only one pane knew can still identify its author.
  Blind rounds rely on the brief's rules as much as on the tool.
- **The local record is local.** Anyone with write access to the XDG state
  directory (or an explicit log path) can edit it; it is an audit aid, not
  tamper-proof evidence.

## Supply chain

Runtime code is `bash` and the `python3` standard library only — no packages
are installed. The official Herdr skill is referenced pinned
(`herdrdev/herdr@v0.9.3`) or via the installed binary's `herdr --skill`. CI
pins GitHub Actions by commit SHA and verifies the shellcheck download
against its published SHA-256. Every release carries a `SHA256SUMS`
asset over the shipped files (`skills/herdr-peers/**`, `bin/herdr-peers`,
`LICENSE`, and from v0.2.0 the `docs/schema/` contracts), generated at release
time from the tagged tree with
`git ls-files skills bin LICENSE docs/schema | LC_ALL=C sort | xargs shasum -a 256`;
verify a checkout with `shasum -a 256 -c SHA256SUMS`.
