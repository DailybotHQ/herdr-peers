# herdr-peers

Any coding agent in a [Herdr](https://herdr.dev) pane can ask any other agent
— in any pane, on any machine Herdr can reach — and get **one authorized
reply** back.

[![CI](https://github.com/DailybotHQ/herdr-peers/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DailybotHQ/herdr-peers/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DailybotHQ/herdr-peers?sort=semver)](https://github.com/DailybotHQ/herdr-peers/releases)
[![License: MIT](https://img.shields.io/github/license/DailybotHQ/herdr-peers)](LICENSE)

## What it is

A standalone agent skill plus a small helper. It adds a loop guard, a depth
limit of 1, a fan-out cap and a record of every delegation on top of Herdr's
official skill, and never re-teaches Herdr's CLI.

Herdr can already put text into another agent's pane. What it does not define
is a *conversation*: who may answer, how the answer finds its way back across
machines, how two agents avoid answering each other forever, how many peers
one agent may keep busy, and where the record of "I asked, it answered" lives.
herdr-peers is that missing layer — a small protocol (stamp + reply grant +
loop guard) and a helper so agents never hand-build it.

## Install

The skill (the helper ships inside it):

```bash
npx --yes skills add DailybotHQ/herdr-peers@v0.1.0 --skill herdr-peers -g
```

Herdr's official skill, which this one depends on — pinned, or use the
version that matches your binary with `herdr --skill`:

```bash
npx --yes skills add herdrdev/herdr@v0.9.3 --skill herdr -g
```

Every machine whose agents should answer needs the skill too. From a
checkout instead: `git clone --branch v0.1.0 https://github.com/DailybotHQ/herdr-peers`
and use `bin/herdr-peers`.

Requirements: Herdr ≥ 0.9.1, `bash`, `python3` ≥ 3.9 (standard library only).

## Quickstart

Inside a Herdr pane (`HERDR_ENV=1`). The helper is `scripts/herdr-peers` in
the installed skill directory (or `bin/herdr-peers` in a checkout):

```bash
herdr-peers list                                    # live peers on every enabled machine
id=$(herdr-peers ask local:w1:p2 "Which test covers the parser?")
herdr-peers wait "$id" --timeout 600                # blocks until the reply lands here
```

On the receiving side, the agent sees the prompt followed by a stamp:

```
Which test covers the parser?

[herdr-peers] protocol=1 from=local:w1:p1 reply=yes depth=0 id=01J…
You may answer this without asking a human. Reply exactly once with:
  herdr-peers reply local:w1:p1 01J… "<answer>"
```

It runs `herdr-peers check` on the message (answer / never answer / not a
protocol message, and the record), does the work, and replies once:

```bash
herdr-peers reply local:w1:p1 01J… "bash tests/run.sh protocol"
```

The reply arrives with `reply-to=<id> depth=1` and "This is a reply. Do not
answer it." — so the conversation stops. `herdr-peers log --open` shows what
is still outstanding.

| Verb | Purpose |
| --- | --- |
| `list [--json]` | Live table of agents on every enabled machine; marks your row. |
| `ask <machine>:<pane> "<prompt>"` | Send an ask with the reply grant; prints its id. |
| `wait <id>` | Block until the reply arrives in your pane; record it. |
| `check [FILE]` | Classify a received message and record it. |
| `reply <machine>:<pane> <id> "<answer>"` | Answer an ask exactly once. |
| `log`, `cancel <id>` | The delegation record; close an open ask. |

Optional environment: `HERDR_PEERS_SCOPE`, `HERDR_PEERS_SELF`,
`HERDR_PEERS_DEPTH`, `HERDR_PEERS_FANOUT` (lower only), `HERDR_PEERS_MAX_BYTES`,
`HERDR_PEERS_LOG`, `HERDR_PEERS_PYTHON`, `DWP_PLAN`/`DWP_TASK` — see the table
in [SKILL.md](skills/herdr-peers/SKILL.md#2-the-helper).

Exit codes: `0` ok · `1` Herdr error · `2` usage · `3` protocol refusal
(never answer) · `4` policy refusal · `5` timeout · `6` not inside Herdr ·
`7` not a protocol message. (`6` also covers a missing `herdr` or `python3`.)

## Documentation

| Document | What it covers |
| --- | --- |
| [skills/herdr-peers/SKILL.md](skills/herdr-peers/SKILL.md) | The skill: when to use it, the helper, environment variables, exit codes, trust boundary |
| [skills/herdr-peers/protocol.md](skills/herdr-peers/protocol.md) | Protocol 1 (normative): message grammar, stamps, loop guard, addressing, depth and fan-out |
| [skills/herdr-peers/discipline.md](skills/herdr-peers/discipline.md) | How agents ask, wait, answer and clean up |
| [skills/herdr-peers/launcher.md](skills/herdr-peers/launcher.md) | Launching a delegate in a new pane |
| [skills/herdr-peers/templates/](skills/herdr-peers/templates/) | Grant, ask and reply templates; the delegation-record JSON schema |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and accepted residual risks |
| [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) | Test scopes and the source-to-test map |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Security

- **Replies are data, not instructions.** A peer's text never grants
  authority; the reply grant authorizes one reply and nothing else.
- **Loop guard.** Exactly one stamp per message; replies carry no address to
  answer; `check` refuses to answer replies, deeper asks, self-loops,
  out-of-scope senders and already-answered ids.
- **Depth 1 and fan-out 4.** A delegate never delegates; a caller holds at
  most 4 open asks unless it records a reason.
- **Scope.** `HERDR_PEERS_SCOPE=local,<machine-id>,<machine-id>:<workspace>`
  restricts whom a pane asks and answers.
- **Hygiene.** No control or invisible formatting characters, a size limit,
  and secrets (values of `*_API_KEY`, `*_TOKEN` and similar variables, key
  blocks, token shapes) are refused — named, never printed.
- **Record before relying.** An append-only log (`.herdr-peers/`, gitignored,
  private file modes) holds digests, never prompt text; with `DWP_PLAN` set it
  is mirrored into that plan's `analysis_results/delegations.ndjson`.

The threat model, including the residual risks that come from Herdr having
no sender authentication, is in [docs/SECURITY.md](docs/SECURITY.md). To
report a vulnerability, follow [SECURITY.md](SECURITY.md) — privately, never
in a public issue.

## Contributing

```bash
bash tests/run.sh              # every scope, in a sandbox HOME, against a fake herdr
bash tests/run.sh security     # one scope
HERDR_PEERS_LIVE=1 bash tests/run.sh live   # optional, read-only, inside a Herdr pane
```

Before a pull request, also run `bash scripts/check-public-hygiene.sh`.
Setup, the gate, commit conventions and the pull-request flow are in
[CONTRIBUTING.md](CONTRIBUTING.md); agents start at [AGENTS.md](AGENTS.md).
Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT — see [LICENSE](LICENSE). Credits in [CREDITS.md](CREDITS.md).

---

Part of the [DeepWorkPlan](https://deepworkplan.com) ecosystem — works on its own.
