# shellcheck shell=bash
# Scope `protocol`: every message fixture classifies as its filename prefix
# says (answer-/notice-/never-/none-), with the matching exit code, stamps
# built by the helper parse back to the same fields, and a frozen v0.2.3
# receiver decides never for every notice (compatibility).

new_world protocol
for f in "$FIXTURES"/messages/*.txt; do
  name=$(basename "$f")
  expected=${name%%-*}
  run "$HELPER" check --json --no-record "$f"
  got=$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["decision"])' 2>/dev/null)
  case $expected in
    answer) want_rc=0 ;;
    notice) want_rc=3 ;;
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
last_prompt local w1:p2 >"$WORK/received.txt"
run as_pane w1:p2 "$HELPER" check --json --no-record "$WORK/received.txt"
assert_contains "helper-built ask classifies as answer at the receiver" "$OUT" '"decision": "answer"'
assert_contains "receiver sees the sender address" "$OUT" '"from": "local:w1:p1"'
assert_contains "receiver sees the same id" "$OUT" "\"id\": \"$id\""

# Notices: a helper-built notice is a notice at the receiver, never answerable.
run "$HELPER" notify local:w1:p2 "Lane state changed."
nid=$OUT
last_prompt local w1:p2 >"$WORK/notice.txt"
run as_pane w1:p2 "$HELPER" check --json --no-record "$WORK/notice.txt"
assert_contains "helper-built notice classifies as notice at the receiver" "$OUT" '"decision": "notice"'
assert_eq "a notice exits 3 (never answer)" "3" "$RC"
assert_contains "receiver sees the notice id" "$OUT" "\"id\": \"$nid\""
run as_pane w1:p2 "$HELPER" reply --message "$WORK/notice.txt" local:w1:p1 "$nid" "ack"
assert_rc "reply --message refuses a notice (exit 3)" 3

# Compatibility: a v0.2.3 receiver decides never (rule 9) for every notice.
OLD="$ROOT/tests/compat/v0_2_3/herdr_peers.py"
assert_eq "the frozen v0.2.3 helper is unmodified" \
  "51a8a6eb5c039961f325fd9c9e0570c9a3984d658416f99c2d4b438813eb465a" \
  "$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$OLD")"
run python3 "$OLD" --version
assert_eq "the frozen helper is v0.2.3" "herdr-peers 0.2.3 (protocol 1)" "$OUT"
for f in "$FIXTURES"/messages/notice-*.txt "$WORK/notice.txt"; do
  run python3 "$OLD" check --json --no-record "$f"
  got=$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["decision"], d["rule"])' 2>/dev/null)
  if [ "$got" = "never 9" ] && [ "$RC" = 3 ]; then
    t_ok "v0.2.3 receiver: $(basename "$f") -> never (rule 9)"
  else
    t_fail "v0.2.3 receiver: $(basename "$f") -> never (rule 9)" "got $got exit $RC"
  fi
done
