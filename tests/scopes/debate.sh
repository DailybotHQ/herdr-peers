# shellcheck shell=bash
# Scope `debate`: the debate lead's tools against the fakes — `tally`
# (Borda, first places, pairwise, Condorcet winner and loser, item verdicts,
# the lead never votes, hostile ballots), `anon` (seeded blind copies,
# redaction, a private key outside the panel's reach), `filings` (recover
# from disk) and `panel` (read-only seating: idle panes, busy panes skipped,
# accounts from a fake `ak pick`, nothing run).

DEBATE_TPL="$ROOT/skills/herdr-peers/templates/debate"
SCHEMAS="$ROOT/docs/schema"

# required_keys SCHEMA — the schema's required top-level keys, sorted.
required_keys() {
  python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["required"])))' "$1"
}
# json_keys — the top-level keys of the JSON on stdin, sorted.
json_keys() { python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin))))'; }
# jget EXPR — evaluate EXPR over the JSON on stdin as `d`.
jget() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }

new_world debate
B="$WORK/ballots.json"
cat >"$B" <<'JSON'
{"schema": "herdr-peers/ballots-v1", "options": ["A", "B", "C"], "items": ["V1", "V2"],
 "ballots": [
  {"voter": "w1:p2", "ranking": ["A", "B", "C"], "confidence": 70, "items": {"V1": "ACCEPT", "V2": "AMEND"}},
  {"voter": "w1:p3", "ranking": ["B", "A", "C"], "confidence": 80, "items": {"V1": "ACCEPT"}},
  {"voter": "w1:p4", "ranking": ["A", "C"], "confidence": 60, "items": {"V1": "REJECT", "V2": "AMEND"}},
  {"voter": "lead", "ranking": ["C", "B", "A"]}
 ]}
JSON

# --- tally ---
run "$HELPER" debate tally "$B"
assert_rc "tally counts a ballots-v1 file" 0
assert_contains "the lead's ballot is excluded and said so" "$OUT" "excluded: lead"
assert_contains "Borda: A earns 2+1+2 of 6" "$OUT" "A                            5/6       2        +2"
assert_contains "Condorcet winner is reported" "$OUT" "condorcet winner: A"
assert_contains "Condorcet loser is reported" "$OUT" "condorcet loser:  C"
assert_contains "a ranked option beats an unranked one (A vs C 3-0)" "$OUT" "A vs C: 3-0"
assert_contains "item verdicts are counted; a missing verdict is ABSTAIN" "$OUT" "V2           ABSTAIN 1 AMEND 2"
assert_contains "median confidence" "$OUT" "median confidence: 70"
run "$HELPER" debate tally --json "$B"
assert_eq "tally --json carries exactly tally-v1's required keys" \
  "$(required_keys "$SCHEMAS/tally-v1.json")" "$(printf '%s' "$OUT" | json_keys)"
assert_eq "tally --json ranks by Borda" "A,B,C" \
  "$(printf '%s' "$OUT" | jget '",".join(o["id"] for o in d["options"])')"
run "$HELPER" debate tally --exclude w1:p3 --json "$B"
assert_eq "--exclude leaves a voter out" "2 ['w1:p3', 'lead']" \
  "$(printf '%s' "$OUT" | jget '"%d %s" % (d["voters"], d["excluded"])')"
cat >"$WORK/cycle.json" <<'JSON'
{"schema": "herdr-peers/ballots-v1", "options": ["A", "B", "C"], "ballots": [
 {"voter": "x", "ranking": ["A", "B", "C"]}, {"voter": "y", "ranking": ["B", "C", "A"]},
 {"voter": "z", "ranking": ["C", "A", "B"]}]}
JSON
run "$HELPER" debate tally --json "$WORK/cycle.json"
assert_eq "a Condorcet cycle has no winner and no loser" "None None" \
  "$(printf '%s' "$OUT" | jget '"%s %s" % (d["condorcet_winner"], d["condorcet_loser"])')"
run "$HELPER" debate tally "$DEBATE_TPL/ballots.json"
assert_rc "the shipped ballots template tallies" 0
run "$HELPER" debate tally - <"$B"
assert_rc "tally reads stdin with -" 0

bad() { printf '%s' "$2" >"$WORK/bad.json"; run "$HELPER" debate tally "$WORK/bad.json"; assert_rc "$1" "${3:-2}"; }
bad "an unknown option in a ranking is refused" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"x","ranking":["Z"]}]}'
bad "a voter with two ballots is refused" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"x","ranking":["A"]},{"voter":"x","ranking":["A"]}]}'
bad "an option ranked twice is refused" \
  '{"schema":"herdr-peers/ballots-v1","options":["A","B"],"ballots":[{"voter":"x","ranking":["A","A"]}]}'
