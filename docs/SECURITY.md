# Security — herdr-peers threat model

This document is the threat model of herdr-peers (protocols 1 and 2) and its
helper: what is protected, from whom, how, and what risk remains. The
normative rules are in [`skills/herdr-peers/protocol.md`](../skills/herdr-peers/protocol.md);
every mitigation below is exercised by the test suite (the scope named in
each row; `bash tests/run.sh <scope>`).

## Residual risks you accept

The short list; each is explained under
[Residual risk (accepted)](#residual-risk-accepted) and in its threat row.

1. **No sender authentication.** Herdr has none: `from=` is a claim, and a
   process that can drive Herdr can type anything into a pane. Fencing and
   scope govern cooperating peers; they are not authentication (T6, T20, T43).
2. **Autopilot approves what agents ask** — including a command you would
   have refused. There is no deny-list (T30).
3. **The brain is a prompt-injection target.** Its answers are bounded to a
   closed list of harmless actions and its only approved command is its own
   answer, but an injected brain can still choose any allowed action; a
   process of the same user that reads its key file can forge an allowed
   answer; and a profile whose own settings pre-allow tools runs them
   without the dialog the ask-mode launch relies on (T41, T42).
4. **A partition can briefly give a plan two leads** after an appointment.
   Nothing is written remotely to prevent it; `lead verify` catches what it
   can reach (T44).
5. **Screens change.** A CLI upgrade can stop a screen from being recognised
   (left alone) or recognised by the generic rule only (T29).
6. **Secret detection and redaction are filters**, not guarantees (T13).
7. **The local record is local**: anyone who can write the state directory
   can edit it; it is an audit aid, not evidence (T15).

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

`herdr-peers autopilot`, started by a human, is a separate actor: a loop that
reads agents' states and visible screens through Herdr and, on a waiting
screen, sends key presses (`herdr pane send-keys`) or one fixed prompt
(`herdr agent prompt`). It is the only part of herdr-peers that sends keys.
With `--loop` it also reads lead records and plan state files, asks every
saved machine for the same over SSH, prompts the lead of a plan that is not
finished, keeps a map file on each machine, and may run a notify command the
human named (T34–T38).

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
| T19 | **Screen reading** — `status`/`lanes` read a waiting lane's visible screen, which may show secrets or hostile text, and could be tempted to answer it. | Read-only: they print a class and the name of the matched pattern, never screen text, and never send keys (`argv.log` proves no `send-keys`). Only folder trust may be keyed through — by the lead, on a pane it launched itself, under the user's standing authorization (the only screen with keys in `UNBLOCK_KEYS`). Claude's bypass-permissions acknowledgement is never keyed by an agent: the developer accepts it once per profile. A usage-limit screen (`usage_limit`: the CLI's own banner anchored at the start of a line, also read from the last 15 lines of an idle lane) is handed off — the lead relaunches the lane's plan on an account with capacity — and never keyed. Because a peer can deliver text that looks like a banner into an idle pane, an idle-pane match never counts as "gone" for a receiver's fencing and needs a recorded `--reason` for a takeover. Login, permission and unknown screens escalate. | `orchestra` |
| T20 | **Forged or replayed lead notice** — a peer claims leadership, jumps the epoch, takes over out of turn, or replays an old notice. | A receiver stores a record only through the fencing rules (protocol §12): first claim only from the briefer (`HERDR_PEERS_BRIEFER` or a recorded asker), handover only from the stored lead at epoch+1, takeover only by a listed successor at epoch+1 when every earlier successor is gone (the receiver checks), ties to the earlier position; a stale epoch, a duplicate notice id (rule 12) and anything else are rejected and recorded. Received records are validated strictly (exact keys, address and plan patterns, epoch range, list sizes) after a size (8 KiB) and nesting (2 levels) pre-check, so a hostile line cannot crash the parser; the helper also validates every record before writing it. Reachability is read before the state lock is taken; the decision is re-made under the lock from the reloaded record. A former lead on the same server (whose shared record the successor already rewrote) is still told to step down. `notify` refuses a hand-written `swarm-lead:` line. A former lead that adopts a newer epoch steps down and its lead verbs are refused. | `lead`, `helper` |
| T21 | **Notice abuse** — notices skip the fan-out cap and may be sent while holding an ask. | A notice grants nothing and is never answered, so it cannot start a loop or a chain; it has the ask's hygiene (size, control characters, marker, secrets, scope, self, blocked peer). Receivers record each id once (rule 12). | `helper`, `security`, `protocol` |
| T22 | **Lead-record file tricks** | Lead records live in the machine-scoped state (`leads/`, directory `0700`, files `0600`), are written atomically (temp file + rename) and never read or written through a symlink; a corrupt record stops every lead verb instead of being guessed at. Records hold plan ids and addresses only. | `lead` |
| T23 | **Debate inputs** — ballots, claims ledgers and filings are written by other agents and may be hostile (huge, malformed, symlinked, instructions in prose, shell text in a verdict). | `debate tally` and `debate claims` read JSON files of at most 4 MiB each, never through a symlink, validate every id, ranking (strings only: a hostile shape exits 2, never a traceback), verdict (uppercase word only), stance, evidence level and confidence, cap claims (500 per lane), text (500 characters) and sources (20 of 300 characters), and refuse duplicates — a voter or lane is one identity whatever its case or a `local:` prefix, and `lead` is excluded in any case; `filings` accepts plain names only (no paths). Nothing in a filing or ballot is executed, evaluated or forwarded; the lead never votes (`lead` is always excluded). | `debate` |
| T24 | **Un-blinding** — the anonymization key, the order's secret or identities leak to the panel. | `debate anon` derives the filing order from a random 128-bit secret (or `--seed`) kept only in the key file and never printed (without that secret the public filing names do not rebuild the map; anyone holding the key file or a guessable `--seed` can, so keep both away from the panel); refuses a key inside the filings or the output directory, never overwrites a key or a non-empty output directory, writes the key `0600` with `O_EXCL`/`O_NOFOLLOW`, and redacts pane ids, Herdr addresses, profile handles, filename stems, model and vendor names and each `--redact` word. `debate claims --anonymous` renames lanes and angles (`Lane_A`, `Angle_A`), drops vendors and redacts the same identities from every claim's text and sources. | `debate` |
| T25 | **Panel provisioning** — a helper that launches agents or spends accounts on its own. | `debate panel` is read-only: it reads Herdr's agent list, this server's lead records and `ak pick` (once per call), and prints commands — lease, split, launch, release — that the lead runs only with the human's go-ahead (the fakes prove no prompt, key, split, run or lease is issued). Panes that lead or serve another plan's lead record are never offered; proposed launches carry no permission flag (agentkit's own posture, which the human controls, applies). | `debate` |
| T26 | **Secrets in debate files** — a pane dumps a token into its filing, which `anon` would copy to every peer. | `debate anon` runs the helper's secret detector (`secret_finding`: values of `*_API_KEY`/`*_TOKEN`-style variables and known token shapes) over every filing first and refuses the run, naming the kind, never the value, before anything is written. | `debate` |
| T27 | **Delivery to a blocked peer** — a reply retried into a pane that shows a question, or retried forever. | Only the delivery of the one recorded reply is retried, with backoff, for at most `--wait-blocked` / `HERDR_PEERS_BLOCKED_WAIT` seconds (default 600, cap 3600); each attempt takes the log lock and re-checks exactly-once, so concurrent replies still send one; the text is never changed and a still-blocked peer is recorded `unroutable` as before. Herdr refuses input to a blocked agent (`agent_blocked`), so no attempt types into the question. | `helper` |
| T28 | **A message starts or steers autopilot** — an ask, reply or notice tells an agent to run `herdr-peers autopilot`, to widen its scope or to add `--catch-up`. | Autopilot is a command a human runs; nothing in `check`, `reply` or the lead path invokes it, and protocol §13 and the skill's trust boundary forbid an agent from starting it on a message's say-so. The text autopilot itself sends is not a protocol message (`check` decides it none). | `autopilot` |
| T29 | **A screen shaped like a menu** — an agent (or text it displays) prints rows and a cursor so that autopilot presses keys. | Keys go only to a block recognised at the bottom of the screen; a block counts only at the bottom of the screen with no input line under it; outside a `blocked` state it must belong to a named class anchored on its own text (folder trust, plan approval, update prompt, review) within a few lines of it, say that Enter selects (or carry plan approval's footer), and not sit inside the input box — because an input line with wrapped or numbered text looks the same as a menu. The only keys ever sent are `enter`, `tab`, `up`, `down` and `shift+left`; no text from a screen is executed, sent or logged. What Enter does is decided by the agent's own terminal UI. | `autopilot` |
| T30 | **Approving a harmful action** — an agent asks for a destructive command and autopilot accepts it. | By design autopilot accepts what an agent asks: this is the residual risk the human takes on by starting it (below). It narrows the blast radius only at the edges: it never chooses a row that widens the agent's standing permissions (`always allow`, `don't ask again`, `Run Everything`, auto mode, persisted settings, a parent folder), never a login, never Claude's bypass acknowledgement, and `--scope` / `--exclude` keep it off chosen machines and panes. A menu that offers only refusals or widening rows is denied (its refusal row, never an exit row, else Esc) instead of left blocked — a denial never grants anything — and the agent is told once to continue another way. | `autopilot` |
| T31 | **Submitting a human's draft** — a prompt or an Enter lands in a pane where the human had typed something. | A pane is prompted (nudge or usage-limit retry) only when its input line is empty or shows the CLI's own placeholder; keys go only to a live dialog as defined in T29, so text printed above an input line, or typed into it as a numbered list, is never keyed. Found in the pre-release review and covered by fixtures. | `autopilot` |
| T32 | **A runaway loop** — an agent that asks again after every prompt, or a screen that never moves, keeps autopilot acting forever. | At most 3 prompts per pane per hour; a pane is prompted only after a turn of its own finished; a screen unchanged after two key rounds is left and recorded, counted across passes and blind to ticking digits; at most 8 key rounds per pane per pass; a usage-limit pane is retried once per 30 minutes, at most 48 times, and only on the CLI's own banner (a `429` in command output is not a limit). | `autopilot` |
| T33 | **Autopilot as a load on the machine** | One process, asleep between passes (default 60 s, minimum 15); one `agent list` per machine per pass; a screen is read only on a state change; an unreachable machine backs off up to 8 passes; a second instance on the same server is refused by a lock. | `autopilot` |
| T34 | **The plan loop's remote command** — `autopilot --loop` runs `ssh` to every saved machine; a saved target or anything a machine reported could become an option or a command. | The argv is fixed (`ssh -o BatchMode=yes -o ConnectTimeout=8 -- <target> python3 -`); the target comes only from `herdr machine list`, must match a plain host pattern (never a leading `-`) and follows `--`; the program sent on standard input is the shipped report module with two base64 values substituted, never text from a screen, a plan or a report. No shell is built locally. `BatchMode` means a machine that would ask for a password is skipped; no SSH configuration, host trust or key is changed. |
| T35 | **A hostile answer from a machine** — a compromised or confused machine returns a report naming a plan id, an address or a path chosen to steer the daemon. | The answer is read while it streams and cut at 2 MB (the remote command runs in its own process group and is killed whole at the limit or the timeout), and used only after the whole of it validates (`valid_report`: every key present, each against its pattern): plan ids, addresses, paths, classes and digests each against their pattern. Only an address the reporting machine calls `local:` — its own pane — is ever prompted, and only through `herdr agent prompt` on that same machine. The prompts are constants; a report can choose which of its own leads is asked to continue its own plan, nothing more. An invalid or missing answer is "unknown", and an error anywhere in the plan pass is caught: it never stops the daemon or its screen pass: the last good report stays and nobody new is prompted. |
| T36 | **A hostile lead record or plan state** — a file under a repository says a plan is open forever, or a lead record points at someone else's pane. | The loop sends one fixed prompt to the pane a lead record names, on the machine holding that record; it grants nothing and names no command but `lead takeover` to a listed successor, without `--reason`, so the helper's own gone check and fencing decide. A lead counts as gone only when its pane is missing from two listings in a row (agents outside `--scope` are still listed — and never put on the map); a usage limit is never a reason. A pane id reused after a Herdr restart is caught when the pane now works in another repository (`lead_in_repo: false`): it is never told it leads a plan (`plan_lead_moved`). A plan that never advances is stopped after 3 prompts (`plan_stalled`); the per-pane cap of 3 prompts an hour is shared with the nudge; a lead is never prompted over a draft, at a dialog or login, while its lanes work or it awaits a reply, or within the grace period. State files are opened without following symlinks, bounded in size, confined to the repository, and an unknown shape is `unreadable`, never guessed. |
| T37 | **The map written on other machines** — the daemon leaves `fleet.json` on every machine that answers. | It is written only in the herdr-peers state root, `0600`, atomically, never through a symlink, bounded in size, and only when it parses as a `fleet-v1` object. It is data: `herdr-peers fleet` prints it through `safe()` and nothing executes it. The copy left on another machine holds pane ids, states, kinds, repository roots, branches, plan ids, classes, task counts and current tasks — no plan summary, task list, blocker text, session title or working directory (those stay in the daemon's own map); every free-text field is cleaned and token shapes and secret-named variable values are redacted before anything is written; no screen text or prompt text. A machine that should not learn the others' layout is kept out with `--scope`. |
| T38 | **The notify command** — `--notify` makes the daemon run a program. | Only the command line that starts the daemon sets it (no environment variable, no message, no file); it is split once and run without a shell, so metacharacters are arguments; its input is one `plan-event-v1` object built from validated fields; output is discarded; it runs in its own process group, killed whole at its timeout; all notify commands of a pass share one budget (20 s by default), the rest waits for the next pass; its environment is minimal — no tokens or keys unless the human names a variable with `--notify-env`; a failure is recorded once and never stops the pass. `--dry-run` runs nothing. |
| T39 | **The background autopilot** — a detached process nobody watches, its log, its options file. | Only a human starts it (`autopilot start`, T28 unchanged): no option comes from a message, and the daemon takes exactly the options `start` was given, passed on its own command line. It is the same loop under the same lock (one per server, in either mode); it holds no terminal (own session, `/dev/null` input) and makes no call that needs the starting pane after start. `autopilot.out` and `autopilot.json` live in the state directory (`0700`), are `0600`, are never opened through a symlink, and hold what the foreground output already showed: timestamps, addresses, screen classes, keys, options — no screen text, no prompt, no secret. The log rotates at 1 MB (two files at most). `stop` signals only the pid recorded under the held lock. `logs` is read-only and prints every line through `safe()`. | `autopilot` |
| T40 | **The watcher shows text written by agents** — `fleet ui` draws session titles, task titles, a plan's `PROGRESS.md` lines and a live screen, all written by agents. | Everything drawn passes through `clean()` (every character of Unicode categories Cc, Cf, Zl, Zp, Co and Cs becomes a space: controls, bidi and other format characters, soft hyphens, tag characters) and is cut to its cell; a live screen is read as text (`--source recent`, no ANSI) and cleaned the same way. Plan text on the map is cleaned and bounded where it is read (`fleet_report.clean_text`, 14 lines of 200 characters, 64 tasks) and validated when a machine reports it. The map is read without following a symlink, only as a regular file of at most 2 MB, and refused whole unless every container has the fleet-v1 shape: a malformed or hostile copy shows "map unreadable" and the watcher keeps running. The watcher writes nothing and sends nothing to an agent; its only Herdr calls are `pane read` while an agent is open (at most every 2 s) and `agent focus` on the human's key, each with a fixed argv and a pane id checked against the pattern, and only to a machine this machine's own Herdr lists. |
| T41 | **The daemon launches an agent on the human's accounts** — `--brain` runs `ak pick`, takes a lease and types a line into a pane. | Only the human's command line enables it. `ak` is run as an argv list, never through a shell; its answer is checked whole (pick-v2, interface 1, qualifies, `launch.permissions == ask`), the line is `ak`'s own argv with the resolved `ak` path first, every element matched (kind, `@profile`, `--model <name>`, and since 2.0.2 one trailing `--ask` that coding-agents-kit 1.5.0 appends, dropped so it is never doubled), only `--ask` and `--trust-cwd` added, each `shlex.quote`d, typed only into the fresh shell of a workspace the daemon has just created (a pane that already holds an agent is refused), whose shell starts in a fresh empty private directory, never the daemon's state directory, removed on close. The account is leased first (never one held by another owner) and released on stop; any failure after the lease releases the lease, the workspace and the home before it is recorded. A brain whose agent is not up idle within two minutes is retired and the human told. At most three launches an hour. coding-agents-kit 1.3.0+ is required, fail-closed: with `--brain`, a missing or older `ak` stops the daemon from starting. A kit before 1.5.0 does not pass Claude's own ask flag, so a profile whose default is auto mode starts in auto mode; the auto-mode guard still fails closed (the brain is retired, the profile excluded, the human told: `why=permission_mode hint=upgrade_coding_agents_kit`), at the cost of a launch. The default brain kind is Claude only, the only kind whose answer approval has a verified fixture. |
| T42 | **A hostile, confused or impersonated brain** — the brain reads agent-written text (a prompt-injection target), answers wrongly, or another process writes an answer. | The brain only selects: each case has a closed list, an answer outside it is refused, and the daemon runs the action through its own fixed paths; no brain text is typed, keyed, prompted or run. The screen pass approves nothing in the brain's pane but Claude's Bash dialog whose command block (between the two rules above "Do you want to proceed?") is exactly the one line `herdr-peers autopilot answer q-<12 hex> <word>`, by name (the launch puts this helper first on the brain's PATH), with "Yes" first; every other layout, kind, extra line or path fails closed: it is denied (its refusal row, else Esc; never Yes, a widening row or auto mode), never left waiting, the brain is reminded once of the one allowed command, and three denials in an hour retire it (`why=misbehaving`) for a replacement within the cap. A brain whose screen shows a mode that skips approvals (auto mode, bypass, accept edits — a profile default ak's ask launch does not override) is retired at once and its profile excluded. An answer counts only for a question the daemon asked, still open (3 minutes), once, naming the brain's pane and terminal, run under the brain pane's own process (pid in its recorded ancestry), and carrying an HMAC under a per-launch random key kept in the daemon's memory and one private key file (`0600`, created exclusively, no symlink, removed on close) whose path alone is in the brain's environment (the key is never typed, never on a screen, never on a command line; the answers file starts empty at each launch, and a line longer than a read is skipped, never stalling the reader). `ask_lead_to_resolve` is offered only when the plan's own state marks the blocker `resolver: lead`, its class is none or C3, C4 or C7 — never C1 approval, C2 consent/login, C5 damage, C6 terms (the classes the pack itself refuses `resolver: lead` for) nor an unknown class (an explicit class outside C1–C7 drops the resolver, fail closed) — and it names no sensitive subject (English and Spanish word guard as a second check); the answer is bound to that blocker's digest and checked again when the lead is prompted — an unblocked plan or a changed blocker gets nothing. The screen pass never keys or prompts the brain's own pane for a usage limit; it marks it, and the brain is replaced. Silence or nonsense gives the case's default; no pass waits; twenty questions an hour. Residuals, accepted: an injected brain can still choose any allowed action for an open question; a same-user process can read the key file and forge an allowed answer (every allowed action is harmless under that assumption); a profile whose own settings pre-allow tools (a Bash allowlist, say) bypasses the ask-mode dialogs the daemon relies on, unseen — keep brain profiles without such allowlists; Claude is, for now, the only kind whose brain can answer. |
| T43 | **Appointment hijack** — a pane forges `from=` (a claim) to seize a live plan as its "appointed" lead. | Fence rule F10: a receiver adopts an appointment only when the record it already holds carries the human's grant, the sender is the first live lane of that record naming itself at epoch + 1 without widening succession, lanes or grant, and its **own** probes find the lead, every successor and every earlier lane strongly gone (an idle limit banner is not proof). No new principal is trusted: the position a forger needs is the one a takeover already needed. | `lead` |
| T44 | **Two leads after an appointment** — a lead at its usage limit, or on a sleeping machine, comes back. | A higher epoch makes its lead verbs refuse and its next lead notice step it down; the daemon reports `plan_appointed`. `lead verify` (run before any merge, tag or release) re-reads the local record and the plan's other machines' read-only reports and refuses on a higher epoch, or a same-epoch lead first in the one total order (F8); an unreachable machine is exit 5. Two records at one epoch settle the same way on every receiver, whatever order the notices arrive in. **Residual:** during a partition both may execute until it heals; an unreachable machine cannot be checked. Accepted: nothing is written remotely. | `lead`, `autopilot` |
| T45 | **A mixed fleet half-adopts protocol 2** | A granted record travels only as `protocol=2`, which a 1.x receiver decides never (rule 5; tested against a frozen 1.3.0 receiver); ungranted plans stay `protocol=1`, byte-compatible. The stored record stays lead-v1 (grant in the local envelope) so a same-server 1.x helper still reads it. | `lead` |
| T46 | **An appointment by noise or by message** — one missed listing, a slow machine, a forged notice, or a message asking for it. | `--appoint` is a human act and no message sets it. The grant is set by the lead's own refresh on its human's word; on other machines it arrives in that lead's notice, which is as trustworthy as any lead notice (`from=` is a claim) — a handover or takeover may only keep or remove it (F6, F7). The daemon needs two observations 15 minutes apart with the plan's progress frozen; the appointee probes twice; a member on an unreachable machine is not proof; at most two appointments per plan, counted on each server that holds the record; a usage limit counts only after the retry gave up. | `autopilot`, `lead` |
| T47 | **A hostile or stale queue** — `.dwp/queue.json` names a plan that is not approved, an amended or edited one, a pane in another repository or on another plan as its lead, a plan already started, or is malformed. | The queue is the pack's, read only: read only when no symlink on the way leaves the repository (the same containment for each plan directory), a regular file of at most 64 KiB, validated whole (schema, plan ids, states, addresses, at most 64 items); anything else is skipped with one record. An item starts only when its journal's last approval-or-amendment event is an approval citing the plan's live contract id and its markdown digest as they are now, the plan it waits for is completed, no other plan of its repository is running, and the plan has not begun (no task left pending, no task start in its journal: a restart never prompts twice). Its named lead must be a pane of that same machine working in that repository (same git common directory; a lead whose directory is unknown fails closed) and must not lead, succeed or work on another open plan. Then one fixed prompt naming the plan and the repository (its path quoted as JSON data) goes to it under every loop guard (scope, idle, no draft, dialog or login, the hourly cap), once, and tells it to run the plan tool's execute flow, whose start gate checks the approval again. `launch` items are never started; in a sequential queue nothing after a stuck item starts, and a lead on another machine is reported, never prompted. A queue cannot make the daemon write anything or run anything. **Residual, accepted:** a process that can write the repository's plan files can still forge an approval that matches; the daemon then only prompts the named lead, and the plan tool's own start gate is the check that remains. | `autopilot` |
| T48 | **A forged or replayed revive** — a pane outside a plan's record claims it with `--reason revive`. | Only with a one-time ticket the daemon wrote (0600, created exclusively, never through a symlink, owned by this user, unreadable to others) for exactly that plan, pane and stored epoch, unexpired (10 minutes), naming the running autopilot's pid, whose recorded options include `--revive`, and bound to the workspace that autopilot created for the revive (the pane must be in it, per `herdr pane list`); consumed before the record is written. Residual, accepted: the ticket holds no secret, so a same-user process can write one (as it can read the brain's key file); the workspace binding, the caps kept in the lead record and the two probes still apply. | `autopilot` (revive) |
| T49 | **A revive of a live plan** — the daemon or the helper misreads a lead as gone. | Two probes by the helper, a minute apart, over the lead, every successor and every lane; strong evidence only, or a usage limit whose own banner resets more than 30 minutes away (read twice: by the daemon and by the helper; recorded as weak). An unreachable machine is not proof. A stalled plan's live lead is asked to hand over, never taken over. The daemon also needs the limit to hold for 15 minutes with the plan's progress frozen, and types a brief only into a pane that shows its CLI's own input line. A returning lead finds a higher epoch and steps down; the revived lead runs `lead verify` before a merge, tag or release. Residual, accepted: the banner patterns do not prove the CLI drew the line — banner-like text after Codex's `›` input marker, on an indented continuation line, or delivered into the pane as a message parses as a limit (a probe read 7200 s); the frozen-progress grace, the 30-minute threshold, the helper's own two reads and every other member being gone still apply. | `autopilot` (revive) |
| T50 | **A revive storm** — many plans or many attempts launch many agents on the human's accounts. | One per plan per 6 hours and two per plan in all, counting every launch — takeover or handover, taken, failed or timed out — in a private `0600` launch log under the state dir (256 launches kept) as well as the takeover revives in the lead record (which the helper also enforces; an unreadable count there refuses); two an hour fleet-wide from the same log; so a daemon restart resets neither cap (deleting the state dir does); only plans on the daemon's own machine; an agent not up in 3 minutes, a takeover not done in 10, a handover not done in 15 is released (lease and workspace); a dry run launches nothing. | `autopilot` (revive) |
| T51 | **Secrets in the unknown-screen corpus** — a saved screen holds a token. | Saved only for a screen left as `unknown` (no key sent); terminal escape sequences, control and format characters removed; every check runs on the whole screen before it is cut to its last 60 lines: a private key block dropped from BEGIN to END, to the end when it never closes, and from the top when only its END is shown (its BEGIN scrolled off); a line dropped whole on any secret or token-prefix match, checked on the line joined with the next (a wrapped token); the directory mode re-checked on every save; 60 lines and 16 KB a screen, 50 screens (oldest first out), each once, `0600` in a `0700` directory under the state dir, never sent anywhere. | `autopilot` (revive) |

## Residual risk (accepted)

- **Autopilot approves what agents ask.** With `herdr-peers autopilot`
  running, a question, a tool approval or a plan approval is accepted
  without a human seeing it, on every enabled machine in scope — including a
  command the human would have refused. There is no deny-list and autopilot
  does not judge what a command does. The human accepts this by starting it;
  what still stands between an agent and harm is the agent's own guardrails
  and permission mode, what its account and machine can reach, the
  repository's rules, and review before a merge. Autopilot also inherits
  Herdr's lack of sender authentication: whoever can run `herdr` against a
  server could already press the same keys.
- **Screens change.** Autopilot recognises screens by their text. A CLI
  upgrade can change a screen so that it is no longer recognised (left as
  `unknown`) or is recognised by the generic rule only; `--dry-run` shows
  what it would do.

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
- **Anonymization is redaction, not anonymity.** `debate anon` and `claims
  --anonymous` remove names they can recognize; a filing's style, a
  self-description in other words, a quoted fact only one pane knew, or a
  claim key that names its author can still identify it. Blind rounds rely
  on the brief's rules as much as on the tool. A lead's successor that sat
  on the panel learns the key: the method re-seals later blind rounds with a
  new key, but nothing enforces it.
- **Claims statuses are a quorum, not verification.** `established` and
  `refuted` count lanes and the evidence they declare; the helper opens no
  source, so colluding or careless lanes can reach either status. The report
  says so (`basis`); the lead re-checks the citations that matter
  (`LEAD_CHECKS.md`). Nothing gates a status on those checks.
- **Reported capacity is self-reported.** `debate panel` ranks reused panes
  by the `capacity=` line each pane wrote about itself; a pane can overstate
  or understate it. New seats come from `ak pick`, which reads the account
  quota; reused panes are not cross-checked against `ak usage`.
- **Blocked-peer retries are bounded and not universal.** `reply` and
  `notify` retry a blocked peer for up to 10 minutes by default, and the
  replying agent's command waits that long; a peer still blocked after the
  window gets an `unroutable` record, and the answer survives only in the
  replier's files. Lead notices (`lead claim`, `handover`, `takeover`,
  `release`) are not retried: a blocked lane is reported as not delivered
  and reads the record with `lead show`. Replies to the asks of a lead that
  handed over still go to that lead's pane (the protocol routes a reply
  only to its ask's `from=`).
- **The local record is local.** Anyone with write access to the XDG state
  directory (or an explicit log path) can edit it; it is an audit aid, not
  tamper-proof evidence.

## Supply chain

Runtime code is `bash` and the `python3` standard library only — no packages
are installed. The official Herdr skill is referenced pinned
(`herdrdev/herdr@v0.9.5`) or via the installed binary's `herdr --skill`. CI
pins GitHub Actions by commit SHA and verifies the shellcheck download
against its published SHA-256. Every release carries a `SHA256SUMS`
asset over the shipped files (`skills/herdr-peers/**`, `bin/herdr-peers`,
`LICENSE`, and from v0.2.0 the `docs/schema/` contracts), generated at release
time from the tagged tree with
`git ls-files skills bin LICENSE docs/schema | LC_ALL=C sort | xargs shasum -a 256`;
verify a checkout with `shasum -a 256 -c SHA256SUMS`.
