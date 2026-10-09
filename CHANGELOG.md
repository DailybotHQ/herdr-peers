# Changelog

All notable changes to herdr-peers. Versions follow semantic versioning
(0.x: breaking changes bump the minor version and, when the wire format
changes, the protocol number).

## [Unreleased]

Fixes from the v0.1.0 Final Review (on `main`; the `v0.1.0` tag is unchanged).

### Fixed

- A reply recorded from a pane capture (`wait`) can no longer be replaced by
  a different reply: `check` reports a conflict and keeps the stored copy.
- `self.json` and `.gitignore` are written `0600` without following
  symlinks; an existing `.gitignore` is never touched; the `DWP_PLAN` mirror
  directory is created `0700`.
- `cancel` runs under the log lock; `log --open` honours `--id`.
- `HERDR_PEERS_MAX_BYTES` can lower the size limit, never raise it.
- Test runner: the real Herdr context for the opt-in `live` scope is no
  longer exported to other scopes, survives paths with spaces, and the live
  listing is scoped to the local server.

### Documentation

- Environment-variable table in `SKILL.md` (and a pointer in the README);
  accurate log/reply locations with `HERDR_PEERS_LOG`; how the release
  `SHA256SUMS` is produced; exit code `6` also covers a missing `herdr` or
  `python3`; the self-address probe's assumption.

## [0.1.0] — 2026-10-08

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

[0.1.0]: https://github.com/DailybotHQ/herdr-peers/releases/tag/v0.1.0
