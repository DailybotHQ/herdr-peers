# Launcher — starting a new peer (optional)

Use this only when the human or the plan asks for a new peer. Asking an agent
that already runs in a pane needs no launch: use `herdr-peers list` and
`herdr-peers ask`. The `herdr` commands below are only named here; their
options and JSON shapes are defined by Herdr's official skill.

Every launch follows the same three steps:

1. **Create a pane you own** — `herdr pane split` next to yours, with the
   working directory the peer should use (its own worktree when it will
   write: [discipline.md](discipline.md) §2) and the delegate mark
   `HERDR_PEERS_DEPTH=1` in its environment. Read the new pane id from the
   JSON response.
2. **Start the agent** in that pane — `herdr agent start <name> --kind <kind>
   --pane <id>`. Use the kind the human asked for.
3. **Send the first ask** — the first message a fresh peer receives is its
   task: `herdr-peers ask local:<id> "<self-contained brief>"`.

Record what you created; close the pane only when you are done with it, and
only because you created it.

## With an agent profile launcher (`ak env`)

When the `ak` command (coding-agents-kit) is installed, it can prepare the
environment for a named profile of a CLI. `ak env <kind> @<profile>` prints
`KEY=VALUE` lines — variable names and paths, never secret values — and prints
nothing for the CLI's own home. Pass each line to the pane as one `--env`:

```bash
env_args=(--env HERDR_PEERS_DEPTH=1)
while IFS= read -r kv; do
  [ -n "$kv" ] && env_args+=(--env "$kv")
done < <(ak env claude @work)
pane=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus "${env_args[@]}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr agent start reviewer --kind claude --pane "$pane"
herdr-peers ask --profile work "local:$pane" "<brief>"
```

## Without `ak`

Start the agent with the CLI's own home — `herdr agent start <name> --kind
<kind> --pane <id>` — or, for a command that is not a recognized agent,
`herdr pane run <id> "<command>"`.

## Permissions

A launched peer runs with its CLI's **default permissions**. Never add a
permission-bypass or auto-approve flag on the peer's behalf; if the human
wants an autonomous peer, the human configures that explicitly (for example
through the profile launcher's own opt-in), and you record that they did.
