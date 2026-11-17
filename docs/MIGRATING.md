# Migrating from 1.x to 2.0.0

herdr-peers 2.0.0 is a major version because the protocol gained a second
number. For almost everyone the move is: install 2.0.0 on every machine,
restart the autopilot daemon if you run one, done. Nothing you rely on in 1.x
changes its behaviour.

## What is breaking, exactly

**Protocol 2 exists, and it is used by one message only**: the lead notice of
a plan whose lead record carries the *appointment grant* (`lead-v2`,
[protocol.md](../skills/herdr-peers/protocol.md) §10, §12).

| Message | 1.x | 2.0.0 |
| --- | --- | --- |
| Asks, replies, notices | `protocol=1` | `protocol=1`, byte-identical |
| Lead notices of a plan without the grant | `protocol=1` | `protocol=1`, byte-identical |
| Lead notices of a plan **with** the grant | — | `protocol=2` |

- A 2.0.0 receiver accepts both numbers. A `protocol=2` ask or reply does not
  exist and is decided **never** (rule 5).
- A 1.x receiver decides every `protocol=2` message **never** (rule 5). It
  keeps its old record of that plan and stays inert for it — it fails
  closed; it never adopts an appointment it cannot verify. This is tested
  against a frozen 1.3.0 receiver (`tests/compat/v1_3_0`).
- `herdr-peers --version` prints `(protocol 2)` and the skill's
  `metadata.protocol` is `2`: that number is the highest protocol the helper
  speaks.

So a mixed fleet behaves like this:

| Situation | What happens |
| --- | --- |
| No plan uses the grant | Nothing changes: 1.x and 2.0.0 peers talk protocol 1 as before |
| A plan uses the grant, every lane and successor runs 2.0.0 | Appointment works as documented |
| A plan uses the grant, a lane runs 1.x | That lane ignores the plan's lead notices until it is upgraded (it never adopts a wrong record); `lead claim --allow-appointment` warns you |

**Upgrade every machine before you grant appointment on a plan.** Granting is
opt-in per plan; until you grant it, a 2.0.0 fleet is wire-identical to 1.x.

## Install

On every machine whose agents ask or answer (the helper ships inside the
skill):

```bash
npx --yes skills add DailybotHQ/herdr-peers@v2.2.0 --skill herdr-peers -g -y
herdr-peers --version          # herdr-peers 2.2.0 (protocol 2)
```

From a checkout instead, verify the tag against the release's `SHA256SUMS`
(see the README). Machines that only *report* plans to the loop need nothing
but `python3`: the daemon sends them its own report module.

## What to restart

| Running | After the upgrade |
| --- | --- |
| Agents and their panes | Nothing: the helper is run per command |
| The autopilot daemon | `herdr-peers autopilot stop`, then `start` again with the same options (`autopilot status` shows them) so it runs the new code |
| Herdr | Nothing |

## What is new, and how to turn it on

Everything below is opt-in; 1.x options keep their meaning.

| Since | Command or option | What it adds |
| --- | --- | --- |
| 1.2.4 | `autopilot start\|stop\|status\|logs` (aliases `on`, `off`) | The daemon in the background, independent of the pane that started it |
| 1.3.0 | `autopilot --loop`, `--notify "<cmd>"`, `--notify-env NAME`; `plans`, `fleet`, `fleet ui` | Every open plan kept running to its end; the fleet map and its live watcher |
| 2.0.0 | `autopilot --loop --brain [--brain-kinds …] [--brain-model kind=model]` | A decision agent the daemon launches on your best account, asked only what its rules cannot decide |
| 2.0.0 | `lead claim --allow-appointment [--any-kind]` / `--no-appointment` | Your standing grant: a plan whose lead and successors are gone may continue under its first live lane |
| 2.0.0 | `lead takeover --as-lane` | The lane's own appointment (the daemon prompts it, with `--appoint`) |
| 2.0.0 | `autopilot --loop --appoint` | The daemon acts on the grant |
| 2.0.0 | `lead verify --plan P [--allow-unreached]` | Before a merge, tag or release: am I still the lead, here and on the plan's other machines? |
| 2.2.0 | `autopilot --loop --revive`; `lead takeover --reason revive` | A fresh agent carries an orphan plan on this machine (the daemon's one-time ticket); a stalled live lead is asked to hand over. Protocol stays 2: a `via: revive` record is never adopted by another machine, and a 2.0/2.1 receiver refuses it (fail closed) |

No flag was renamed or removed.

### Turn on lead appointment

1. Upgrade every machine of the plan.
2. As the plan's lead, on your word: `herdr-peers lead claim --plan P --allow-appointment`.
3. Run the daemon with it: `herdr-peers autopilot start --loop --appoint`.
4. Have leads run `herdr-peers lead verify --plan P` before any merge, tag or
   release (exit 4: not the lead; exit 5: a machine could not be reached).

The rules and the residual risk are in
[autopilot.md](../skills/herdr-peers/autopilot.md) §7 and
[protocol.md](../skills/herdr-peers/protocol.md) §12.

### Turn on the brain

1. Install coding-agents-kit 1.3.0 or later (`ak`) and add your accounts.
   `--brain` is fail-closed: with `ak` missing or older, the daemon refuses
   to start at all (start it without `--brain` to run without one).
2. Make sure the profile it will use does not default to a mode that skips
   approvals (auto, bypass, accept edits) — the daemon retires such a brain —
   and that its own settings do not pre-allow tools (Bash on an allowlist,
   say): those run without any dialog the daemon could see.
3. `herdr-peers autopilot start --loop --brain` (a Claude brain; since
   2.0.1 Claude is the only default kind, the only one whose answers are
   approved for now; `--brain-model claude=sonnet` for a model). Use
   coding-agents-kit 1.5.0 or later: an older kit starts a Claude profile
   whose default is auto mode in auto mode, and the daemon retires it.

What it may decide, and what it never does, is in
[autopilot.md](../skills/herdr-peers/autopilot.md) §6. Its answers carry an
HMAC under a per-launch key kept in memory and in one private `0600` file
whose path alone is in the brain's environment; a process of the same user
that reads that file could still forge an allowed (harmless) answer.

## New environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `HERDR_PEERS_AUTOPILOT_GRACE` | 300 | Seconds a lead's pane must stay unchanged before a loop prompt |
| `HERDR_PEERS_AUTOPILOT_SSH_TIMEOUT` | 25 | Seconds the loop waits for another machine's report |
| `HERDR_PEERS_AUTOPILOT_NOTIFY_TIMEOUT` | 20 | Seconds one `--notify` command may run |
| `HERDR_PEERS_AUTOPILOT_NOTIFY_BUDGET` | 20 | Seconds all `--notify` commands of one pass may run together |
| `HERDR_PEERS_AUTOPILOT_APPOINT_GRACE` | 900 | Seconds lead and successors must be gone, with the plan frozen, before an appointment |
| `HERDR_PEERS_APPOINT_PROBE_GAP` | 60 | Seconds between the appointee's two probes (0 is for tests only) |

## New contracts

`lead-v2` (`docs/schema/lead-v2.json`), `plans-v1` (`appoint`, `appointed`),
`fleet-v1`, `plan-event-v1` (`plan_appointment_prompted`, `plan_appointed`,
`needs_human`). Consumers ignore keys they do not know.
