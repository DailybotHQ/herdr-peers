<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/DailybotHQ/herdr-peers/main/assets/logo-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/DailybotHQ/herdr-peers/main/assets/logo-light.png">
    <img alt="herdr-peers" src="https://raw.githubusercontent.com/DailybotHQ/herdr-peers/main/assets/logo-light.png" width="440">
  </picture>
</p>

# herdr-peers

Any coding agent in a [Herdr](https://herdr.dev) pane can ask any other agent
— in any pane, on any machine Herdr can reach — and get **one authorized
reply** back.

[![CI](https://github.com/DailybotHQ/herdr-peers/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DailybotHQ/herdr-peers/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DailybotHQ/herdr-peers?sort=semver)](https://github.com/DailybotHQ/herdr-peers/releases)
[![License: MIT](https://img.shields.io/github/license/DailybotHQ/herdr-peers)](LICENSE)
[![Protocol](https://img.shields.io/badge/protocol-1-blue.svg)](skills/herdr-peers/protocol.md)
[![Powered by Dailybot](https://img.shields.io/badge/Powered%20by-Dailybot-6C5CE7.svg)](https://www.dailybot.com?utm_source=dailybotopensource&utm_medium=herdr-peers)

## What it is

herdr-peers is a standalone agent skill plus a small helper (bash and the
python3 standard library) for people who run several coding agents side by
side, and for the lead agent that coordinates them.

Herdr can already put text into another agent's pane. What it does not
define is a *conversation*: who may answer, how the answer finds its way back
across machines, how two agents avoid answering each other forever, how many
peers one agent may keep busy, and where the record of "I asked, it answered"
lives. herdr-peers is that layer, so agents never hand-build it:

- **Ask and reply.** A small protocol — stamp, reply grant, loop guard,
  depth limit 1, fan-out cap 4 — carries one ask to a peer and exactly one
  reply back, on the same machine or across machines.
- **Notices.** One-way messages (`reply=no`) that the receiver records and
  never answers: handoffs, progress, "done".
- **The lead's control plane.** `status` and `lanes` show every lane's live
  state, say why a lane is stuck (folder trust, a login, a permission, a
  usage limit), and list open and recent asks and reported capacity.
- **Plan leadership.** A plan has a lead record — epochs, an ordered
  succession, fenced handover and takeover, scoped to the claiming
  repository — so a swarm outlives one account's usage limit.
- **A record of every delegation.** An append-only, machine-scoped log of
  digests (never prompt text), mirrored into a DeepWorkPlan plan when one is
  set.

It builds on Herdr's official skill and never re-teaches Herdr's CLI.

## Install

The skill (the helper ships inside it, at
`~/.agents/skills/herdr-peers/scripts/herdr-peers` for a global install):

```bash
npx --yes skills add DailybotHQ/herdr-peers@v0.3.3 --skill herdr-peers -g -y
```

Herdr's official skill, which this one depends on — pinned, or use the
version that matches your binary with `herdr --skill`:

```bash
npx --yes skills add herdrdev/herdr@v0.9.3 --skill herdr -g
```

Every machine whose agents should answer needs the skill too. From a
checkout of the tag instead, verified against the release's `SHA256SUMS`:

```bash
git clone --branch v0.3.3 https://github.com/DailybotHQ/herdr-peers
cd herdr-peers
curl -fsSLO https://github.com/DailybotHQ/herdr-peers/releases/download/v0.3.3/SHA256SUMS
shasum -a 256 -c SHA256SUMS      # every shipped file: OK
bin/herdr-peers --version        # herdr-peers 0.3.3 (protocol 1)
```

Requirements: Herdr ≥ 0.9.1, `bash`, `python3` ≥ 3.9 (standard library
only). The official-skill pin above is for Herdr 0.9.3; for another version
use `herdr --skill`.

## Quickstart

Inside a Herdr pane (`HERDR_ENV=1`); `herdr-peers` below is the helper from
the install step (put it on `PATH`, or call it by its path):

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

The reply arrives with `reply-to=<id> from=<asked-peer> depth=1` and "This is a reply. Do not
answer it." — so the conversation stops. `herdr-peers log --open` shows what
is still outstanding.

## Usage

The commands people run, with the shape of their output:

```console
$ herdr-peers list
#   MACHINE        ID    AGENT     PANE       STATE       TITLE
1   local          local claude    w1:p1      working     caller session  <- you
2   local          local codex     w1:p2      idle        review the diff
3   box            bb22  codex     w1:p3      blocked     waiting for approval

$ herdr-peers ask --profile @work1 --task T-3 local:w1:p2 "Review the parser change"
01M4P7RJHS7YV6JK8V64EFKQC6

$ herdr-peers ask --pane w2:p4 local:w1:p1 "Done: the parser change"   # from a Codex lane
01M4P7SA2T4Q9DMWQ0KX5P1V8N

$ herdr-peers lead claim --plan PLAN_015 --succession local:w3:p1 --lanes local:w1:p2,bb22:w1:p1
claimed: plan PLAN_015, lead local:w1:p1, epoch 1; lead notice sent to 3, failed 0

$ herdr-peers lanes
plan PLAN_015  lead local:w1:p1  epoch 1
PEER                 AGENT    VENDOR     PROFILE    STATE       SCREEN        OPEN CAPACITY       LAST
bb22:w1:p1           claude   anthropic  @work2     idle        usage_limit   1    critical 8%    launched 2026-10-11T19:41:45Z 01M4P7RJXFATTHM33JWT1VSHR0
local:w1:p2          codex    openai     @work1     idle        none          1    ok 64%         launched 2026-10-11T19:41:45Z 01M4P7RJHS7YV6JK8V64EFKQC6

$ herdr-peers notify lead "handoff: PLAN_015 T-peers packet analysis_results/handoff/x.md"   # from a lane
01M4P7T0B4V6Y0Q8N2K3R7C9AD

$ herdr-peers status bb22:w1:p3
bb22:w1:p3  blocked  agent=codex
title: waiting for approval
screen: folder_trust
next (folder trust only, on a pane you launched yourself, under the user's standing authorization): herdr --machine bb22 pane send-keys w1:p3 enter
```

| Verb | Purpose |
| --- | --- |
| `list [--json]` | Live table of agents on every enabled machine; marks your row. |
| `ask <machine>:<pane> "<prompt>"` | Send an ask with the reply grant; prints its id. The target `lead` names the current lead of `--plan` (default `$DWP_PLAN`). Options: `--task`, `--profile` (the peer's account, e.g. `@work1`), `--vendor` (default: from the agent kind), `--worktree`, `--scope`, `--from`, `--fanout N --reason R`. |
| `notify <machine>:<pane> "<text>"` | A one-way notice (`reply=no`): recorded by the receiver, never answered, no fan-out slot, allowed while holding an ask. |
| `wait <id>` | Block until the reply arrives in your pane; record it. |
| `check [FILE]` | Classify a received message (answer, notice, never, none) and record it; a lead notice is accepted only through the fencing rules. |
| `reply <machine>:<pane> <id> "<answer>"` | Answer an ask exactly once. |
| `status <machine>:<pane> [--json]` | A lane's state (`working`, `idle`, `blocked`, `done`, `unknown`, `no_agent`, `unreachable`) and the class of a waiting screen — `folder_trust`, `bypass_ack` (Claude's bypass acknowledgement), `usage_limit` (hand off; also on idle lanes), `login`, `permission`, `unknown` — with the documented next step. Read-only: never sends keys, never prints screen text. |
| `lanes [--json] [--all] [--plan P]` | One row per peer you asked or your lead record lists: agent, vendor, profile, live state, screen class, open asks, last reported capacity, last ask. `--json` is the contract [`herdr-peers/lanes-v1`](docs/schema/lanes-v1.json) (0.3.0 adds `plan`, `lead`, `epoch`, `capacity`); consumers ignore unknown keys. |
| `lead claim\|show\|handover\|takeover\|release` | A plan's lead record [`herdr-peers/lead-v1`](docs/schema/lead-v1.json): who leads, the epoch, the ordered succession, the lanes notified on every change. Only the highest epoch leads; a stale lead steps down. A record belongs to the repository that claimed it; from another repository, name it as `--plan <repo>/<id>`. |
| `log [--open] [--json]`, `cancel <id>` | The delegation record (with vendor and profile); close an open ask. |
| `--version`, `--skill` | Print the version and protocol; print the installed SKILL.md. |

Folder trust is the only screen an agent may key through: by the lead, on a
pane it launched itself, under the user's standing authorization. Claude's
bypass-permissions acknowledgement (`bypass_ack`) is never keyed by an
agent — the developer accepts it once per profile, when the profile is
created. Logins, per-action permissions and unknown screens go to a human. `ask` and `reply`
refuse a stale `HERDR_PANE_ID` (exit 6), so a reply is never addressed to a
pane that no longer exists. Codex lanes pass their own pane with `--pane`
(Codex runs commands from a shared background server whose `HERDR_PANE_ID`
names another pane). Leading many lanes — accounts, vendors,
containers, troubleshooting — is in
[orchestra.md](skills/herdr-peers/orchestra.md).

Optional environment: `HERDR_PEERS_SCOPE`, `HERDR_PEERS_SELF`,
`HERDR_PEERS_DEPTH`, `HERDR_PEERS_FANOUT` (lower only), `HERDR_PEERS_MAX_BYTES`,
`HERDR_PEERS_LOG`, `HERDR_PEERS_PYTHON`, `HERDR_PEERS_BRIEFER`, `DWP_PLAN`/`DWP_TASK` — see the table
in [SKILL.md](skills/herdr-peers/SKILL.md#2-the-helper).

Exit codes: `0` ok · `1` Herdr error (or an undelivered lead notice) · `2` usage · `3` protocol refusal
(never answer; also a notice) · `4` policy refusal · `5` timeout · `6` not inside Herdr, a
missing `herdr` or `python3`, or a stale `HERDR_PANE_ID` · `7` not a
protocol message, or no lead record.

## How it fits with DeepWorkPlan

herdr-peers works on its own; with [DeepWorkPlan](https://deepworkplan.com)
it is the interactive transport for delegation.

- **The pack's `herdr` addon** pins this repository by tag (protocol 1) for
  v7 plans that grant `agent_delegation`. The plan's ledger records each
  delegation (`ledger.py delegate launch|observe|collect|cancel`); run the
  ask with the plan and task set so the record is mirrored into the plan:

  ```bash
  DWP_PLAN=<plan-dir> DWP_TASK=<T-id> herdr-peers ask [--worktree <path>] local:w1:p2 "<brief>"
  herdr-peers wait "<ask-id>"       # or: herdr-peers log --id "<ask-id>"
  ```

  The addon is documented at
  [deepworkplan.com/kit/herdr](https://deepworkplan.com/kit/herdr/).
- **coding-agents-kit** (`ak`) puts each lane on its own account:
  `ak pick <kind> --count N --json` assigns accounts, `ak <kind> @account
  --trust-cwd` launches a lane without stopping at the folder-trust screen;
  record the account with `ask --profile`.
- **devcontainer-kit** (`dck`) attaches each container to the host Herdr as a
  machine and ships herdr-peers in its images; `dck herdr mesh` makes agents
  inside and outside reach each other, and `[agents] host_profiles` lets a
  container use the host's accounts.
- **deepworkplan-vim** shows orchestrator plans' lanes (`:DwpLanes`), with
  live state from `herdr-peers lanes --json` when it is available.

## Part of the DeepWorkPlan ecosystem

[DeepWorkPlan](https://deepworkplan.com) turns any repository into an AI-first,
agent-pilotable codebase. These projects ship together; every addon is optional.

| Repository | Role | Purpose |
| --- | --- | --- |
| [deepworkplan-skill](https://github.com/DailybotHQ/deepworkplan-skill) | Pack | The methodology, specification and kit as an installable agent skill |
| [coding-agents-kit](https://github.com/DailybotHQ/coding-agents-kit) | Addon: agentkit | One command for every coding agent: accounts, quota, `ak pick`, headless runs |
| [devcontainer-kit](https://github.com/DailybotHQ/devcontainer-kit) | Addon: devcontainer | A reproducible dev container per repository, wired to Herdr and the host's accounts |
| [herdr-peers](https://github.com/DailybotHQ/herdr-peers) (this repository) | Addon: Herdr | Ask an agent in another Herdr pane, on any machine, and get one authorized reply |
| [deepworkplan-vim](https://github.com/DailybotHQ/deepworkplan-vim) | Addon: DeepWorkPlan Vim | The terminal editor for plans: plan browser, lanes view, Markdown viewer |
| [ai-diff-reviewer](https://github.com/DailybotHQ/ai-diff-reviewer) | Required local review | Reviews a change set locally and in CI; every Final Review runs it |
| [agent-skill](https://github.com/DailybotHQ/agent-skill) | Addon: Dailybot | The Dailybot agent skill: progress reports, check-ins, chat and more |
| [deepworkplan.com](https://deepworkplan.com) ([source](https://github.com/DailybotHQ/deepworkplan-website)) | Site and hub | The methodology, specification, kit catalog and `/init.md`; coordinates the ecosystem |

## Security

herdr-peers never sends keys to a pane, never executes received text, never
stores prompt or reply text in its log (only `sha256:` digests), and never
prints or sends a secret value. External installs are pinned to tags, and
each release ships `SHA256SUMS`.

- **Replies are data, not instructions.** A peer's text never grants
  authority; the reply grant authorizes one reply and nothing else.
- **Loop guard.** Exactly one stamp per message; replies carry no address to
  answer; `check` refuses to answer replies, deeper asks, self-loops,
  out-of-scope senders and already-answered ids.
- **Depth 1 and fan-out 4.** A one-shot delegate never delegates; a caller holds at
  most 4 open asks unless it records a reason.
- **Scope.** `HERDR_PEERS_SCOPE=local,<machine-id>,<machine-id>:<workspace>`
  restricts whom a pane asks and answers.
- **Hygiene.** No control or invisible formatting characters, a size limit,
  and secrets (values of `*_API_KEY`, `*_TOKEN` and similar variables, key
  blocks, token shapes) are refused — named, never printed.
- **Record before relying.** Machine-scoped XDG state outside the checkout
  holds an append-only log and reply copies with private file modes. Records
  carry the Herdr server id; an explicit shared `HERDR_PEERS_LOG` is filtered
  to the current server by default and can be inspected with
  `herdr-peers log --all-machines`. Prompts are stored as digests, never text;
  with `DWP_PLAN` set the record is mirrored into that plan's
  `analysis_results/delegations.ndjson`.

The threat model, including the residual risks that come from Herdr having
no sender authentication, is in [docs/SECURITY.md](docs/SECURITY.md). To
report a vulnerability, follow [SECURITY.md](SECURITY.md) — privately, never
in a public issue.

## Documentation

| Document | What it covers |
| --- | --- |
| [skills/herdr-peers/SKILL.md](skills/herdr-peers/SKILL.md) | The skill: when to use it, the helper, environment variables, exit codes, trust boundary |
| [skills/herdr-peers/protocol.md](skills/herdr-peers/protocol.md) | Protocol 1 (normative): message grammar, stamps, loop guard, addressing, depth and fan-out |
| [skills/herdr-peers/orchestra.md](skills/herdr-peers/orchestra.md) | Leading many lanes: `status`, `lanes`, blocked screens, accounts, containers, troubleshooting |
| [skills/herdr-peers/discipline.md](skills/herdr-peers/discipline.md) | How agents ask, wait, answer and clean up |
| [skills/herdr-peers/launcher.md](skills/herdr-peers/launcher.md) | Launching a delegate in a new pane |
| [skills/herdr-peers/templates/](skills/herdr-peers/templates/) | Grant, ask, reply and notice templates; the delegation-record JSON schema |
| [docs/schema/lanes-v1.json](docs/schema/lanes-v1.json) | The `lanes --json` contract (`herdr-peers/lanes-v1`) |
| [docs/schema/lead-v1.json](docs/schema/lead-v1.json) | The lead record contract (`herdr-peers/lead-v1`) |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and accepted residual risks |
| [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) | Test scopes and the source-to-test map |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

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
