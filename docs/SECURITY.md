# Security — herdr-peers

This document is the threat model of herdr-peers protocol 1 and its helper:
what is protected, from whom, how, and what risk remains. The normative rules
are in [`skills/herdr-peers/protocol.md`](../skills/herdr-peers/protocol.md);
every mitigation below is exercised by `bash tests/run.sh security` (and the
`protocol`, `helper` and `templates` scopes).

## Reporting a vulnerability

Please report suspected vulnerabilities privately through GitHub's
*Security → Report a vulnerability* on this repository rather than in a public
issue. Include the herdr-peers and Herdr versions and a minimal reproduction.

## Threat model

### What the system is

An agent in a Herdr pane runs `herdr-peers ask`, which sends text into
another agent's pane with `herdr agent prompt` (locally, or through
`herdr --machine <id>` to a saved SSH machine). The other agent may answer
once with `herdr-peers reply`. Both sides keep an append-only local record.

### Assets

1. **The receiving agent's authority** — what it may do in its repository and
   on its machine (files, commands, credentials it can reach).
2. **The caller's decisions** — a reply feeds the caller's next actions.
3. **Secrets** in either environment (`*_API_KEY`, `*_TOKEN`, keys, passwords).
4. **The human's terminal and panes** — focus, layout, other agents' work.
5. **The record** — the delegation log and stored replies.

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
| T2 | **Reply loops** — two agents answering each other forever. | Reply stamps carry `reply-to=` + `depth=1` and **no** `from=` (nothing to answer); `check` classifies every reply as never-answer; `reply` refuses an id this pane originated and a second reply to the same id. | `protocol`, `helper` |
| T3 | **Delegation chains** — a delegate delegating further. | Depth limit 1: `ask` refuses when `HERDR_PEERS_DEPTH>=1` (set by the launcher) or while this pane holds an unanswered ask recorded by `check`. | `helper` |
| T4 | **Fan-out storms** | At most 4 open asks per caller; raising it needs `--fanout N --reason` (recorded); the environment can lower, never raise the cap; the check-and-append runs under a file lock (8 parallel asks open exactly 4). | `helper`, `security` |
| T5 | **Stamp smuggling** — a body quoting a stamp, a mid-line stamp, a second stamp appended. | Exactly one `[herdr-peers]` marker, at the start of a line; anything else is invalid and never answered. `ask`/`reply` refuse bodies containing the marker. | `protocol`, `security` |
| T6 | **Spoofed ask** claiming `from=<victim>` so the delegate's reply lands in the victim's pane. | The victim's `check` sees a reply to an id it never sent: *unsolicited*, never answered, never recorded. The reply itself is written by the delegate's agent, not the attacker. | `security` |
| T7 | **Forged reply** to a real outstanding ask. | Ids are ULIDs with 80 random bits, known only to the asked pane; a guessed id is *unsolicited*. A second, different reply to a recorded id is flagged *conflict*. | `security`, `helper` |
| T8 | **Reply redirection** — text in an ask asks the delegate to "reply to" another pane. | `reply` sends only to the `from` of an ask that `check` recorded for this pane (or that `--message` verifies); any other target is refused. | `helper` |
| T9 | **Reply misrouting across machines** — `local` resolved on the wrong server. | A caller never sends `from=local` to another machine; it names an address the peer can reach (`HERDR_PEERS_SELF`, `--from`, or a probe matching its own `terminal_id`) or refuses with *no reply route*. | `helper` |
| T10 | **Terminal manipulation** — escape sequences, C1 controls, bidi overrides or zero-width characters that hide or fake text. | Outgoing messages with such characters are refused; received ones are never answered; every string printed from Herdr or a peer (titles, kinds, labels, errors) is neutralized. | `security` |
| T11 | **Option/argument injection into `herdr`** | Every call is an argv list (no shell); addresses and ids are validated with full-string matches (no trailing-newline tricks); machine ids never start with `-`; a message starting with `-` is shifted by one space. | `security` |
| T12 | **Oversized messages** | 16384-byte limit (`HERDR_PEERS_MAX_BYTES` lowers it) on send and receive. | `security` |
| T13 | **Secret leakage** in messages, logs or replies. | Outgoing text containing the value of any variable named `*_API_KEY`, `*_TOKEN`, `*_SECRET`, `*_SECRET_KEY`, `*_ACCESS_KEY` or `*_PASSWORD` (case-insensitive, ≥ 8 chars), a private-key block or a known token shape is refused — naming the variable, never the value. A received message carrying one is never answered and never stored. Records hold `sha256:` digests of prompts, never their text. | `security`, `templates` |
| T14 | **Scope bypass** — labels, case variants, `local` vs ids. | Scope compares exact machine ids (and workspaces); anything not listed is refused (fail-closed). | `security` |
| T15 | **Record tampering and filesystem tricks** | Log and reply copies are `0600` in a `0700` directory with a `.gitignore`; symlinked log or reply files are refused (`O_NOFOLLOW`) and nothing is sent when the record cannot be written; reply paths are rebuilt from the validated id, never read from the log. | `security` |
| T16 | **Malformed or hostile JSON from Herdr** | Every field is type-checked; malformed machines/agents are dropped; nothing crashes into a traceback. | `security` |
| T17 | **Panes and layout** — closing or moving others' work. | Discipline: close only panes you created; layout changes are recorded intent; launched peers get default permissions, never a bypass flag. | `skill` (marketplace rules) |

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
- **Pane capture in `wait`.** `wait` records the text before the exact reply
  stamp as captured from the caller's own pane (best effort, bounded by
  `--lines`). The received message itself, passed to `check`, replaces the
  capture with the exact copy.
- **Secret detection is a filter, not a guarantee.** Values of other names,
  short values and unknown token formats are not recognized.
- **The local record is local.** Anyone with write access to the repository
  can edit `.herdr-peers/`; it is an audit aid, not tamper-proof evidence.

## Supply chain

Runtime code is `bash` and the `python3` standard library only — no packages
are installed. The official Herdr skill is referenced pinned
(`herdrdev/herdr@v0.9.3`) or via the installed binary's `herdr --skill`. CI
pins GitHub Actions by commit SHA and verifies the shellcheck download
against its published SHA-256. Releases carry a `SHA256SUMS` file over the
shipped files.
