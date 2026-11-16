# Changelog

All notable changes to herdr-peers are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Since
1.0.0 a breaking change to the public interface bumps the major version, and
a wire-format change also bumps the protocol number (before 1.0.0, breaking
changes bumped the minor version).

## [Unreleased]

### Changed

- **The default `--brain-kinds` is `claude`** (was `claude,codex,grok`):
  Claude is, for now, the only kind whose answers the daemon approves, so a
  brain of another kind only spent the hourly launch cap. Other kinds can
  still be named.

### Fixed

- **Why a brain was retired is recorded**
  ([#54](https://github.com/DailybotHQ/herdr-peers/issues/54)). The record
  and the log line of a `brain_replaced` carry `why=` (`gone`,
  `usage_limit`, `start_timeout`, `permission_mode`); a profile excluded for
  starting in a mode that skips approvals is recorded as
  `brain_profile_excluded why=@profile`. The map's brain block gains
  `excluded` and `retired` (optional: a 2.0.0 map is still read), `fleet ui`
  shows them, and `autopilot status` prints a brain line. A
  `permission_mode` retirement names its likely cause and fix
  (`hint=upgrade_coding_agents_kit`: a kit before 1.4.1 does not pass
  Claude's own ask flag, so an auto-mode profile starts in auto mode).
- **The loop forgets queue state it no longer needs**
  ([#51](https://github.com/DailybotHQ/herdr-peers/issues/51)): keys of
  items or queues a machine's report no longer lists are dropped (only after
  a report that answered), and a reason that clears and returns is reported
  again.

### Documentation

- The skill covers everything new in 2.0: the `autopilot` verb row names
  `--appoint`, `--brain`, `--notify` and the plan queue; `autopilot answer`
  has its own row (the brain's verb only); `lead show` names `lead-v2` and
  protocol 2; the environment table adds the notify timeout and budget, the
  appointment grace and probe gap, and the two variables set by the helper
  and the daemon (`HERDR_PEERS_UI_SERVER`, `HERDR_PEERS_BRAIN_KEY_FILE`); the
  trust boundary gains a 2.0 paragraph (the brain's workspace and key file,
  appointment, the read-only queue); the description mentions the queue, the
  brain and appointment; the migration guide is named.
- `orchestra.md` §10, *Leading on 2.0*: the grant, `lead verify` before every
  merge, tag or release, `--as-lane`, stalled plans under `--appoint`, the
  queue, and the brain is not a lane.
- `autopilot.md` §16, an environment reference with every default from the
  code; the README names what is new in 2.0 and links the migration guide at
  the top, and describes the queue in the loop's layer.

## [2.0.0] - 2026-11-16

The 2.0.0 release: lead appointment under protocol 2, the daemon's brain, and the plan queue.
Upgrading from 1.x: [docs/MIGRATING.md](docs/MIGRATING.md).

### Breaking

- **Protocol 2.** One message only is stamped `protocol=2`: the lead notice
  of a plan whose lead record carries the appointment grant (`lead-v2`).
  Every other message — asks, replies, notices, lead notices of ungranted
  plans — stays `protocol=1`, byte-identical to 1.x. A 1.x receiver decides
  protocol 2 never and fails closed (tested against a frozen 1.3.0
  receiver). `metadata.protocol` and `--version` report 2. Every lane and
  successor of a granted plan must run 2.0 or later; until you grant
  appointment on a plan, a 2.0 fleet is wire-identical to 1.x.

### Added

- **The plan queue.** With `--loop`, when a repository's current plan
  finishes, the next approved plan in its `.dwp/queue.json` (`dwp-queue-v1`,
  written by the DeepWorkPlan pack, read only by the daemon) starts: its
  named lead gets one fixed prompt naming the plan and the repository, once,
  one plan at a time per repository unless the queue is parallel. A plan
  starts only when its approval cites its live contract and plan digest as
  they are now, its lead works in that repository and on no other open
  plan, and it has not already begun (a restart never prompts twice). Items
  that cannot start for a reason the developer must fix are reported once
  (`queue_blocked`); a started item emits `plan_queued_started`. `fleet ui`
  gains a Queues view (`u`) and each plan shows its place in its queue;
  `herdr-peers fleet` lists the queues.
- At start, under its lock, the daemon removes the brain key files and
  brain directories a killed daemon left behind (never through a symlink).
- **Lead appointment.** When a plan's lead and every successor are gone, the
  plan's first live lane may take the lead — only under the human's
  standing grant (`lead claim --allow-appointment [--any-kind]`,
  `--no-appointment`) and only on strong evidence, which the lane's helper
  checks twice (`lead takeover --as-lane`; no `--reason`; a member on a
  machine that cannot be reached is not proof). Receivers verify it with
  their own probes (fence rule F10). Two records at one epoch settle by one
  total order — the previous lead, then its successors, then its lanes —
  whatever order the notices arrive in. At most two appointments per plan.
- **`lead verify --plan P`**: before a merge, tag or release, is this pane
  still the lead here and on the plan's other machines (read-only reports)?
  Exit 4 on a newer or earlier-ranked lead, exit 5 when a machine cannot be
  reached (`--allow-unreached` accepts that, recorded). Nothing is written
  to git or any remote.
- **`autopilot --loop --appoint`**: the daemon asks the first live lane of a
  granted plan to take the lead once lead and successors have been gone for
  15 minutes (`HERDR_PEERS_AUTOPILOT_APPOINT_GRACE`) with no progress; a
  live successor always comes first; a lead at its usage limit counts only
  after the screen pass gave up on it. Events `plan_appointment_prompted`
  and `plan_appointed`.
- **`autopilot --loop --brain`: the daemon keeps a brain it launches
  itself.** A dedicated decision agent on the human's best account
  (`--brain-kinds`, default claude, codex, grok; `--brain-model kind=model`),
  launched in ask mode through coding-agents-kit 1.3.0+ in a workspace and
  an empty private directory of its own, briefed once, replaced when gone or
  at its usage limit, retired at once if its profile skips approvals,
  released and closed on stop. The daemon asks it only what its rules cannot
  decide — a stalled plan, a blocked plan its lead may resolve, an unknown
  screen — and acts only on one action from that case's closed list,
  answered with `herdr-peers autopilot answer <question> <action>`. The only
  approval the daemon gives the brain is that one command; anything else, or
  silence, gives the case's default.
- Brain answers carry an HMAC under a per-launch key held in a private
  `0600` key file whose path alone is in the brain's environment (never on a
  command line or a screen); an `ask_lead_to_resolve` answer is bound to the
  blocker it was about; a brain not up within two minutes is retired; a
  failed launch releases everything it took. **`--brain` is fail-closed:** a
  missing or older coding-agents-kit (before 1.3.0) stops the daemon from
  starting.
- The fleet map and `fleet ui` show the brain: state, account, questions in
  the last hour, last decision.
- Contracts: `lead-v2` (`lead-v1` plus `appoint` and `via`); `plans-v1`
  gains `appoint` and `appointed`; `plan-event-v1` gains
  `plan_appointment_prompted`, `plan_appointed` and `needs_human`.
- **Docs:** [docs/MIGRATING.md](docs/MIGRATING.md); the README as a product
  page; `autopilot.md` as the operator's manual (one minute, the loop, the
  brain, appointment, notify, watching, cost, limits, troubleshooting, and
  where each guarantee is tested); a short list of the residual risks you
  accept at the top of `docs/SECURITY.md`.

### Fixed

- `herdr-peers autopilot logs -f` test: the follower is waited for before a
  line is appended (it raced its own start-up on a loaded machine).

## [1.3.1] - 2026-11-16

### Fixed

- **The protocol text now defines the address alias the helper has accepted
  since 1.2.3** ([#42](https://github.com/DailybotHQ/herdr-peers/issues/42)).
  `protocol.md` §2 says that `local:<pane>` and `<this server's own saved
  id>:<pane>` name the same pane, and rule 7 matches a reply's `from=`
  against the asked peer or that alias. A pane on any other machine is
  never an alias. Doc only, no wire change.
- **The notify budget of a pass is real**
  ([#43](https://github.com/DailybotHQ/herdr-peers/issues/43)). All notify
  commands of one pass share `HERDR_PEERS_AUTOPILOT_NOTIFY_BUDGET` (default
  20 s, 1–120); a larger per-event `HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT`
  no longer widens the pass.
- **Schema links work in an installed skill**
  ([#44](https://github.com/DailybotHQ/herdr-peers/issues/44)). `autopilot.md`
  linked `../../docs/schema/`, which only exists in this repository; the
  `fleet-v1` and `plan-event-v1` schemas now ship in `skills/herdr-peers/schemas/`
  (kept byte-identical to `docs/schema/` by a test), and the `skill` scope
  refuses a link that leaves the skill directory.
- **One validator for the fleet map** (#44). The writer (`store_fleet`), the
  reader (`fleet`) and the watcher (`fleet ui`) use the same `valid_fleet`,
  so a map is never printed by one and refused by another.
- The unused `GONE_REASONS` constant is removed (#44).
- The test runner checks that every scope file parses before running it:
  a scope that bash cannot parse no longer stops early and looks green.

## [1.3.0] - 2026-11-15

### Added

- **`autopilot --loop`: every open plan runs to its end.** The daemon a
  human starts now also watches every plan that has a lead record, on
  every enabled machine. The idle lead of a plan that is not finished gets
  one fixed prompt to continue it — after its pane has been unchanged for
  5 minutes, never while its lanes work or it awaits a reply, never over a
  draft, a dialog or a login. A blocked plan is left and recorded; three
  prompts without progress stop the plan (`plan_stalled`); a lead that is
  gone has its first reachable successor asked to run `lead takeover`
  (once per epoch), or the plan is recorded `plan_no_lead`. The daemon
  never writes a lead record, sends no protocol message and launches no
  agent. Without `--loop` nothing changes.
- **One daemon for every machine.** Each machine reports its own plans:
  the daemon reads its own in process and, for every other saved machine,
  sends a self-contained report module on standard input to `python3` over
  that machine's SSH target (`ssh -o BatchMode=yes … -- <target> python3
  -`). Nothing is installed or required on the other machine but python3.
- **`herdr-peers plans [--json]`** (`plans-v1`): the plans led on this
  machine with their class (`open`, `blocked`, `completed`, `unreadable`)
  and progress. Works outside a Herdr pane.
- **`herdr-peers fleet [--json]`** (`fleet-v1`): the loop's map of every
  machine, its agents with repository and branch, the plans and each
  agent's role in them. The daemon leaves every machine a copy, so any
  agent on any machine can read it.
- **`--notify "<command>"`**: with `--loop`, run a command (no shell, its
  own process group, a minimal environment, `--notify-env NAME` to pass a
  variable) with a `plan-event-v1` object when a plan stalls, is blocked,
  loses its lead, its lead record goes stale, or it completes.
- `HERDR_PEERS_AUTOPILOT_GRACE`, `HERDR_PEERS_AUTOPILOT_SSH_TIMEOUT` and
  `HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT`.

- **`herdr-peers fleet ui`**: a live terminal watcher of the whole fleet.
  A header with how old the picture is and counts by state; agents grouped
  by plan (lead, lanes, successors, the plan's progress and current task,
  plans that need you first), with the agents working outside plans and
  those doing nothing as groups of their own — or by repository or machine.
  Open a plan (progress, current task, its tasks, the blocker, the summary
  from its `PROGRESS.md`) or an agent (its plans, its live screen, focus its
  pane) with Enter or a click. Redraws by itself when the map changes.
  `--snapshot` prints it once as text. Standard library only (curses).
- The map carries each agent's session title and time in its state, and
  each plan's progress and, while open or blocked, its detail.

### Changed

- A bounded dry run (`autopilot --dry-run --once` or `--passes N`) no
  longer takes the single-instance lock, so it can run beside a running
  autopilot; it writes no map and runs no notify command.

### Security

- Threat model rows T34–T38 (`docs/SECURITY.md`): the loop's `ssh` command,
  a hostile answer from a machine, a hostile lead record or plan state, the
  map written on other machines, and the notify command.

### Fixed

- **A background autopilot skipped the pane it was started from.** The
  own-pane rule exists so a foreground autopilot never keys the pane it
  runs in; a background one has no pane, so the pane that ran
  `autopilot start` is an ordinary agent pane. A lead that started the
  daemon stayed blocked at its own questions. It is now watched like any
  other; a foreground autopilot still never keys its own pane.
- A regression fixture for a multi-question form with tabs
  (`claude__blocked__question_tabs_recommended_es`): the recommended
  option of each tab, then the review screen's Submit.

## [1.2.4] - 2026-11-15

This release adds features, which by the book is a minor version. It stays in
1.2.x on purpose: 1.3.0 is reserved for the loop programme.

### Added

- **Autopilot in the background.** `herdr-peers autopilot start` (alias
  `on`) starts autopilot as a detached process that survives the pane that
  started it; `autopilot stop` (alias `off`) stops it and waits until it
  exits; `autopilot status` shows, from any pane, whether it runs, its pid,
  since when, how it was started (background or a foreground pane), its
  options, its log and its last ten actions. `autopilot` with no verb is the
  foreground mode, unchanged. Start takes the same options as the foreground
  run except `--once` / `--passes`, refuses while one runs (exit 4), and
  fails with the log's tail if the process dies at once. No login item or
  service is installed: after a reboot or a Herdr restart, run
  `autopilot start` again.
- **`herdr-peers autopilot logs`** prints the last lines of the background
  log (`--lines N`, default 50) and with `-f` / `--follow` keeps printing new
  ones across a rotation, read-only and through `safe()`.
- `autopilot.out` (the background log, `0600`, rotated to `autopilot.out.1`
  at 1 MB) and `autopilot.json` (the options it runs with, `0600`), in the
  state directory, never opened through a symlink. Threat model row T39.
- A pass line, `pass N: M machines, K agents, A actions, T s`, when a pass
  acted, and on every tenth idle pass so a watcher can see it is alive.

### Fixed

- **A stop that landed during a pass could be swallowed.** The signal
  handler raised an exception that the per-pane guard caught, so `stop`
  ended one pane's visit instead of the loop. It now always ends the loop,
  and `stop` waits up to 10 seconds to confirm it.
- **The own-pane skip matches the terminal too**, so a new pane that reuses
  the id of the pane autopilot started from is not skipped.

## [1.2.3] - 2026-11-15

### Fixed

- **`check` refused a genuine reply stamped with this server's own saved
  machine id** ([#35](https://github.com/DailybotHQ/herdr-peers/issues/35)).
  A peer on this server is both `local:<pane>` and `<saved id>:<pane>`; the
  caller now treats the two as the same peer, in both directions, in `check`
  and in `wait`'s pane capture. The machine part must be `local` on one side
  and this server's own saved id (`HERDR_PEERS_SELF`, the cached self probe,
  or a fresh probe) on the other, and the pane must be the one asked: a reply
  from another machine with the same pane id is still a conflict.
- **A reply to a local asker is signed `local:`.** When the ask had not been
  recorded by `check` (a `reply --message`), the reply took its own address
  from the cached self probe and stamped the saved machine id even to a
  caller on the same server. It now signs the way `check` records it:
  `local:` to a local asker, the saved id only to a caller on another
  machine, whose reply route needs it. This is how two of eight replies were
  refused on a real run.

## [1.2.2] - 2026-11-15

### Fixed

- **Autopilot left a question that shows a preview beside its options.**
  The preview box runs several lines under the last option, more than a
  live menu was allowed to have beneath it, so the pane was recorded as
  `unknown` and never answered. A block may now have up to 16 lines under
  it when one of them says that Enter selects. Found on a real pane.
- **The recommended mark is recognised in other languages and on a wrapped
  label line.** `(Recomendado)`, `(Recomendada)`, `(Recommandé)`,
  `(Empfohlen)` and `(Consigliato)` count like `(Recommended)`, also when
  the label wraps and the mark sits on its second or third line.
- An option's label ends at a wide gap, so text of a preview drawn on the
  same line is never read as part of the label (it could have named a
  refusal or a permission-widening phrase).
- Fixtures `claude__blocked__question_with_preview` and
  `claude__blocked__question_preview_recommended_third`.

## [1.2.1] - 2026-11-15

### Fixed

- **Autopilot left a question whose options have long descriptions.** A
  numbered option followed by more than three description lines ended the
  menu early, so the block had one row and the pane was recorded as
  `unknown` and never answered. Found on a real pane within the first hour
  of 1.2.0. A numbered or radio option may now carry up to 12 lines before
  the next row; unnumbered blocks keep the short limit, because they are
  told from other text only by their column. Fixture
  `claude__blocked__question_long_descriptions`.

## [1.2.0] - 2026-11-15

Protocol stays **1**: no stamp, grant, rule, verb, flag, exit code or JSON
contract of 1.1.0 changes. The release is additive.

### Added

- **Autopilot** ([`autopilot.md`](skills/herdr-peers/autopilot.md)) —
  `herdr-peers autopilot`, a daemon a human starts once so that no agent
  waits for an approval. It watches every agent on every enabled machine
  and, on a waiting screen, presses the keys that accept an option, then
  re-reads the screen to confirm, step by step until the dialog is done.
  - **What it accepts:** questions (single, several with a review step,
    multi-select), tool approvals (command, file edit or creation, URL
    fetch), plan approval, folder trust, an update prompt (skipped), a
    question queued while a Codex turn is still working.
  - **Which option:** the one marked `(Recommended)`, else the one the CLI
    pre-selected, else the first. Never a refusal, never free text, never a
    row that widens the agent's standing permissions (`always allow`,
    `allow all … during this session`, `don't ask again`, `Run Everything`,
    auto mode, bypass permissions, persisted settings) — so plan approval
    is accepted with "manually approve edits", not "use auto mode".
  - **Agents that stop to ask in prose** get one fixed prompt to continue
    with what they recommended — at most 3 per pane per hour, only after a
    turn of their own, never when the input line holds a human's draft.
  - **Usage limits** (the CLI's own banner, not a `429` in a command's
    output) are retried every 30 minutes for at most a day; **logins** and
    Claude's bypass-permissions acknowledgement are never touched.
  - **An input line is never mistaken for a menu:** a block of options
    counts only at the bottom of the screen with no input line under it,
    and outside a `blocked` state only when it says that Enter selects.
  - **Verified on real panes** of Claude Code, Codex, Cursor, Grok, Pi and
    Antigravity; screen fixtures with their expected decision in
    `tests/fixtures/screens/`, including hand-written hazards.
  - **Cheap by construction:** asleep between passes (default 60 s), one
    `agent list` per machine per pass in parallel, a screen read only when
    a pane's state changed, backoff for unreachable machines; about one
    second of CPU per pass on 14 machines with 59 agents.
  - `autopilot status`, `autopilot stop`, `--dry-run`, `--once`,
    `--passes N`, `--interval S`, `--exclude`, `--scope`, `--no-nudge`,
    `--catch-up`; `HERDR_PEERS_AUTOPILOT_CONFIRM`. One instance per server.
  - Every action is recorded in the delegation log with `role: autopilot`
    (states `keyed`, `nudged`, `left`, `gave_up`): the screen class and the
    keys, never screen text. `delegation-record.json` gains those values.
- **Launching several agents at once** — `launcher.md` documents how a lead
  opens a tab of agents with `ak`, on chosen accounts and vendors, gives
  each its brief and watches them with `lanes`.
- Test scope `autopilot`; the fake `herdr` can script a dialog that moves
  on when it is keyed (`<machine>/keys.json`).

### Changed

- `orchestra.md` §2: with autopilot running, a lane blocked at a question or
  a permission needs no escalation. The rule for agents and leads is
  unchanged — they key only folder trust, and never start autopilot on
  their own. Protocol §13 states that autopilot is outside the protocol and
  that no message can start or steer it.
- The threat model gains T28–T33 and the accepted residual risk that
  autopilot approves what agents ask, without a deny-list.

### Known limitations

- Autopilot sees only panes Herdr lists as agents; a CLI stopped at a
  first-run screen before Herdr detects it is not reached.
- OpenCode's screens are not verified. Codex's start-up update prompt is
  matched from its documented shape, not from a live capture.
- Screens are recognised by their text and can change with a CLI upgrade.

## [1.1.0] - 2026-10-25

Protocol stays **1**: the ask, reply and notice stamps, the reply grant, the
loop guard, depth limit 1, the fan-out cap and every existing verb, flag,
exit code and JSON contract are unchanged. The release is additive.

### Added

- **Debates for any purpose, a native sub-skill**
  ([`debate.md`](skills/herdr-peers/debate.md)). A lead runs a panel of
  peers through rounds and closes with one trustworthy result. The lead
  chooses the **purpose** first — **decide**, **research** the state of the
  art, **stress-test**, **verify**, **generate** — and each purpose has its
  formats, its counting and its deliverable; purposes chain (research →
  decide, decide → verify). Also: sizes (quick, standard, deep); the lead's
  contract (never votes, the human's words verbatim, one channel, filings on
  disk with one-line replies, no external actions); nine formats (angle
  research, classic rounds, draft package, claim-by-claim cross-exam, red
  team then defenders, steelman then judge, blind fresh-context challenge,
  replication panel, divergent proposals) with a forced verdict space for
  decisions; brief design (scope, settled results, premise ledger and
  dead-objection rule, questions or per-angle sub-questions, weighted
  criteria); a lane and angle catalog per purpose (for research: literature,
  industry, open source, vendors, practitioners, history, standards,
  economics, risks, frontier, skeptic, contrarian); evidence levels and
  dated sources; bias control (context resets, anonymized filings, sealed
  proposals, rotated sides, independence before triangulation, recusal);
  counting; operating and recovering a panel; closing with cross-review and
  a fix log; optional outputs for the team.
- **`herdr-peers debate`**, the lead's tools (`scripts/debate.py`, standard
  library only):
  - `tally FILE|DIR` counts a [`herdr-peers/ballots-v1`](docs/schema/ballots-v1.json)
    file, or a directory of per-pane `*.ballot.json` files (one ballot each,
    same options and items), so the lead never retypes a ballot: Borda, first places, Copeland, every pairwise duel, the Condorcet
    winner and loser, per-item verdicts (ACCEPT / AMEND / REJECT …, missing =
    ABSTAIN) and the median confidence; `--json` prints
    [`herdr-peers/tally-v1`](docs/schema/tally-v1.json). A voter named `lead`
    is always left out, as is every `--exclude` (in any case); a voter is one
    identity whatever its case or a `local:` prefix, and a hostile ranking
    shape exits 2 instead of a traceback.
  - `claims PATH… [--rounds] [--map M] [--min-lanes N] [--anonymous [--seed
    S] [--redact W]]` merges lanes'
    [`herdr-peers/claims-v1`](docs/schema/claims-v1.json) ledgers: each claim
    is `established` (enough independent lanes, a FACT with a source, two
    distinct sources), `agreed` (evidence bar not met), `contested`,
    `partial` (several lanes, fewer than `--min-lanes`), `single` (one lane),
    `unsupported`, `disputed` (enough disputing lanes, evidence bar not met)
    or `refuted` (enough disputing lanes with the same evidence bar as
    `established`), with the supporters' and the disputers' sources, FACT
    counts and median confidences reported apart, the vendors, coverage per
    lane and the claims only one lane raised. Statuses are a **quorum, not a
    verification** — the report says so (`basis`). `--rounds` takes the
    rounds in order and lets a lane's later ledger override its earlier one
    claim by claim, so a triangulation round keeps round-1 consensus; lanes
    are named without a `local:` prefix and matched case-insensitively.
    `--map` merges synonym keys; `--anonymous` names lanes `Lane_A`… and
    angles `Angle_A`…, drops vendors and redacts lane ids, addresses,
    profile handles, vendors, angles and model names from every claim's text
    and sources; `--json` prints
    [`herdr-peers/claims-report-v1`](docs/schema/claims-report-v1.json).
  - `anon SRC DST --key K [--seed S] [--redact W]` copies filings to
    `Filing_A.md`, `Filing_B.md`… in an order derived from a random 128-bit
    secret (or `--seed`) that is kept only in the key and never printed, so
    the filing names cannot rebuild the mapping; pane ids, Herdr addresses,
    profile handles, filename stems and model and vendor names are redacted;
    a filing that carries a secret-shaped value stops the run before
    anything is written; the mapping goes to a `0600` key that must sit
    outside both directories.
  - `filings DIR --expect a,b [--min-words N]` lists present, missing and
    short filings, exiting 5 while the round is incomplete — recover from disk
    and re-ask only the missing panes.
  - `panel --seats N [--kinds …] [--owner A] [--exclude …] [--all-workspaces]
    [--no-ak]` proposes a panel and runs nothing. Seats go round-robin over
    model **providers** (`codex-xai` counts as xai) for diverse
    perspectives; within a provider the seat with the **most quota** goes
    first: idle panes (by their last reported capacity) and — when agentkit
    (`ak`) is installed — the accounts `ak pick <kind> --owner <lead>`
    proposes are ranked together, known headroom first, then unknown, then
    `low`, an idle pane winning only a tie; `critical` panes and panes in
    another plan's lead record are never seated. Each
    reused pane gets its context reset (`/clear`; `/new` and Enter for
    Codex); each new seat its `ak lease`, pane split (`HERDR_PEERS_BRIEFER`
    set), `ak <kind> @<profile> --trust-cwd` launch and `ak lease release`.
    It reports the provider mix, whether it meets the diversity bar (three
    providers, none above half), and the two seats with the most quota as
    the lead's successors (another provider than the lead's first on a
    tie; seats of unknown quota fill the rest, with a note); without `ak` it
    recommends coding-agents-kit, also when the panel is filled.
  - Every debate verb accepts `--pane` (Codex lanes pass it on every call).
    [`herdr-peers/panel-v1`](docs/schema/panel-v1.json) with `--json`.
- **Standing preferences in every debate** (`debate.md` §3): mix model
  providers (at least three when available, none above half the panel,
  roles spread across providers), seat the agents with the most quota, and
  let the lead **hand over before it runs dry** — successors chosen by quota
  at claim time, `ak capacity --self` at every round boundary, a handoff
  packet and `lead handover` at `critical`. Every one-line reply ends with
  the pane's `capacity=` line.
- SKILL.md and the README recommend coding-agents-kit (`ak`, v1.0.1 or
  later) as an optional companion, never installed by an agent.
- Sixteen debate templates under `skills/herdr-peers/templates/debate/`:
  `HUMAN_NOTE.md`, `DEBATE_BRIEF.md`, `RESEARCH_BRIEF.md`,
  `STRESS_TEST_BRIEF.md` (pre-seeded claim keys, a claims ledger and the
  forced verdict filed as a ballot), `ROUND_BRIEF.md`, `ROUND_SYNTHESIS.md`,
  `LEAD_CHECKS.md`, `HANDOFF.md` (the lead's handoff packet, with each
  lane's last capacity), `ballots.json`, `claims.json`, `DECISION.md`,
  `STATE_OF_THE_ART.md`, `STRESS_TEST.md` (one verdict vocabulary — GO, GO
  with conditions, NO-GO — and a claims-status-to-ruling guide),
  `REPLICATION.md`, `FIXLOG.md` and `TEAM_BRIEF.md` (with an audio-script
  outline). Replies end with `capacity=… <@profile or ->`.
- **Delivery to a blocked peer.** `reply` and `notify` retry the delivery to
  a peer blocked at a question or approval (`agent_blocked`) with backoff
  for up to `--wait-blocked SECONDS` (default `HERDR_PEERS_BLOCKED_WAIT` or
  600, at most 3600; 0 tries once, as before) before recording the reply
  `unroutable` or refusing the notice. It is still exactly one reply: only
  the delivery is retried, each attempt under the log lock with the
  exactly-once check. Before, a reply to a lead whose pane showed a question
  to its human was closed unroutable at once and lost.
- `lanes` shows the last capacity a lane of the lead record reported to any
  pane of this server, so a lead that took over still sees it.
- A `debate` test scope with a fake `ak` (`tests/fakes/agentkit/ak`), a fake
  agent that unblocks (`<machine>/blocked.json`), and threat-model rows
  T23–T27 (hostile debate inputs, un-blinding, panel provisioning, secrets
  in debate files, delivery to a blocked peer).

### Known limitations

Recorded in [docs/SECURITY.md](docs/SECURITY.md) "Residual risk":

- Claims statuses are a quorum of lanes and their self-declared evidence;
  the helper opens no source and nothing gates a status on the lead's checks.
- Reused panes are ranked by self-reported capacity, not cross-checked with
  `ak usage`.
- A lead's successor comes from the panel and learns the anonymization key;
  re-sealing later blind rounds is a documented step, not enforced.
- Lead notices are not retried on a blocked lane, and replies to a former
  lead's asks still reach the former lead's pane (read filings from disk).

### Fixed

- The helper no longer writes `__pycache__` into the skill directory: the
  entry script runs Python with `-B` and the `debate` import sets
  `sys.dont_write_bytecode`. The bytecode embedded the checkout's absolute
  path in an installed skill and failed the `skill` scope's name checks
  locally. Found by the verification debate; a `skill` test pins it.

- `wait` no longer times out on a reply that reached the caller's pane. An
  agent's TUI (Claude Code, Codex) echoes a delivered prompt indented, with
  its prompt glyph on the first line, and `wait` only matched a stamp at the
  start of a line. It now accepts the indented stamp (still exact, still
  from the asked peer) and drops the glyph and indent from the body. It also
  re-reads the log every few seconds, so a reply that `check` recorded while
  `wait` blocked ends the wait.

### Changed

- Repository tooling: the vendored deepworkplan skill moved to 7.8.1, the
  pack's coding-agents-kit and devcontainer-kit pins moved to v1.0.1, and
  the existing addon pins remain herdr v1.0.0 and AI Diff Reviewer v3.3.14
  (skills-lock.json, .dwp/config.json). The shipped skill and helper are
  unchanged.

- Repository tooling: the vendored `deepworkplan` skill moved to 7.8.0 and
  the AI Diff Reviewer skill to v3.3.14, the pack's pins (`skills-lock.json`);
  the addon registry records herdr v1.0.0. The shipped skill and helper are
  unchanged.

## [1.0.0] - 2026-10-13

The first stable release. Protocol stays **1**; the helper's behavior, wire
formats and schemas are unchanged from 0.3.3.

### Changed

- The public interface is now committed to Semantic Versioning: a breaking
  change to any of the following bumps the major version, and a wire-format
  change also bumps the protocol number.
  - The CLI verbs `list`, `ask`, `notify`, `wait`, `check`, `reply`,
    `status`, `lanes`, `lead claim|show|handover|takeover|release`, `log`
    and `cancel`, their documented flags, and `--version` and `--skill`.
  - Exit codes `0`–`7` and the documented `HERDR_PEERS_*`, `DWP_PLAN` and
    `DWP_TASK` environment variables.
  - Protocol 1: the ask, reply and notice stamps, the reply grant, the loop
    guard, depth limit 1 and the fan-out cap.
  - The JSON contracts `herdr-peers/lanes-v1`, `herdr-peers/lead-v1` and
    the delegation record (`templates/delegation-record.json`).
- Since v0.3.3 only the version moved to 1.0.0 (SKILL.md, the helper's
  `--version`, the README install pins and SECURITY.md); there are no
  functional changes. 0.x releases are no longer supported.

## [0.3.3] - 2026-10-12

Protocol stays **1**; the helper, wire formats and schemas are unchanged.

### Changed

- The README carries the herdr-peers logo (light and dark variants in
  `assets/`), a feature overview of asks, notices, the control plane, plan
  leadership and the delegation record, repository-qualified plan ids,
  `--version`/`--skill`, and the `lead-v1` schema in the documentation map.

## [0.3.2] - 2026-10-12

Protocol stays **1**. `lead-v1` gains optional `repo_root`; legacy records
remain readable. Updated peers accept repository-qualified plan ids.

### Fixed

- Record the claiming repository git common root, preserve it through
  local succession; omit it from lead notices and fencing so older strict
  receivers keep working and remote machines receive no host paths. Refuse
  the current holder's active claims from a
  different repository with safe local root diagnostics and guidance to use `--plan <repo>/<id>`;
  cross-repository lane lookups keep working. Claims after release clear
  stale lanes and succession while keeping epochs monotonic.
- Accept and validate `lead show --pane`, matching `status`.
- Resolve `DWP_PLAN` ids under the caller's git checkout `.dwp/plans/`,
  mirroring delegation records without spurious missing-directory warnings.
- Tell idle lanes to end their turn for incoming asks instead of polling.

## [0.3.1] - 2026-10-12

Protocol stays **1**; wire formats and schemas are unchanged.

### Fixed

- Lead record changes (claim/refresh, release, handover and takeover) return
  success when the record was written, even if a listed pane is closed or
  unreachable. Failed notices still warn, are recorded, and do not stop
  delivery to reachable lanes. A handover whose designated new lead was
  not notified still exits 1, with recovery guidance and the record intact.
  `lead claim --lanes` replaces the list;
  omitted preserves it on refresh and empty clears it.
- `check` reports `current` with exit 0 when a lead notice matches the
  shared record. It remains a notice with no reply grant; fenced notices
  still exit 3, and adoption and `STEP DOWN` keep their existing statuses.
- `status` accepts the caller's `--pane` for validation only, without changing
  the positional peer it inspects.
- Launcher guidance distinguishes swarm lanes (no depth mark; they may
  ask once no ask is held) from one-shot delegates (`HERDR_PEERS_DEPTH=1`).
  The lead claims with empty lanes before launch, then refreshes the list
  as agents become ready or close.

## [0.3.0] - 2026-10-12

Protocol stays **1**: notices reuse the ask stamp's keys (`reply=no`), and a
0.2.x receiver decides every notice *never*. `herdr-peers/lanes-v1` stays
compatible (additive fields and screen class); new schema
`herdr-peers/lead-v1`.

### Added

- `notify <addr|lead> "<text>"`: a one-way notice stamped `reply=no depth=0`
  with the clause "This is a notice. Do not answer it." `check` decides
  **notice** (rule 14, exit 3), records it once (`notified received`; a
  repeated id is rule 12) and never replies. Notices use no fan-out slot and
  may be sent while holding an ask or as a marked delegate; they get the
  ask's hygiene (size, control characters, marker, secrets, scope). A
  `swarm-lead:` line is reserved for lead notices. Template `notice.md`.
- Plan leadership: `lead claim|show|handover|takeover|release` keep a
  `herdr-peers/lead-v1` record per plan (`plan, lead, epoch, succession[],
  lanes[], updated_at`; `docs/schema/lead-v1.json`) in the machine-scoped
  state (`leads/`, `0600`, atomic writes, no symlinks). Every change is
  recorded in the delegation log (and the plan mirror) and sent as a lead
  notice to every lane and successor, with `local:` addresses rewritten for
  remote receivers. Takeover is refused while an earlier successor is
  reachable, and while the lead is reachable unless `--reason` is recorded.
- Fenced acceptance of lead notices (protocol.md §12): first claim only from
  the briefer (`HERDR_PEERS_BRIEFER` or a recorded asker), handover and
  release only from the current lead at epoch + 1, takeover only by the first
  reachable successor at epoch + 1, ties to the earlier succession position,
  stale epochs rejected; a lead that adopts a newer epoch prints `STEP DOWN`
  and its lead verbs are refused.
- The address `lead` in `ask` and `notify` resolves to the current lead of
  `--plan` / `$DWP_PLAN` (falling back to the one record that lists this
  pane, for lanes whose `DWP_PLAN` is a child plan).
- Screen class `usage_limit` in `status` and `lanes`: the CLI's own limit
  banner (Claude, Codex, a generic "Rate limit reached/exceeded" or
  "Error: 429") anchored at the start of a screen line, so prose and quoted
  prompts do not match; also read from the last 15 lines of an idle or done
  lane, where it is a hint (a takeover on it needs `--reason`). Next step
  "hand off", never keyed.
- `lanes --json` adds `plan`, `lead`, `epoch` and a per-lane `capacity`
  parsed from `capacity=<verdict> [NN%] [@profile]` lines in recorded asks,
  replies and notices; lanes listed in the lead record appear even when
  never asked (`last: null`). The table gains a CAPACITY column.
- Delegation records: roles `notifier`, `notified`, `lead`; states `sent`,
  `received`, `claimed`, `refreshed`, `handed_over`, `taken_over`,
  `released`, `adopted`, `stepped_down`, `rejected`; optional `plan`,
  `epoch`, `capacity`.
- Tests: `lead` scope; notice fixtures with a frozen v0.2.3 receiver
  (`tests/compat/`) proving old peers decide *never*; every new assertion was
  shown to fail on a seeded defect first.

### Changed

- `reply=no` is now a notice instead of rule 9 *never* (rule 9 now covers any
  other value); the fixture `never-reply-no.txt` became
  `notice-grant-text-ignored.txt` and `never-reply-maybe.txt` covers rule 9.
- orchestra.md: lane ↔ lane asks (information and coordination; work is
  assigned only by the lead), authority comes from the plan (a relayed
  approval adds none), succession and handoff, lead notices.
  discipline.md §7 and protocol.md §9 use the escalation taxonomy C1–C7.
- Development harness only (the shipped skill is not affected): the vendored
  `deepworkplan` skill moved to 7.6.3 and the AI Diff Reviewer skill to
  v3.3.11, the pack's pins (`skills-lock.json`).

## [0.2.3] - 2026-10-12

Protocol stays **1**; the `herdr-peers/lanes-v1` schema remains compatible and
adds the terminal `unroutable` state.

### Fixed

- Runtime state is now isolated per Herdr server under XDG state storage
  instead of the checkout. Records carry `server_id`, shared explicit logs are
  filtered to the current server by default (`log --all-machines` shows all),
  and legacy checkout self caches migrate only after a terminal-id match.
- Replies carry the asked peer's address, so `wait` rejects caller-pane
  captures and accepts only replies from the peer that was asked.
- `wait` accepts the exact v0.2.2 reply stamp without `from` during mixed-version
  operation, records the sender as unverified, and warns until that peer is
  upgraded.
- Failed reply delivery is recorded as `unroutable`; when both sides can see
  the record, the caller's ask closes with that reason instead of timing out.

## [0.2.2] - 2026-10-11

Protocol stays **1**; the `herdr-peers/lanes-v1` schema is unchanged.

### Fixed

- Codex lanes could not `ask` or `reply` (exit 6, "names another session's
  pane"). Codex runs its tool commands from a per-profile app-server daemon:
  the commands have no terminal and are not descendants of the pane, and
  they inherit the daemon's `HERDR_PANE_ID` — the pane that first started
  that daemon — so every Codex lane on a profile after the first carried a
  wrong id. The stale-id guard was right to refuse it; the lane had no way
  to name its own pane. New `--pane <pane_id>` on `ask`, `reply`, `check`,
  `wait`, `lanes` and `cancel` declares this session's pane and wins over
  `HERDR_PANE_ID`. A declared pane is accepted when one of its foreground
  processes is an ancestor, or — for a caller with no terminal anywhere in
  its ancestry — when it runs the same agent program as that ancestry; a
  pane running another agent, and any terminal-attached caller outside the
  pane, are still refused. The inherited id never gets the same-program
  path. The refusal for a detached caller names the cause and the fix.
- `herdr-peers list` printed machine ids cut to 12 characters, which `ask`
  could not route. `list` now prints the full id, and `ask` and `status`
  accept any unique prefix of at least 4 characters (an ambiguous prefix is
  a usage error naming the candidates); records carry the full id.

### Changed

- Development harness: the vendored `deepworkplan` skill is 7.6.0 and the
  `ai-diff-reviewer` skill 3.3.9, upgraded through the pack's all-addons
  onboarding. Tests: a fake `ps` scripts Claude-style (child), Codex-style
  (detached, same program) and stale-id callers; the fake `herdr` reports
  process names; long machine ids cover the prefix resolution.

## [0.2.1] - 2026-10-11

Protocol stays **1**; the `herdr-peers/lanes-v1` schema is unchanged.

### Fixed

- `bypass_ack` (Claude's bypass-permissions acknowledgement) now escalates:
  "escalate to the developer: accept once per profile; never keyed by an
  agent". It is no longer in `UNBLOCK_KEYS`, so `status` never suggests
  keys for it. v0.2.0 documented and printed `send-keys down enter` for it.
  Folder trust is the only screen an agent may key through, and only on a
  pane it launched itself; `status` says so in its next step. Docs
  (`orchestra.md`, `SKILL.md`, README, `docs/SECURITY.md`) and tests follow.

## [0.2.0] - 2026-10-11

herdr-peers becomes the control plane of an orchestra: a lead agent sees
and diagnoses its lanes. Protocol stays **1** (no wire change; additive).
Also ships the fixes from the v0.1.0 Final Review and the public repository
standard.

### Added

- `herdr-peers status <machine>:<pane> [--json]`: a lane's state from Herdr
  (`working`, `idle`, `blocked`, `done`, `unknown`, `no_agent`,
  `unreachable`), its agent kind, and the class of a waiting screen read
  with `herdr pane read` — `folder_trust`, `bypass_ack`, `login`,
  `permission`, `unknown` — with the documented next step: the exact
  `herdr pane send-keys` for the two first-run screens (only under the
  user's standing authorization), escalation for everything else.
  Read-only: never sends keys, never prints screen text.
- `herdr-peers lanes [--json] [--all]`: one row per peer this pane asked —
  agent, vendor, profile, live state, screen class, open asks, last ask.
  `--json` is the frozen contract `herdr-peers/lanes-v1`
  (`docs/schema/lanes-v1.json`; consumers ignore unknown keys).
- `ask --vendor NAME`; the vendor is otherwise derived from the agent kind
  (claude → anthropic, codex → openai, …) and recorded as the optional
  `vendor` field of the delegation record. Profile, vendor, kind and task
  are repeated on every later record of an ask; `log` shows vendor and
  profile.
- `skills/herdr-peers/orchestra.md`: leading many lanes — the loop, states
  and screen classes, accounts and vendors with coding-agents-kit (`ak pick`,
  `ak usage`, `--trust-cwd`), lanes inside devcontainer-kit containers
  (`dck herdr mesh`, `[agents] host_profiles`), single-branch work,
  troubleshooting.
- Test scope `orchestra`; the fake `herdr` models `pane process-info`; the
  record validator understands arrays and validates one JSON document.
- `SHA256SUMS` also covers `docs/schema/`.

- Repository standard: `SECURITY.md` (supported versions, private
  reporting, response targets), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
  (Contributor Covenant 2.1), issue and pull-request templates, `CODEOWNERS`,
  Dependabot for GitHub Actions, and `CLAUDE.md` pointing to `AGENTS.md`.
- `scripts/check-public-hygiene.sh` with `.public-hygiene-allow`: fails on
  personal paths, private names, private addresses and credential shapes in
  tracked files; runs in CI as the `public hygiene` job.
- Release workflow: an annotated `vX.Y.Z` tag publishes a GitHub release
  with notes from this file and `SHA256SUMS` (`scripts/release-assets.sh`).
- Test scope `repo` (repository standard, hygiene check, release assets).

### Changed

- Documentation audit for the v7 ecosystem: the `ask` options (`--task`,
  `--worktree`, `--profile`, `--from`, `--scope`, `--fanout --reason`) are
  documented, the README gains a "Use with Deep Work Plan v7" subsection
  (the pack's `herdr` addon pins this repository), and the official-skill
  pin is tied to the Herdr binary version.
- Onboarded to Deep Work Plan 7.0.0 (`.dwp/config.json` registry, vendored
  `deepworkplan` and `ai-diff-reviewer` skills, `/dwp-*` delegators);
  benchmark and learnings enabled in the tracked config.
- README follows the ecosystem layout (what it is, install, quickstart,
  documentation, security, contributing, license).
- Environment-variable table in `SKILL.md` (and a pointer in the README);
  accurate log/reply locations with `HERDR_PEERS_LOG`; how the release
  `SHA256SUMS` is produced; exit code `6` also covers a missing `herdr` or
  `python3`; the self-address probe's assumption.

### Fixed

- `ask` and `reply` refuse a stale `HERDR_PANE_ID` (exit 6, nothing sent or
  recorded): the pane must exist on the local server and, when its
  foreground pids are visible, run an ancestor of the helper. Seen in the
  field: an agent with an inherited pane id sent `from=` an address that no
  longer existed, so the reply could not route.
- `log --open` honours `--id`.
- Test runner: the real Herdr context for the opt-in `live` scope is no
  longer exported to other scopes, survives paths with spaces, and the live
  listing is scoped to the local server.

### Security

- A reply recorded from a pane capture (`wait`) can no longer be replaced by
  a different reply: `check` reports a conflict and keeps the stored copy.
- `self.json` and `.gitignore` are written `0600` without following
  symlinks; an existing `.gitignore` is never touched; the `DWP_PLAN` mirror
  directory is created `0700`.
- `cancel` runs under the log lock.
- `HERDR_PEERS_MAX_BYTES` can lower the size limit, never raise it.

## [0.1.0] - 2026-10-08

First release. Interface version: **protocol 1** (`metadata.protocol: 1` in
`SKILL.md` and `protocol=1` in every stamp).

### Added

- `skills/herdr-peers/` — the skill: `SKILL.md` (strict triggers, depends on
  Herdr's official skill `herdrdev/herdr`), the normative `protocol.md`,
  `discipline.md`, `launcher.md`, and `templates/` (grant, ask, reply, and the
  `delegation-record.json` schema).
- Helper `herdr-peers` (bash entry + python3 standard library), shipped inside
  the skill (`scripts/`) with a `bin/` shim for checkouts. Verbs: `ask`,
  `reply`, `list`, `wait`, `log`, `check`, `cancel`; `--skill`, `--version`.
- Protocol 1: ask stamp + reply grant, reply stamp + clause, 13-rule loop
  guard, depth limit 1, fan-out cap 4 with a recorded override, scope
  allow-list (machine and workspace), reply routing that never sends `local`
  to another machine, exactly-once replies bound to the asking pane.
- Append-only delegation log (digests, never prompt text) with an optional
  mirror into `$DWP_PLAN/analysis_results/delegations.ndjson`.
- Security hardening and `docs/SECURITY.md` (threat model, residual risk).
- Test suite (`bash tests/run.sh`): sandboxed, fake `herdr`, scopes
  `harness lint protocol helper skill templates security live`; CI on Ubuntu
  and macOS.

[Unreleased]: https://github.com/DailybotHQ/herdr-peers/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/DailybotHQ/herdr-peers/compare/v1.3.1...v2.0.0
[1.3.1]: https://github.com/DailybotHQ/herdr-peers/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/DailybotHQ/herdr-peers/compare/v1.2.4...v1.3.0
[1.2.4]: https://github.com/DailybotHQ/herdr-peers/compare/v1.2.3...v1.2.4
[1.2.3]: https://github.com/DailybotHQ/herdr-peers/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/DailybotHQ/herdr-peers/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/DailybotHQ/herdr-peers/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/DailybotHQ/herdr-peers/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/DailybotHQ/herdr-peers/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/DailybotHQ/herdr-peers/compare/v0.3.3...v1.0.0
[0.3.3]: https://github.com/DailybotHQ/herdr-peers/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/DailybotHQ/herdr-peers/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/DailybotHQ/herdr-peers/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/DailybotHQ/herdr-peers/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/DailybotHQ/herdr-peers/releases/tag/v0.1.0
