# Changelog

All notable changes to herdr-peers are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (0.x:
breaking changes bump the minor version and, when the wire format changes,
the protocol number).

## [Unreleased]

Fixes from the v0.1.0 Final Review and the public repository standard
(on `main`; the `v0.1.0` tag is unchanged).

### Added

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

- README follows the ecosystem layout (what it is, install, quickstart,
  documentation, security, contributing, license).
- Environment-variable table in `SKILL.md` (and a pointer in the README);
  accurate log/reply locations with `HERDR_PEERS_LOG`; how the release
  `SHA256SUMS` is produced; exit code `6` also covers a missing `herdr` or
  `python3`; the self-address probe's assumption.

### Fixed

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

[Unreleased]: https://github.com/DailybotHQ/herdr-peers/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DailybotHQ/herdr-peers/releases/tag/v0.1.0
