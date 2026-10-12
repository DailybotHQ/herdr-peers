# Changelog

All notable changes to herdr-peers are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (0.x:
breaking changes bump the minor version and, when the wire format changes,
the protocol number).

## [Unreleased]

### Changed

- Development harness: the vendored `deepworkplan` skill is 7.6.1 (from the
  v7.6.1 tag, all 175 files checked against its SHA256SUMS), through the
  pack's addon planner; the AI Diff Reviewer skill stays at v3.3.9, the
  pack's pin. The shipped skill and helper are unchanged.

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

[Unreleased]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/DailybotHQ/herdr-peers/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/DailybotHQ/herdr-peers/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/DailybotHQ/herdr-peers/releases/tag/v0.1.0
