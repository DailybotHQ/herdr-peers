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
| `lint` | `shellcheck` (pinned `v0.11.0` in CI) over every shell file, `bash -n`, python compilation, JSON validity. Skips honestly when `shellcheck` is not installed. | every `*.sh`, both helper entry points, every `*.py`, every `*.json` |

## Source-to-test map

When a change touches… run at least…

| Changed path | Scopes |
| --- | --- |
| `tests/run.sh`, `tests/lib.sh`, `tests/fakes/` | `harness lint`, then the full suite (every scope depends on them) |
| `.github/workflows/ci.yml` | `lint` locally; CI itself on push |
| anything else | the full suite |

## Posture

- **Sandbox.** Each run creates `tmp/test-sandbox.XXXXXX/` (gitignored) and
  points `HOME`, `XDG_*` and the working directory into it. `PATH` is
  `tests/fakes`, a `python3` shim and the system directories only — the real
  `herdr` (often in `~/.local/bin`) is unreachable. Every `HERDR_*`, `DWP_*`,
  `*_API_KEY` and `*_TOKEN` variable is unset, so a run started inside a live
  Herdr pane cannot reach that server. The sandbox is deleted on exit
  (`HERDR_PEERS_KEEP_SANDBOX=1` keeps it for debugging).
- **No network, no installs.** Nothing is downloaded or installed by the
  suite; the fake `herdr` never opens a socket.
- **Python floor.** Runtime code targets python3 ≥ 3.9 (standard library
  only). Run the suite against a specific interpreter with
  `HERDR_PEERS_TEST_PYTHON=/path/to/python3 bash tests/run.sh`
  (e.g. `/usr/bin/python3`, 3.9 on macOS). CI runs 3.13.
- **Bash floor.** Scripts stay bash 3.2 compatible (macOS `/bin/bash`): no
  associative arrays, no `mapfile`.
- **Output.** TAP-like: `ok N - …`, `not ok N - …` with `#` diagnostics,
  `skip - …`.

## CI

`.github/workflows/ci.yml` runs the full suite on `ubuntu-latest` and
`macos-latest` for pushes to `main`, tags and pull requests. Actions are
pinned by commit SHA; shellcheck is downloaded at a pinned version and
verified against its published SHA-256 before use.
