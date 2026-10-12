# Frozen v0.2.3 helper (test fixture)

`herdr_peers.py` is the v0.2.3 helper byte for byte (`git show
v0.2.3:skills/herdr-peers/scripts/herdr_peers.py`). The `protocol` scope runs
its `check` on every notice fixture to prove that a receiver which predates
notices decides **never** (rule 9: no grant). It is a fixture, never imported by
the shipped skill; its digest is pinned in `tests/scopes/protocol.sh`. CI
checkouts are shallow, so the old helper cannot come from git history.
