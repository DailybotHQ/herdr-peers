# Testing guide — herdr-peers

## Full validation command

```bash
bash tests/run.sh
```

Runs every scope in order. The last line is always
`passed: N failed: M skipped: K`; the exit status is non-zero when `M > 0`.
A `skip` is never a pass: it names what was unavailable and why.

## Scoped commands

`bash tests/run.sh <scope> [<scope>…]` runs selected scopes. An unknown scope
exits 2.

| Scope | What it proves | Source it covers |
| --- | --- | --- |
| `harness` | The sandbox is sealed (HOME, PATH, env) and the fake `herdr` models the real 0.9.x shapes (envelopes, error codes, `--machine`, unreachable/disabled machines, `wait-output`). | `tests/run.sh`, `tests/lib.sh`, `tests/fakes/herdr` |
| `protocol` | Every fixture in `tests/fixtures/messages/` classifies as its filename prefix says (`answer-`/`never-`/`none-`) with the matching exit code; helper-built asks parse back at the receiver. | `skills/herdr-peers/protocol.md` §4, `scripts/herdr_peers.py` (`check`, parser) |
| `helper` | Every verb against the fake: ask (stamp, grant, record before send, self/blocked/missing peers, stdin), reply routing (`--machine`, probed self id, `HERDR_PEERS_SELF`, no-route refusal), depth, fan-out cap and recorded override, cancel, scope, receive/reply exactly once, caller-side record-before-rely (recorded / already-recorded / conflict / unsolicited), self-loop and scope on receive, wait (round trip, timeout, unknown id), list, log, `DWP_PLAN` mirror, log location. | `skills/herdr-peers/scripts/`, `bin/herdr-peers` |
| `skill` | Frontmatter (name, `metadata.protocol: 1`, versions equal to the helper, `allowed-tools`, strict trigger description ≤ 1024 chars), pinned official-skill dependency, Trust boundary section, marketplace rules (no fetch-piped-to-shell, no bypass flag, pinned installs, no vendor or methodology names), relative links resolve, docs carry the helper's grant/clause verbatim, `--skill`, and a copy of only the skill directory works (install simulation). | `skills/herdr-peers/*.md`, `scripts/` |
| `templates` | The four templates exist; the delegation-record schema requires every plan-agnostic delegation field; a scripted run produces every role/state the helper writes (caller launched/completed/cancelled/failed, delegate launched/completed) and every line — and the `DWP_PLAN` mirror — validates (`tests/tools/validate_records.py`, stdlib); negative records are rejected; message templates match real helper output. | `skills/herdr-peers/templates/`, the helper's record writer |
| `security` | Hostile input end to end (threat model in `docs/SECURITY.md`): spoofed asks and forged/guessed replies, path-like ids, stamp smuggling, oversized messages, control/bidi/zero-width characters, option injection into the herdr argv, scope bypass (labels, case, local), fan-out env cannot raise the cap, secrets (variable values, token shapes, PEM) never sent/stored/echoed, terminal escapes from Herdr output, file modes and symlinked logs, malformed `depth`, newline tricks, `wait` capture validation, pane identity, hostile Herdr JSON, and concurrency (8 parallel asks → 4 open; 5 parallel replies → 1 sent). | the helper, `docs/SECURITY.md` |
| `repo` | The public repository standard: required root and `.github/` files, `CLAUDE.md` → `AGENTS.md`, README section order and footer; `scripts/check-public-hygiene.sh` passes on this repository and catches every rule on planted hits in a throwaway git repository (never printing the matched text), honours the public aliases, the vendored-pack exclusion and the allow-list rules (reason required, fake marker required, private names never allowed); `scripts/release-assets.sh` extracts one version's notes and a `SHA256SUMS` that `shasum -c` verifies. | `scripts/`, `.public-hygiene-allow`, root docs, `.github/` |
| `live` | **Opt-in** (`HERDR_PEERS_LIVE=1`, inside a Herdr pane): read-only checks against the real server — it answers, version ≥ 0.9.1, `herdr-peers list` parses the real JSON and marks exactly one row as you, a failed ask to a missing pane records nothing. Creates, changes and closes nothing; the listing is scoped to the local server (`--scope local`), so no saved machine is contacted. Without the opt-in or a server it reports `skip - live: unavailable (…)`. The two-pane round trip is not run live (it would create panes in the human's session); the fake covers it. | the helper against real Herdr |
| `lint` | `shellcheck` (pinned `v0.11.0` in CI) over every shell file, `bash -n`, python compilation, JSON validity. Skips honestly when `shellcheck` is not installed. | every `*.sh` (incl. `scripts/`), both helper entry points, every `*.py`, every `*.json` |

## Source-to-test map

When a change touches… run at least…

| Changed path | Scopes |
| --- | --- |
| `tests/run.sh`, `tests/lib.sh`, `tests/fakes/` | `harness lint`, then the full suite (every scope depends on them) |
| `skills/herdr-peers/protocol.md`, `tests/fixtures/messages/` | `protocol helper` |
| `skills/herdr-peers/SKILL.md`, `discipline.md`, `launcher.md` | `skill` |
| `skills/herdr-peers/templates/`, `tests/tools/` | `templates skill` |
| `skills/herdr-peers/scripts/`, `bin/herdr-peers` | `protocol helper lint`, then the full suite before a release |
| `docs/SECURITY.md` | `security` |
| `.github/workflows/ci.yml`, `release.yml` | `lint repo` locally; CI itself on push |
| `scripts/`, `.public-hygiene-allow`, root docs, `.github/` templates | `repo lint`, and `bash scripts/check-public-hygiene.sh` |
| a Herdr upgrade | `HERDR_PEERS_LIVE=1 bash tests/run.sh live` from a Herdr pane, then update `tests/fakes/herdr` if a shape changed |
| anything else | the full suite |

## Posture

- **Sandbox.** Each run creates `tmp/test-sandbox.XXXXXX/` (gitignored) and
  points `HOME`, `XDG_*` and the working directory into it. `PATH` is
  `tests/fakes`, a `python3` shim and the system directories only — the real
  `herdr` (often in `~/.local/bin`) is unreachable. Every `HERDR_*`, `DWP_*`,
  `*_API_KEY` and `*_TOKEN` variable is unset, so a run started inside a live
  Herdr pane cannot reach that server. `GIT_CEILING_DIRECTORIES` stops git
  discovery at the sandbox (it lives inside this repository's `tmp/`), and a
  run that leaves `.herdr-peers/` in the repository root fails. The sandbox is deleted on exit
  (`HERDR_PEERS_KEEP_SANDBOX=1` keeps it for debugging).
- **Fake failures.** `FAKE_HERDR_FAIL="<group> <verb>"` makes that fake
  command fail with a server error, for transport-failure paths.
- **No network, no installs.** Nothing is downloaded or installed by the
  suite; the fake `herdr` never opens a socket.
- **Python floor.** Runtime code targets python3 ≥ 3.9 (standard library
  only). Run the suite against a specific interpreter with
  `HERDR_PEERS_TEST_PYTHON=/path/to/python3 bash tests/run.sh`
  (e.g. `/usr/bin/python3`, 3.9 on macOS). CI runs 3.13. The v0.1.0 suite
  was run green on 3.9.6, 3.12.14 and 3.14 before release.
- **Bash floor.** Scripts stay bash 3.2 compatible (macOS `/bin/bash`): no
  associative arrays, no `mapfile`.
- **Live context.** Only when `HERDR_PEERS_LIVE=1` and the run starts inside
  a Herdr pane does the runner keep the real `HERDR_*` values and `herdr`
  path aside — in unexported shell variables that only the `live` scope passes
  on, so no other scope or child process inherits them (a `harness` check
  asserts this).
- **Output.** TAP-like: `ok N - …`, `not ok N - …` with `#` diagnostics,
  `skip - …`.

## CI

`.github/workflows/ci.yml` runs the full suite on `ubuntu-latest` and
`macos-latest` for pushes to `main`, tags and pull requests. Actions are
pinned by commit SHA; shellcheck is downloaded at a pinned version and
verified against its published SHA-256 before use.
