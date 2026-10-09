## Summary

<!-- What changes and why, in a few sentences. -->

## Linked issue

<!-- Closes #… (or "none"). -->

## Test evidence

<!-- Paste the last line of each run, e.g. `passed: N failed: 0 skipped: K`. -->

- `bash tests/run.sh`:
- `bash scripts/check-public-hygiene.sh`:

## Checklist

- [ ] Conventional commit title (`feat:`, `fix:`, `docs:`, …)
- [ ] Tests added or updated in the matching scope (docs/TESTING_GUIDE.md)
- [ ] Docs updated (SKILL.md, protocol.md, README, docs/) where behavior changed
- [ ] `CHANGELOG.md` `[Unreleased]` updated for user-visible changes
- [ ] Wire-format change: `protocol.md`, helper and `templates/` updated together, `metadata.protocol` bumped
- [ ] No secrets, tokens, personal paths or private context in the diff
