# herdr-peers

A standalone agent skill for [Herdr](https://herdr.dev): any coding agent can
ask any other agent — in any pane, on any machine Herdr can reach — and get
**one authorized reply** back, with a loop guard, a depth limit of 1, a
fan-out cap and a record of every delegation. It builds on Herdr's official
skill and never re-teaches its CLI.

Part of the [DeepWorkPlan](https://deepworkplan.com) ecosystem, and fully
usable without it.

## Why

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

Exit codes: `0` ok · `1` Herdr error · `2` usage · `3` protocol refusal
(never answer) · `4` policy refusal · `5` timeout · `6` not inside Herdr ·
`7` not a protocol message.

## How it stays safe

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

The full threat model, including the residual risks that come from Herdr
having no sender authentication, is in [docs/SECURITY.md](docs/SECURITY.md).
The normative protocol is
[skills/herdr-peers/protocol.md](skills/herdr-peers/protocol.md).

## Development

```bash
bash tests/run.sh              # every scope, in a sandbox HOME, against a fake herdr
bash tests/run.sh security     # one scope
HERDR_PEERS_LIVE=1 bash tests/run.sh live   # optional, read-only, inside a Herdr pane
```

See [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) and
[CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE). Credits in [CREDITS.md](CREDITS.md).
