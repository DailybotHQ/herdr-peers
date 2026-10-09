# Skills and agents catalog — herdr-peers

## Skills (`.agents/skills/`, vendored and pinned in `skills-lock.json`)

| Skill | Version | Purpose |
| --- | --- | --- |
| `deepworkplan` | 7.0.0 | Deep Work Plans: create, execute, refine, resume, status, verify, upgrade |
| `ai-diff-reviewer` | 3.3.0 | Local review of the branch diff (configured by `.review/extension.md`) |

The product skill `skills/herdr-peers/` is what this repository ships; it is
not installed into `.agents/`.

## Agents (`.agents/agents/`)

| Agent | Purpose |
| --- | --- |
| `reviewer` | Protocol, hostile-input, hygiene, tests and docs review of a change |
| `security-auditor` | Audit against the threat model in `docs/SECURITY.md` |
| `executor` | Implement a scoped change with tests and the repository gate |
| `qa` | Reproduce bugs as tests; find missing coverage |

## Commands

See [COMMANDS_REFERENCE.md](COMMANDS_REFERENCE.md).
