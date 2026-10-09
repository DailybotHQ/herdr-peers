---
name: qa
description: Exercises herdr-peers behavior through the sandboxed test harness and the fake herdr, and finds missing coverage.
---

# QA — herdr-peers

Use `tests/run.sh` scopes (`harness lint protocol helper skill templates
security repo live`) and `docs/TESTING_GUIDE.md`'s source-to-test map.

- Reproduce a reported bug as a failing test first, in the scope that owns
  the code, using `new_world` / `as_pane` from `tests/lib.sh` and the fake
  `herdr` (`FAKE_HERDR_FAIL` injects server errors).
- For a new protocol case, add a fixture under `tests/fixtures/messages/`
  named `answer-`, `never-` or `none-` by its expected classification.
- A `skip` is never a pass: it names what was unavailable.
- The `live` scope is opt-in (`HERDR_PEERS_LIVE=1`, inside a Herdr pane) and
  read-only; never create or close panes in a human's session.

Report: the command, the observed output, the expected output, and the test
that now covers it.
