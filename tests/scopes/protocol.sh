# shellcheck shell=bash
# Scope `protocol`: every message fixture classifies as its filename prefix
# says (answer-/never-/none-), with the matching exit code, and stamps built
# by the helper parse back to the same fields.

new_world protocol
for f in "$FIXTURES"/messages/*.txt; do
  name=$(basename "$f")
  expected=${name%%-*}
  run "$HELPER" check --json --no-record "$f"
  got=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])' 2>/dev/null)
  case $expected in
    answer) want_rc=0 ;;
    none) want_rc=7 ;;
    *) want_rc=3; expected=never ;;
  esac
  if [ "$got" = "$expected" ] && [ "$RC" = "$want_rc" ]; then
    t_ok "fixture $name -> $expected (exit $want_rc)"
  else
    t_fail "fixture $name -> $expected (exit $want_rc)" "got decision=$got exit=$RC
$OUT
$ERR"
  fi
done

run "$HELPER" check --no-record "$FIXTURES/messages/answer-local-ask.txt"
assert_contains "human verdict names the exact reply command" "$OUT" \
  'herdr-peers reply local:w1:p2 01M4EZB9004TFF59TDWH9EDD1R "<answer>"'
run "$HELPER" check --no-record "$FIXTURES/messages/never-reply.txt"
assert_contains "human verdict for a reply says never answer" "$OUT" "NEVER ANSWER (rule 7)"

# Round trip: an ask built by the helper is an answerable stamp for the peer.
run "$HELPER" ask local:w1:p2 "What is the build status?"
id=$OUT
pane_text local w1:p2 >"$WORK/received.txt"
run as_pane w1:p2 "$HELPER" check --json --no-record "$WORK/received.txt"
assert_contains "helper-built ask classifies as answer at the receiver" "$OUT" '"decision": "answer"'
assert_contains "receiver sees the sender address" "$OUT" '"from": "local:w1:p1"'
assert_contains "receiver sees the same id" "$OUT" "\"id\": \"$id\""
