# shellcheck shell=bash
# Scope `templates`: the templates exist, the delegation-record schema
# carries the plan-agnostic delegation fields, every record the helper writes
# in every state validates against it, and the message templates match what
# the helper actually sends.

TPL="$ROOT/skills/herdr-peers/templates"
SCHEMA="$TPL/delegation-record.json"
VALIDATE="$ROOT/tests/tools/validate_records.py"

for f in grant.md ask.md reply.md delegation-record.json; do
  check "template $f exists" test -s "$TPL/$f"
done

fields=$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(" ".join(sorted(s["required"])))' "$SCHEMA")
for k in task transport via kind profile target worktree prompt_digest state result_path; do
  assert_contains "schema requires delegation field $k" " $fields " " $k "
done
states=$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(",".join(s["properties"]["state"]["enum"]))' "$SCHEMA")
assert_eq "state enum is launched|completed|failed|cancelled" "launched,completed,failed,cancelled" "$states"

# Drive the helper through every record-writing path in one world.
new_world records
id=$("$HELPER" ask --task T-demo --profile work --worktree /wt/a local:w1:p2 "Template run")   # caller launched
pane_text local w1:p2 >"$WORK/ask.txt"
as_pane w1:p2 "$HELPER" check "$WORK/ask.txt" >/dev/null                                      # delegate launched
as_pane w1:p2 "$HELPER" reply local:w1:p1 "$id" "done" >/dev/null                              # delegate completed
pane_text local w1:p1 >"$WORK/reply.txt"
"$HELPER" check "$WORK/reply.txt" >/dev/null                                                   # caller completed (message)
id2=$("$HELPER" ask local:w1:p2 "second")
as_pane w1:p2 "$HELPER" reply local:w1:p1 "$id2" "two" >/dev/null
"$HELPER" wait "$id2" --timeout 2 >/dev/null 2>&1                                              # caller completed (pane-capture)
id3=$("$HELPER" ask --fanout 5 --reason "demo" local:w1:p2 "third")
"$HELPER" cancel "$id3" --reason "not needed" >/dev/null                                       # caller cancelled
FAKE_HERDR_FAIL="agent prompt" "$HELPER" ask local:w1:p2 "will fail" >/dev/null 2>&1          # caller failed
LOG="$WORK/.herdr-peers/log.ndjson"
seen=$(python3 -c 'import json,sys; print(" ".join(sorted({(json.loads(l)["role"]+":"+json.loads(l)["state"]) for l in open(sys.argv[1]) if l.strip()})))' "$LOG")
assert_eq "the run covers every role and state the helper writes" \
  "caller:cancelled caller:completed caller:failed caller:launched delegate:completed delegate:launched" "$seen"
run python3 "$VALIDATE" "$SCHEMA" "$LOG"
assert_rc "every helper log line validates against delegation-record.json" 0
assert_contains "the validator saw all lines" "$OUT" "valid 11"
assert_contains "task, profile and worktree are recorded" "$(head -1 "$LOG")" '"worktree": "/wt/a"'

# The validator is not vacuous.
head -1 "$LOG" | sed 's/"launched"/"running"/' >"$WORK/bad-state.ndjson"
run python3 "$VALIDATE" "$SCHEMA" "$WORK/bad-state.ndjson"
assert_rc "an unknown state is rejected" 1
head -1 "$LOG" | sed 's/^{/{"prompt": "leaked text", /' >"$WORK/extra.ndjson"
run python3 "$VALIDATE" "$SCHEMA" "$WORK/extra.ndjson"
assert_rc "an extra field (e.g. prompt text) is rejected" 1
head -1 "$LOG" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); d.pop("via"); print(json.dumps(d))' >"$WORK/missing.ndjson"
run python3 "$VALIDATE" "$SCHEMA" "$WORK/missing.ndjson"
assert_rc "a missing delegation field is rejected" 1

# The DWP_PLAN mirror carries the same shape.
mkdir -p "$WORK/plan"
DWP_PLAN="$WORK/plan" "$HELPER" ask local:w1:p2 "mirrored" >/dev/null
run python3 "$VALIDATE" "$SCHEMA" "$WORK/plan/analysis_results/delegations.ndjson"
assert_rc "mirrored plan records validate too" 0

# Message templates match the helper's real output.
grant=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import herdr_peers as h; print(h.GRANT_LINE)' "$ROOT/skills/herdr-peers/scripts")
clause=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import herdr_peers as h; print(h.REPLY_CLAUSE)' "$ROOT/skills/herdr-peers/scripts")
for f in grant.md ask.md; do
  assert_contains "$f carries the grant line verbatim" "$(cat "$TPL/$f")" "$grant"
  assert_contains "$f carries the ask stamp shape" "$(cat "$TPL/$f")" \
    "[herdr-peers] protocol=1 from=<machine_id>:<pane_id> reply=yes depth=0 id=<ulid>"
done
assert_contains "reply.md carries the reply clause verbatim" "$(cat "$TPL/reply.md")" "$clause"
assert_contains "reply.md carries the reply stamp shape" "$(cat "$TPL/reply.md")" \
  "[herdr-peers] protocol=1 reply-to=<ulid> depth=1"
real=$(sed -n '/^\[herdr-peers\]/p' "$WORK/ask.txt" | sed -E 's/from=[^ ]+/from=<machine_id>:<pane_id>/; s/id=[0-9A-Z]{26}$/id=<ulid>/')
assert_eq "a real ask stamp reduces to the template shape" \
  "[herdr-peers] protocol=1 from=<machine_id>:<pane_id> reply=yes depth=0 id=<ulid>" "$real"
