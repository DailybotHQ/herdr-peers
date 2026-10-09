# AGENTS.md — herdr-peers

Entry point for AI agents working **on** this repository.

## Purpose

A standalone agent skill for [Herdr](https://herdr.dev): any coding agent can ask any other agent, in any pane on any machine, and get the answer back — with an explicit reply grant, a loop guard, depth 1, and a record of every delegation. It builds on Herdr's official skill and never re-teaches its CLI.

## Command / skill

herdr-peers (skill + helper script)

## Layout

| Path | What |
| --- | --- |
| `skills/herdr-peers/` | The installable skill: `SKILL.md`, normative `protocol.md`, `discipline.md`, `launcher.md`, `templates/` (incl. `delegation-record.json` schema) |
| `skills/herdr-peers/scripts/` | The helper: `herdr-peers` (bash entry) + `herdr_peers.py` (python3 stdlib). It lives inside the skill so `npx skills add` installs it. |
| `bin/herdr-peers` | Checkout shim that runs the skill's helper |
| `tests/` | `run.sh` (sandboxed runner), `lib.sh`, `fakes/herdr`, `scopes/`, `fixtures/messages/`, `tools/` |
| `docs/` | `TESTING_GUIDE.md`, `SECURITY.md` (threat model) |
| `scripts/` | `check-public-hygiene.sh` (public-hygiene check; allow-list in `.public-hygiene-allow`), `release-assets.sh` (release notes + `SHA256SUMS`) |
| `.github/` | `workflows/ci.yml` (suite on Ubuntu + macOS, `public hygiene` job), `workflows/release.yml` (annotated tag → release), issue/PR templates, `CODEOWNERS`, `dependabot.yml` |
| Root | `README.md`, `CHANGELOG.md` (Keep a Changelog), `SECURITY.md` (policy), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CREDITS.md`, `LICENSE`; `CLAUDE.md` is a symlink to this file |

The protocol's interface version is `metadata.protocol` in `SKILL.md`; a wire
change bumps it (and the minor version while 0.x). Keep `protocol.md`, the
helper constants and `templates/` in step — the `skill` and `templates` test
scopes compare them.

## Validation

| Scope | Command |
| --- | --- |
| Full | `bash tests/run.sh` |
| Scoped | `bash tests/run.sh <scope>` |
| Public hygiene | `bash scripts/check-public-hygiene.sh` |

The test map lives in [`docs/TESTING_GUIDE.md`](docs/TESTING_GUIDE.md).

## Rules

1. English for code, comments and docs; conventional commits.
2. Runtime code depends on bash and the python3 standard library only.
3. Never print, log or write the value of any `*_API_KEY` / `*_TOKEN` variable; refer to variables by name.
4. Never spell a fetch-piped-to-shell install line in a skill file (marketplace rule E005); never inject a permission-bypass flag by default (E006); pin every cross-repo install to a tag (W012).
5. Developing is not installing: tests run in a sandbox `HOME`; nothing is installed into the real `$HOME` while developing.
6. Pin every external tool by version.
7. This repository is public: never commit personal absolute paths, private
   organization or repository names, internal hostnames, or real credentials.
   Secret-shaped test data says it is fake and is listed in
   `.public-hygiene-allow` with a reason. Never rewrite history; a leaked
   secret is rotated first.
8. Changes land through a pull request with green CI; releases come from an
   annotated `vX.Y.Z` tag (`.github/workflows/release.yml`).

## Deep Work Plans

Structured work runs through the installed `deepworkplan` skill (`.agents/skills/deepworkplan/`); plans live in the gitignored `.dwp/`.

DWP standard: 6.0.0 (onboarded 2026-10-08; skill 6.1.0)
