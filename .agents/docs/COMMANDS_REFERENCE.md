# Commands reference — herdr-peers

Invoke a command as `/<name>` in Claude Code, `#<name>` in agents that
intercept slash syntax (Codex, Cursor), or in plain text ("run `<name>`") on
hosts without slash commands. Each file in `.agents/commands/` is a thin
delegator: it routes to a sub-skill of the vendored `deepworkplan` skill
(`.agents/skills/deepworkplan/`), which owns the flow.

| Command | Procedure file | Routes to |
| --- | --- | --- |
| `dwp-create` | `.agents/commands/dwp-create.md` | `deepworkplan` create |
| `dwp-execute` | `.agents/commands/dwp-execute.md` | `deepworkplan` execute |
| `dwp-refine` | `.agents/commands/dwp-refine.md` | `deepworkplan` refine |
| `dwp-resume` | `.agents/commands/dwp-resume.md` | `deepworkplan` resume |
| `dwp-status` | `.agents/commands/dwp-status.md` | `deepworkplan` status |
| `dwp-verify` | `.agents/commands/dwp-verify.md` | `deepworkplan` verify (read-only) |
| `dwp-upgrade` | `.agents/commands/dwp-upgrade.md` | `deepworkplan` upgrade |
| `skill-create` | `.agents/commands/skill-create.md` | `deepworkplan` author |
| `agent-create` | `.agents/commands/agent-create.md` | `deepworkplan` author |

The vendored `ai-diff-reviewer` skill is invoked directly
(`/ai-diff-reviewer`) for a local review of the branch diff.