bad "a verdict that is not an uppercase word is refused" \
  '{"schema":"herdr-peers/ballots-v1","items":["V1"],"ballots":[{"voter":"x","items":{"V1":"accept; echo pwned"}}]}'
bad "a file without the ballots-v1 schema is refused" '{"options":["A"],"ballots":[]}'
bad "a ballots file of only the lead is refused" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"lead","ranking":["A"]}]}'
bad "a confidence outside 0-100 is refused" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"x","ranking":["A"],"confidence":101}]}'
bad "invalid JSON is refused" '{not json'
ln -s "$B" "$WORK/link.json"
run "$HELPER" debate tally "$WORK/link.json"
assert_rc "a symlinked ballots file is refused (policy)" 4

# --- anon ---
R1="$WORK/rounds/round1"
mkdir -p "$R1" "$WORK/private"
printf 'Filed by p2D (claude-opus) from local:w1:p4; see bb22:w3:p1 and w2:p9.\nGPT-5 and Grok agree. Acme is my team.\n' >"$R1/p2D.md"
printf 'p21 here, running codex.\nThe argument stands on its own.\n' >"$R1/p21.md"
printf 'no identity here\n' >"$R1/p2F.md"
printf 'not a filing\n' >"$R1/notes.txt"
run "$HELPER" debate anon "$R1" "$WORK/rounds/round1_anon" --key "$WORK/private/key.json" --seed 20261025 --redact Acme
assert_rc "anon writes blind copies" 0
anon_all=$(cat "$WORK"/rounds/round1_anon/*.md)
assert_eq "one Filing_<letter>.md per .md filing, nothing else" "Filing_A.md Filing_B.md Filing_C.md" \
  "$(cd "$WORK/rounds/round1_anon" && echo *)"
for leak in p2D p21 claude opus GPT-5 Grok codex w1:p4 bb22:w3:p1 w2:p9 Acme; do
  assert_not_contains "anon redacts $leak" "$anon_all" "$leak"
done
assert_contains "anon keeps the argument text" "$anon_all" "The argument stands on its own."
assert_contains "anon keeps a filing with no identity intact" "$anon_all" "no identity here"
assert_eq "the key file is private (0600)" "600" \
  "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$WORK/private/key.json")"
assert_eq "the key maps every filing back" "p21.md p2D.md p2F.md" \
  "$(jget '" ".join(sorted(d["map"].values()))' <"$WORK/private/key.json")"
map1=$(jget 'd["map"]' <"$WORK/private/key.json")
run "$HELPER" debate anon "$R1" "$WORK/again" --key "$WORK/private/key2.json" --seed 20261025
assert_eq "the same seed gives the same order" "$map1" "$(jget 'd["map"]' <"$WORK/private/key2.json")"
run "$HELPER" debate anon "$R1" "$WORK/third" --key "$WORK/third/key.json"
assert_rc "a key inside the panel's directory is refused" 4
run "$HELPER" debate anon "$R1" "$WORK/fourth" --key "$R1/key.json"
assert_rc "a key inside the filings directory is refused" 4
run "$HELPER" debate anon "$R1" "$WORK/rounds/round1_anon" --key "$WORK/private/key3.json"
assert_rc "a non-empty output directory is refused" 4
run "$HELPER" debate anon "$R1" "$WORK/fifth" --key "$WORK/private/key.json"
assert_rc "an existing key is never overwritten" 4
run "$HELPER" debate anon "$R1" "$R1/inner" --key "$WORK/private/key4.json"
assert_rc "an output directory inside the filings is refused" 4
check "a refused run leaves no output directory" test ! -e "$WORK/fifth"

# --- filings ---
run "$HELPER" debate filings "$R1" --expect p2D,p21,p2F
assert_rc "filings: every expected filing present exits 0" 0
assert_contains "filings says complete" "$OUT" "complete"
run "$HELPER" debate filings "$R1" --expect p2D,p21,p2X --min-words 12
assert_rc "filings: missing or short exits 5" 5
assert_contains "filings marks the missing one" "$OUT" "p2X.md                       missing"
assert_contains "filings marks a short one" "$OUT" "p21.md                       short"
assert_contains "filings lists only the panes to re-ask" "$OUT" "re-ask only p21.md, p2X.md"
run "$HELPER" debate filings --json "$R1" --expect p2D
assert_contains "filings --json names unexpected filings" "$OUT" '"unexpected": ['
run "$HELPER" debate filings "$R1" --expect ../etc/passwd
assert_rc "filings refuses a path as a name" 2

# --- panel ---
run "$HELPER" debate panel --seats 2 --no-ak --json
assert_rc "panel proposes a panel" 0
assert_eq "panel --json carries exactly panel-v1's required keys" \
  "$(required_keys "$SCHEMAS/panel-v1.json")" "$(printf '%s' "$OUT" | json_keys)"
assert_eq "panel reuses idle panes of this workspace only, never itself" "w1:p2" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"])')"
assert_eq "a Codex pane is cleared with /new and Enter" \
  "herdr agent prompt w1:p2 /new|herdr pane send-keys w1:p2 Enter" \
  "$(printf '%s' "$OUT" | jget '"|".join(d["reuse"][0]["reset"])')"
assert_eq "panel is never executed" "False" "$(printf '%s' "$OUT" | jget 'd["executed"]')"
run "$HELPER" debate panel --seats 3 --no-ak --all-workspaces --json
assert_eq "--all-workspaces reuses idle panes elsewhere too (Claude: /clear)" \
  "w2:p1=herdr agent prompt w2:p1 /clear" \
  "$(printf '%s' "$OUT" | jget '[s["pane"] + "=" + s["reset"][0] for s in d["reuse"] if s["kind"] == "claude"][0]')"
run "$HELPER" debate panel --seats 2 --exclude w1:p2 --no-ak
assert_contains "--exclude keeps a pane off the panel" "$OUT" "not reused (another plan's lead or lane, or --exclude): w1:p2"
run "$HELPER" debate panel --seats 3
assert_contains "without ak, panel says how to start agents" "$OUT" "agentkit (ak) is not installed"

# Another plan's lead and lanes are busy, even when idle.
as_pane w2:p1 "$HELPER" lead claim --plan other-plan --lanes local:w1:p2 >/dev/null 2>&1
run "$HELPER" debate panel --seats 2 --no-ak --all-workspaces --json
assert_eq "a pane in another plan's lead record is not reused" "" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"])')"

# With agentkit: accounts from ak pick, round-robin over kinds, nothing run.
new_world debate-ak
export FAKE_AK_DIR="$WORK/ak"
mkdir -p "$FAKE_AK_DIR"
echo '[{"profile":"@work1","headroom_pct":94,"verdict":"ok"},{"profile":"@work2","headroom_pct":40,"verdict":"ok"}]' >"$FAKE_AK_DIR/pick-claude.json"
echo '[{"profile":"@c1","headroom_pct":70,"verdict":"ok"}]' >"$FAKE_AK_DIR/pick-codex.json"
: >"$FAKE_HERDR_DIR/argv.log"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 4 --json
assert_rc "panel with ak proposes new seats" 0
assert_eq "one idle pane reused, then accounts round-robin over kinds" "w1:p2|claude@work1,codex@c1,claude@work2" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"]) + "|" + ",".join(s["kind"] + s["profile"] for s in d["new"])')"
assert_eq "the vendor mix is reported" "{'claude': 2, 'codex': 2}" "$(printf '%s' "$OUT" | jget 'd["mix"]')"
assert_contains "a kind with no account is noted" "$OUT" "ak pick grok: no account qualifies"
cmds=$(printf '%s' "$OUT" | jget '"\n".join(c for s in d["new"] for c in s["commands"] + [s["release"]])')
assert_contains "each new seat is leased to the lead" "$cmds" "ak lease claude @work1 --owner local:w1:p1 --ttl 12h --purpose debate"
assert_contains "each new pane knows its briefer" "$cmds" "--env HERDR_PEERS_BRIEFER=local:w1:p1"
assert_contains "each new seat launches on its account" "$cmds" 'herdr pane run <pane2> "ak codex @c1 --trust-cwd"'
assert_contains "each lease is released at close" "$cmds" "ak lease release claude @work2 --owner local:w1:p1"
assert_not_contains "no permission-bypass flag is proposed" "$cmds" "--auto"
assert_eq "only ak pick ran, with the lead as owner" "pick claude --count 3 --allow-unknown --json --owner local:w1:p1" \
  "$(head -1 "$FAKE_AK_DIR/argv.log")"
assert_eq "nothing but pick reached ak" "0" "$(grep -vc '^pick ' "$FAKE_AK_DIR/argv.log")"
assert_eq "panel sends, keys, splits and runs nothing in Herdr" "0" \
  "$(grep -cE 'prompt|send-keys|split|"run"|start' "$FAKE_HERDR_DIR/argv.log")"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 9
assert_contains "a panel larger than the accounts says what is unfilled" "$OUT" "left unfilled"
unset FAKE_AK_DIR

run "$HELPER" debate panel --seats 0
assert_rc "panel refuses zero seats" 2
run "$HELPER" debate panel --seats 2 --kinds 'claude;rm'
assert_rc "panel refuses a malformed kind" 2
run env -u HERDR_ENV "$HELPER" debate panel --seats 2
assert_rc "panel outside Herdr exits 6" 6
run "$HELPER" debate
assert_rc "debate without a sub-verb is a usage error" 2
