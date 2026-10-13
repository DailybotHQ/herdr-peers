# Changelog

All notable changes to herdr-peers are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Since
1.0.0 a breaking change to the public interface bumps the major version, and
a wire-format change also bumps the protocol number (before 1.0.0, breaking
changes bumped the minor version).

## [Unreleased]

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

[Unreleased]: https://github.com/DailybotHQ/herdr-peers/compare/v1.0.0...HEAD
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
