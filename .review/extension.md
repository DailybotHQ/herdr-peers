# Review overrides for herdr-peers

herdr-peers is a public agent skill plus a helper (`bash` entry +
`python3` standard library, `skills/herdr-peers/scripts/herdr_peers.py`)
that lets one coding agent send text into another agent's terminal pane
through Herdr and accept exactly one reply. Herdr has no sender
authentication, so every message the helper receives is hostile input, and
every message it sends lands in another agent's context. The normative
rules are in `skills/herdr-peers/protocol.md`; the threat model (T1–T17)
is in `docs/SECURITY.md`; the rules for agents are in `AGENTS.md`.

## Severity overrides for this codebase

- **Always `critical`:** received message text (an ask, a reply, a pane
  title, a Herdr error string) reaching a shell, `eval`, `exec`, a format
  string that is executed, or the argv of anything except a literal
  `herdr` subcommand. `herdr()` / `herdr_json()` take argv lists; any
  `shell=True` or string-built command is a defect.
- **Always `critical`:** a change that lets the helper answer a reply, answer
  twice, answer an id this pane originated, or answer at depth ≥ 1 — the
  loop guard in `_classify()` and the exactly-once checks in `cmd_reply`
  (protocol §4, threats T2/T3/T8).
- **Always `critical`:** printing, logging, storing or sending the value of
  a `*_API_KEY` / `*_TOKEN` / `*_SECRET` / `*_PASSWORD` variable, or
  weakening `secret_finding()` / `check_outgoing()`. Refusals name the
  variable, never the value (T13).
- **Always `critical`:** a record, reply copy, `self.json` or `.gitignore`
  write that does not go through `write_private()` / `append_line()`
  (0600, `O_NOFOLLOW`, under the lock where the log is involved) (T15).
- **Always `critical`:** a tracked file that adds a personal absolute path,
  a private organization or repository name, an internal hostname, or a
  real credential — the repository is public (`scripts/check-public-hygiene.sh`).
- **Always `high`:** a wire-format change (stamp grammar, grant or reply
  clause, field names) without the same change in `protocol.md`,
  `templates/`, the helper constants and `metadata.protocol` in `SKILL.md`.
- **Always `high`:** a raise of the fan-out cap (`DEFAULT_FANOUT`), the size
  limit (`max_bytes()`) or the depth limit through the environment — the
  environment may lower them, never raise them (T4/T12).
- **Always `high`:** a string from Herdr or a peer printed to the terminal
  without `safe()` (escape sequences, C1 controls, bidi and zero-width
  characters — T10).
- **Always `high`:** a runtime dependency outside `bash` and the `python3`
  standard library, or Python syntax newer than 3.9.
- **Always `high`:** a skill file that spells a fetch-piped-to-shell install,
  a permission-bypass flag for launched agents, or an unpinned cross-repo
  install (`AGENTS.md` rule 4).

## Don't comment on

- Long single-file layout of `herdr_peers.py` — deliberate, so the skill
  installs as one directory with no package.
- Token-shaped strings in `tests/` that are assembled at runtime or listed in
  `.public-hygiene-allow` — they are planted test data.
- Files under `.agents/skills/` — vendored, pinned copies managed upstream.

## Repo-specific conventions

- Bash 3.2 compatibility for every shell file (macOS default); `shellcheck`
  v0.11.0 clean.
- Exit codes are a contract: 0 ok · 1 Herdr · 2 usage · 3 protocol refusal ·
  4 policy refusal · 5 timeout · 6 environment · 7 not a protocol message.
- Record before relying: the log line is written before a prompt is sent,
  and nothing is sent when the record cannot be written.
- Conventional commits; user-visible changes add a `CHANGELOG.md`
  `[Unreleased]` line.

## Test-strategy expectations

- Every behavior change comes with a test in the matching scope of
  `bash tests/run.sh` (`docs/TESTING_GUIDE.md` maps source to scopes);
  hostile-input fixes add a regression to the `security` scope.
- Tests run in the sandbox `HOME` against the fake `herdr`
  (`tests/fakes/herdr`); a test that reaches a real Herdr server, the
  network or the real `$HOME` is a defect.
