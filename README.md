# herdr-peers

A standalone agent skill for [Herdr](https://herdr.dev): any coding agent can ask any other agent, in any pane on any machine, and get the answer back — with an explicit reply grant, a loop guard, depth 1, and a record of every delegation. It builds on Herdr's official skill and never re-teaches its CLI.

> **Status: pre-release.** Part of the [DeepWorkPlan](https://deepworkplan.com) ecosystem, and fully usable without it.

## Install

```bash
npx --yes skills add DailybotHQ/herdr-peers@v0.1.0 --skill herdr-peers -g   # available from v0.1.0
```

## Usage

Inside a Herdr pane (`HERDR_ENV=1`), with the skill installed, the helper is
`scripts/herdr-peers` in the skill directory (or `bin/herdr-peers` in a
checkout):

```bash
herdr-peers list                                   # live peers on every enabled machine
id=$(herdr-peers ask local:w1:p2 "Which test covers the parser?")
herdr-peers wait "$id" --timeout 600               # blocks until the reply lands here
herdr-peers check < received.txt                   # receiver: may I answer this?
herdr-peers reply local:w1:p1 <id> "bash tests/run.sh protocol"
herdr-peers log --open                             # the delegation record
```

Exit codes: `0` ok · `1` Herdr error · `2` usage · `3` protocol refusal
(never answer) · `4` policy refusal · `5` timeout · `6` not inside Herdr ·
`7` not a protocol message. The protocol is
[`skills/herdr-peers/protocol.md`](skills/herdr-peers/protocol.md).

## License

MIT — see [LICENSE](LICENSE). Credits in [CREDITS.md](CREDITS.md).
