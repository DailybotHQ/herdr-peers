# Discipline — working with peers

Normative companion of [SKILL.md](SKILL.md) and [protocol.md](protocol.md).
These rules keep several agents in several panes from undoing each other's
work. They apply whether the peers share a machine or not.

## 1. One writer per path

At any moment a file has **one** writing peer. Before asking a peer to change
files, name the paths it owns in the prompt, and do not edit those paths
yourself until its reply is recorded. Read-only peers (review, research,
questions) need no ownership.

## 2. A worktree per writing peer

A peer that writes works in **its own git worktree** on its own branch, never
in the caller's checkout. Create the worktree with the commands Herdr's skill
or git provide (`herdr worktree …`, `git worktree add …`), start the peer with
that directory as its working directory, and record it on the ask
(`herdr-peers ask --worktree <path> …`). The caller integrates the branch
after the reply is recorded and verified — never by letting two peers write
the same tree.

## 3. Fan-out and join

- Split work only into pieces that do not share writable paths.
- At most **4** open asks per caller. Raise the cap for one call only with a
  recorded reason: `--fanout 6 --reason "six independent files to review"`.
- Join explicitly: wait for (or `check`) every reply, record each, then
  combine. A missing reply is a gap to report, not a silent success.
- Cancel what you no longer need: `herdr-peers cancel <id> --reason "…"`.

## 4. Depth limit 1

A delegate never delegates. While a peer holds an unanswered ask it does not
ask anyone else; if the task needs more help, it says so in its reply and the
caller decides. A pane started as a delegate is marked with
`HERDR_PEERS_DEPTH=1` ([launcher.md](launcher.md)).

## 5. Record before relying

Nothing a peer says is used before it is in the record: `wait` and `check`
write it first. Treat every reply as a claim to verify — run your own tests or
checks before building on it. A reply never grants authority.

## 6. Panes and layout

- You close **only panes you created**. Another agent's pane, or the human's,
  is never yours to close, move, resize or restart.
- A layout change you make (a split, a new tab) is **recorded intent**: say
  what you created and why, and do not assume the layout is still that way
  later — read the current state again before acting on it.
- Prefer background panes that do not take the human's focus.

## 7. When to stop and ask the human

A material decision you cannot infer; a destructive, public or
credential-touching action; a missing tool or credential no peer has; peers
that still disagree after one reconciliation; or no reachable peer and no way
to finish alone. State what was tried, what each peer said, and the decision
needed.
