# AGENTS.md — herdr-peers

Entry point for AI agents working **on** this repository.

## Purpose

A standalone agent skill for [Herdr](https://herdr.dev): any coding agent can ask any other agent, in any pane on any machine, and get the answer back — with an explicit reply grant, a loop guard, depth 1, and a record of every delegation. It builds on Herdr's official skill and never re-teaches its CLI.

## Command / skill

herdr-peers (skill + helper script)

## Layout (target; built by the first plan)

skills/herdr-peers/ (SKILL.md, protocol.md, templates/), bin/herdr-peers (helper), tests/ (run.sh), docs/

## Validation

| Scope | Command |
| --- | --- |
| Full | `bash tests/run.sh` |
| Scoped | `bash tests/run.sh <scope>` |

The test map lives in [`docs/TESTING_GUIDE.md`](docs/TESTING_GUIDE.md).

## Rules

1. English for code, comments and docs; conventional commits.
2. Runtime code depends on bash and the python3 standard library only.
3. Never print, log or write the value of any `*_API_KEY` / `*_TOKEN` variable; refer to variables by name.
4. Never spell a fetch-piped-to-shell install line in a skill file (marketplace rule E005); never inject a permission-bypass flag by default (E006); pin every cross-repo install to a tag (W012).
5. Developing is not installing: tests run in a sandbox `HOME`; nothing is installed into the real `$HOME` while developing.
6. Pin every external tool by version.

## Deep Work Plans

Structured work runs through the installed `deepworkplan` skill (`.agents/skills/deepworkplan/`); plans live in the gitignored `.dwp/`.

DWP standard: 6.0.0 (onboarded 2026-10-08; skill 6.1.0)
