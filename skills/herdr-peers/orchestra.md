# Orchestrating lanes

How a **lead** agent runs several long-lived **lanes** — one agent per pane,
per repository or per task, on this machine, on other machines and inside
containers, on different vendors and accounts — with herdr-peers as the
control plane. The wire stays protocol 1: every exchange is still one ask
and one reply ([protocol.md](protocol.md)); this page adds the lead's view.

## 1. The lead's loop

1. **Launch** each lane in its own pane on the account it should spend
   (§3). Record the account with the ask: `--profile @work1` (and
   `--vendor` when the agent kind does not imply it).
2. **Delegate** with one self-contained ask per lane:
   `herdr-peers ask --profile @work1 local:w4:p1 "<task, files, acceptance>"`.
   At most 4 open asks (`--fanout N --reason` raises it, recorded).
3. **Watch** with `herdr-peers lanes` — one row per lane: agent, vendor,
   profile, live state, blocked-screen class, open asks, last ask. It reads
   the delegation log and Herdr; it never sends anything.
4. **Diagnose** a lane that is not moving with `herdr-peers status <addr>`.
5. **Collect** each reply with `herdr-peers check` (record before relying)
   and verify it like your own work: a lane's reply is a claim, not evidence.

Lanes ask the lead back the same way (a lane holding an ask cannot ask —
depth 1 — so a lane answers first, then asks). Keep coordination in asks and
replies, not in shared files.

## 2. Lane states and blocked screens

`herdr-peers status <machine>:<pane> [--json]` is **read-only**: it reads
`herdr agent get` and, for a lane that waits (`blocked`, `unknown`,
`no_agent`), the visible screen with `herdr pane read`. It never sends keys
and never prints screen text — only the class and the name of the pattern
that matched.

| State | Meaning |
| --- | --- |
| `working` | The agent is on a turn. |
| `idle` / `done` | Ready for input (`done`: a finished turn not yet seen). |
| `blocked` | Herdr recognized an approval or question UI. |
| `unknown` | An agent is present; Herdr cannot classify it. |
| `no_agent` | The pane runs no detected agent (a shell, or a CLI still at its first screen). |
| `unreachable` | Herdr could not answer for that pane or machine. |

| Screen class | What it is | Documented next step |
| --- | --- | --- |
| `folder_trust` | First run in a folder: "Do you trust the files in this folder?" (Claude), "Trust this folder?" / "Do you trust the contents of this directory?" (Codex) | **The only screen an agent may key through**, and only on a pane it launched itself, under the user's standing authorization: `herdr pane send-keys <pane> enter` (the default option accepts) |
| `bypass_ack` | Claude's one-time "Bypass Permissions mode" acknowledgement (default "No, exit") | **Escalate to the developer: accept once per profile; never keyed by an agent.** It is a one-time, per-profile developer step, done when the profile is created (§3). |
| `login` | Sign-in, API key or credential prompt | **Escalate.** A human signs in, or the lane restarts on a signed-in account. Never type credentials into a pane. |
| `permission` | A per-action approval ("Do you want to proceed?") | **Escalate** to the lane's human; a peer's ask never authorizes it. |
| `unknown` | Anything else | **Escalate**: read the screen, ask a human. |

For `folder_trust` only, `status` prints the exact command (with
`--machine` for a remote lane); for every other class, including
`bypass_ack`, it prints no keys. Keying through folder trust is a decision
of the lead, not of the helper: only when the user has granted it for
unattended lanes, only on a pane the lead launched itself, only for the
lane's own folder — then read the screen again (`status`) to confirm it
moved. Two failed attempts stop the lane. No agent ever sends keys for
Claude's bypass-permissions acknowledgement, and a permission opt-out the
user set (for example an "ask" mode) is never answered by the lead.

## 3. Lanes on several accounts and vendors

Each lane can run on its own account so the work spends several quotas, and
on its own vendor so lanes check each other. With **coding-agents-kit**
(`ak`, its own skill `agentkit` documents every command):

```bash
ak usage                         # every account's windows, read-only
ak pick claude --count 3 --json  # one account per lane, the most room first
ak claude @work1 --trust-cwd     # in the lane's pane: launch on that account, folder pre-trusted
```

`--trust-cwd` pre-trusts the launch folder in that account's own config, so
the lane does not stop at `folder_trust`. Claude's bypass-permissions
acknowledgement is the developer's own step: accept it once per profile,
when the profile is created; no agent keys it (§2). Use only your own accounts, within each vendor's terms; never
rotate accounts to get past a limit. Record the account with `--profile`:
`lanes` shows it, and `log` keeps it on every record of the ask.

## 4. Lanes inside containers

With **devcontainer-kit** (`dck`), the host Herdr attaches each container as
a machine, so a lane inside is addressed `<machine_id>:<pane>` like any
remote lane:

- `dck herdr mesh` (run by `dck up` unless `[herdr] mesh = false`) makes the
  host and the other dck containers reachable from inside, with the host's
  machine ids mirrored, so `from=` addresses route both ways. Agents inside
  reach the host through its opt-in loopback listener.
- With the host profile's `[agents] host_profiles = true`, the container uses
  the host's own agent accounts for the CLIs the repository lists — no login
  inside — so the lead can place a containerized lane on a chosen account.
  devcontainer-kit records Claude's bypass acknowledgement only in a
  container's own homes, never in the host profiles it shares (those also
  drive Claude on the host, where the developer accepts it once per
  profile).
- From a lane on another machine, set `HERDR_PEERS_SELF=<this machine's id as
  saved there>` (or pass `--from`) whenever the helper reports *no reply route*.

## 5. Single branch, single release

Lanes that write share one rule: one writer per path. When the user asks for
all the work of a repository on one branch, one lane owns that repository's
checkout and branch; other lanes do not write there. Ask that lane instead
([discipline.md](discipline.md)).

## 6. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `ask` / `reply` exit 6: *HERDR_PANE_ID … stale* or *names another session's pane* | The agent inherited a pane id that no longer names its pane (panes are renumbered when moved, restored or re-created, or the agent was started from another pane). A reply to that `from=` would not route (`agent_not_found`). Restart the agent from its own pane, or export the right `HERDR_PANE_ID` (`herdr-peers list` marks your row), then ask again. The check compares the pane's foreground processes with this process's ancestors; where those pids are not visible (another PID namespace) it accepts an existing pane. |
| `ask` exit 4: *blocked* | The lane waits at a screen: `herdr-peers status <addr>`. |
| `ask` exit 4: *no reply route* | Set `HERDR_PEERS_SELF` or `--from` (§4). |
| A lane shows `no_agent` with `folder_trust` | The CLI stopped at its first screen before Herdr detected it; see §2. |
| `lanes` shows `unreachable` | The machine or pane is gone; `herdr-peers list` shows what is live. |
