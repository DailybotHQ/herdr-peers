# Changelog

All notable changes to herdr-peers are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Since
1.0.0 a breaking change to the public interface bumps the major version, and
a wire-format change also bumps the protocol number (before 1.0.0, breaking
changes bumped the minor version).

## [Unreleased]

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

[Unreleased]: https://github.com/DailybotHQ/herdr-peers/compare/v1.1.0...HEAD
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
