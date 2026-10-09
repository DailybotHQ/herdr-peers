# Contributing to herdr-peers

Thanks for helping. herdr-peers is small on purpose: a protocol document, a
skill and one helper. Changes that keep it that way are the easiest to land.

## Development setup

You need `bash`, `git` and `python3` ≥ 3.9 (standard library only — there is
nothing to install). [`shellcheck`](https://github.com/koalaman/shellcheck)
v0.11.0 is optional locally; the `lint` scope skips honestly without it and CI
runs it pinned. Herdr itself is **not** needed: the tests drive a fake
`herdr` in a sandbox.

```bash
git clone https://github.com/DailybotHQ/herdr-peers
cd herdr-peers
bash tests/run.sh
```

## The gate

Run both before you open a pull request; CI runs the same commands on Ubuntu
and macOS:

```bash
bash tests/run.sh                        # full suite, sandboxed HOME, fake herdr
bash scripts/check-public-hygiene.sh     # nothing private or secret-shaped in tracked files
```

The last line of the suite is `passed: N failed: M skipped: K`; `M` must be
`0`. Scoped runs (`bash tests/run.sh <scope>`) and the map from source to
scopes are in [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md). A behavior
change comes with a test in the matching scope.

Rules that reviews enforce:

- Runtime code depends on `bash` and the `python3` standard library only.
- A change to the wire format updates `skills/herdr-peers/protocol.md`, the
  helper and `templates/` together, and bumps `metadata.protocol`.
- Never commit a real credential, a personal absolute path or private
  context. Secret-shaped test data must say it is fake and be listed in
  `.public-hygiene-allow` with a reason.
- Tests never touch the real `$HOME` or a real Herdr server (the `live` scope
  is opt-in and read-only).

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):
`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:` — for
example `fix(helper): refuse a reply to an unknown id`. Write in English. A
Developer Certificate of Origin sign-off is **not** required.

## Pull requests

1. Branch from `main` (`fix/…`, `feat/…`, `docs/…`).
2. Keep one change per pull request; fill in the template, including the
   test evidence.
3. CI (`test (ubuntu-latest)`, `test (macos-latest)`, `public hygiene`) must
   be green, and one maintainer review is required before merge.
4. User-visible changes add a line under `[Unreleased]` in
   [CHANGELOG.md](CHANGELOG.md).

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md), never a
public issue. Everyone taking part follows the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Working with AI agents

Coding agents working on this repository start at [AGENTS.md](AGENTS.md)
(`CLAUDE.md` points to it): layout, the gate and the rules above.
