---
name: executor
description: Implements a scoped herdr-peers change end to end — code, tests, docs — and validates it with the repository gate.
---

# Executor — herdr-peers

1. Read `AGENTS.md`, then the files the task names. For protocol work read
   `skills/herdr-peers/protocol.md` first; it is normative.
2. Make the smallest change that meets the task. Runtime code stays `bash` +
   `python3` (≥ 3.9) standard library; shell stays bash 3.2 compatible.
3. Add or update tests in the matching scope (`docs/TESTING_GUIDE.md`).
   Tests run in the sandbox `HOME` against `tests/fakes/herdr`; never the
   real `$HOME` or a real Herdr server.
4. Run `bash tests/run.sh <scope>` while iterating, then the full gate:
   `bash tests/run.sh` and `bash scripts/check-public-hygiene.sh`.
5. Update docs and `CHANGELOG.md` `[Unreleased]`; commit with a Conventional
   Commit message; open a pull request (CI and one review are required).

Inside a Deep Work Plan, follow the plan's task file and record gates through
the plan's ledger instead of ad-hoc claims.
