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
bad "a ranking entry that is not a string is refused cleanly (no crash)" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"x","ranking":[{}]}]}'
assert_not_contains "no traceback for a hostile ranking" "$ERR" "Traceback"
bad "one voter in two cases is one voter" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"W1:P2","ranking":["A"]},{"voter":"w1:p2","ranking":["A"]}]}'
bad "local:w1:p2 and w1:p2 are one voter" \
  '{"schema":"herdr-peers/ballots-v1","options":["A"],"ballots":[{"voter":"local:w1:p2","ranking":["A"]},{"voter":"w1:p2","ranking":["A"]}]}'
printf '%s' '{"schema":"herdr-peers/ballots-v1","options":["A","B"],"ballots":[{"voter":"x","ranking":["A"]},{"voter":"LEAD","ranking":["B"]}]}' >"$WORK/lead.json"
run "$HELPER" debate tally "$WORK/lead.json"
assert_contains "the lead is left out in any case" "$OUT" "excluded: LEAD"
run "$HELPER" debate tally --exclude X "$WORK/lead.json"
assert_rc "--exclude matches voters in any case (X leaves x out)" 2
ln -s "$B" "$WORK/link.json"
run "$HELPER" debate tally "$WORK/link.json"
assert_rc "a symlinked ballots file is refused (policy)" 4
# Per-pane ballot files: each pane files one ballot; the lead tallies the directory.
BD="$WORK/ballots_r1"
mkdir -p "$BD"
for v in w1:p2 w1:p3; do
  printf '{"schema":"herdr-peers/ballots-v1","options":["A","B"],"ballots":[{"voter":"%s","ranking":["B","A"]}]}' "$v" \
    >"$BD/$(printf '%s' "$v" | tr ':' '-').ballot.json"
done
run "$HELPER" debate tally --json "$BD"
assert_eq "tally assembles a directory of per-pane *.ballot.json files" "2 B" \
  "$(printf '%s' "$OUT" | jget '"%d %s" % (d["voters"], d["condorcet_winner"])')"
printf '{"schema":"herdr-peers/ballots-v1","options":["A","C"],"ballots":[{"voter":"w1:p4","ranking":["A"]}]}' >"$BD/w1-p4.ballot.json"
run "$HELPER" debate tally "$BD"
assert_rc "ballot files with other options are refused" 2
run "$HELPER" debate tally --pane w1:p1 "$B"
assert_rc "every debate verb takes --pane (Codex passes it on every call)" 0
run "$HELPER" debate claims --pane 'w1;p1' "$DEBATE_TPL/claims.json"
assert_rc "a malformed --pane is refused" 2

# --- anon ---
R1="$WORK/rounds/round1"
mkdir -p "$R1" "$WORK/private"
printf 'Filed by p2D (claude-opus) from local:w1:p4 on @work1; see bb22:w3:p1 and w2:p9.\nGPT-5, o3-mini, Gemini and Google agree. Acme is my team. Mail ops@example.com.\n' >"$R1/p2D.md"
printf 'p21 here, running codex.\nThe argument stands on its own.\n' >"$R1/p21.md"
printf 'no identity here\n' >"$R1/p2F.md"
printf 'not a filing\n' >"$R1/notes.txt"
run "$HELPER" debate anon "$R1" "$WORK/rounds/round1_anon" --key "$WORK/private/key.json" --seed 20261025 --redact Acme
assert_rc "anon writes blind copies" 0
anon_all=$(cat "$WORK"/rounds/round1_anon/*.md)
assert_eq "one Filing_<letter>.md per .md filing, nothing else" "Filing_A.md Filing_B.md Filing_C.md" \
  "$(cd "$WORK/rounds/round1_anon" && echo *)"
assert_not_contains "anon never prints the order's secret" "$OUT" "20261025"
for leak in p2D p21 claude opus GPT-5 o3-mini Grok codex w1:p4 bb22:w3:p1 w2:p9 Acme @work1 Google; do
  assert_not_contains "anon redacts $leak" "$anon_all" "$leak"
done
assert_contains "anon keeps the argument text" "$anon_all" "The argument stands on its own."
assert_contains "anon keeps a filing with no identity intact" "$anon_all" "no identity here"
assert_contains "anon keeps an e-mail address (not a profile handle)" "$anon_all" "ops@example.com"
assert_eq "the key file is private (0600)" "600" \
  "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$WORK/private/key.json")"
assert_eq "the key maps every filing back" "p21.md p2D.md p2F.md" \
  "$(jget '" ".join(sorted(d["map"].values()))' <"$WORK/private/key.json")"
map1=$(jget 'd["map"]' <"$WORK/private/key.json")
run "$HELPER" debate anon "$R1" "$WORK/again" --key "$WORK/private/key2.json" --seed 20261025
assert_eq "the same seed gives the same order" "$map1" "$(jget 'd["map"]' <"$WORK/private/key2.json")"
run "$HELPER" debate anon --json "$R1" "$WORK/blind-json" --key "$WORK/private/key-json.json"
assert_not_contains "anon --json carries no seed or secret" "$OUT" '"seed"'
secret=$(jget 'd["seed"]' <"$WORK/private/key-json.json")
check "without --seed the order's secret is a random 128-bit value, only in the key" \
  python3 -c 'import re,sys; sys.exit(not re.fullmatch("[0-9a-f]{32}", sys.argv[1]))' "$secret"
# A seed seen by the panel plus the public filing names must not rebuild the
# map: the 1.1.0 draft shuffled the sorted names with random.Random(seed).
R8="$WORK/rounds/eight"
mkdir -p "$R8"
for n in a1 b2 c3 d4 e5 f6 g7 h8; do printf 'filing %s\n' "$n" >"$R8/$n.md"; done
"$HELPER" debate anon "$R8" "$WORK/eight-out" --key "$WORK/private/key8.json" --seed 20261025 >/dev/null
assert_eq "the order is not the seeded shuffle of the filing names" "differs" \
  "$(python3 -c 'import json,random,sys; o=sorted(n + ".md" for n in sys.argv[2:]); random.Random("20261025").shuffle(o); m=json.load(open(sys.argv[1]))["map"]; print("same" if [m["Filing_%s" % c] for c in "ABCDEFGH"] == o else "differs")' "$WORK/private/key8.json" a1 b2 c3 d4 e5 f6 g7 h8)"
S1="$WORK/rounds/secret"
mkdir -p "$S1"
printf 'my key is %s\n' "sk-ant-$(printf 'x%.0s' $(seq 1 30))" >"$S1/p31.md"
run "$HELPER" debate anon "$S1" "$WORK/secret-out" --key "$WORK/private/key-secret.json"
assert_rc "a filing carrying a secret-shaped value is refused" 4
assert_contains "the refusal names the kind of secret, never the value" "$ERR" "an Anthropic key"
assert_not_contains "the value is never echoed" "$ERR" "xxxxxxxxxx"
check "a refused secret writes nothing (no output, no key)" test ! -e "$WORK/secret-out" -a ! -e "$WORK/private/key-secret.json"
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
assert_contains "without ak, panel recommends coding-agents-kit" "$OUT" "recommended: coding-agents-kit"
run "$HELPER" debate panel --seats 1
assert_contains "without ak, a filled panel still recommends coding-agents-kit" "$OUT" "recommended: coding-agents-kit"
run "$HELPER" debate panel --seats 1 --no-ak --json
assert_eq "without known quota the first seat still succeeds, with a note" "local:w1:p2" \
  "$(printf '%s' "$OUT" | jget '",".join(d["succession"])')"
assert_contains "the unknown-quota successor is noted" "$OUT" "successor(s) without known quota"

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
assert_eq "seats alternate providers; the 70% codex account goes before the codex pane of unknown quota" "w1:p2|claude@work1,codex@c1,claude@work2" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"]) + "|" + ",".join(s["kind"] + s["profile"] for s in d["new"])')"
assert_eq "the kind mix is reported" "{'claude': 2, 'codex': 2}" "$(printf '%s' "$OUT" | jget 'd["mix"]')"
assert_eq "the provider mix is reported" "{'anthropic': 2, 'openai': 2}" "$(printf '%s' "$OUT" | jget 'd["providers"]')"
assert_eq "two providers are not a diverse panel" "False" "$(printf '%s' "$OUT" | jget 'd["diverse"]')"
assert_contains "low diversity is noted" "$OUT" "low provider diversity (2 provider(s)"
assert_contains "a kind with no account is noted" "$OUT" "ak pick grok: no account qualifies"
cmds=$(printf '%s' "$OUT" | jget '"\n".join(c for s in d["new"] for c in s["commands"] + [s["release"]])')
assert_contains "each new seat is leased to the lead" "$cmds" "ak lease claude @work1 --owner local:w1:p1 --ttl 12h --purpose debate"
assert_contains "each new pane knows its briefer" "$cmds" "--env HERDR_PEERS_BRIEFER=local:w1:p1"
assert_contains "each new seat launches on its account" "$cmds" 'herdr pane run <pane2> "ak codex @c1 --trust-cwd"'
assert_contains "each lease is released at close" "$cmds" "ak lease release claude @work2 --owner local:w1:p1"
assert_not_contains "no permission-bypass flag is proposed" "$cmds" "--auto"
assert_eq "only ak pick ran, with the lead as owner" "pick claude --count 4 --allow-unknown --json --owner local:w1:p1" \
  "$(head -1 "$FAKE_AK_DIR/argv.log")"
assert_eq "nothing but pick reached ak" "0" "$(grep -vc '^pick ' "$FAKE_AK_DIR/argv.log")"
assert_eq "panel sends, keys, splits and runs nothing in Herdr" "0" \
  "$(grep -cE 'prompt|send-keys|split|"run"|start' "$FAKE_HERDR_DIR/argv.log")"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 9
assert_contains "a panel larger than the accounts says what is unfilled" "$OUT" "left unfilled"
echo '[{"profile":"@g1","headroom_pct":null,"verdict":"unknown"}]' >"$FAKE_AK_DIR/pick-grok.json"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --json
assert_eq "with a third provider available, 3 seats take one of each" "{'anthropic': 1, 'openai': 1, 'xai': 1} True" \
  "$(printf '%s' "$OUT" | jget '"%s %s" % (d["providers"], d["diverse"])')"
assert_eq "most quota first: an account with known headroom beats an idle pane of unknown quota" "|codex@c1" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"]) + "|" + ",".join(s["kind"] + s["profile"] for s in d["new"] if s["provider"] == "openai")')"
echo '[{"profile":"@x1","headroom_pct":50,"verdict":"ok"}]' >"$FAKE_AK_DIR/pick-codex-xai.json"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --kinds claude,codex-xai --json
assert_eq "an agentkit provider kind counts as its provider (codex-xai is xai)" "{'anthropic': 1, 'openai': 1, 'xai': 1}" \
  "$(printf '%s' "$OUT" | jget 'd["providers"]')"
assert_eq "successors are the two seats with the most known quota, most first" "local:<pane1>,local:<pane2>" \
  "$(env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --json | jget '",".join(d["succession"])')"
echo '[{"profile":"@work1","headroom_pct":50,"verdict":"ok"}]' >"$FAKE_AK_DIR/pick-claude.json"
assert_eq "on a headroom tie a provider other than the lead's succeeds first" "local:<pane2>,local:<pane1>" \
  "$(env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --kinds claude,codex-xai --json | jget '",".join(d["succession"])')"
echo '[{"profile":"@work1","headroom_pct":94,"verdict":"ok"},{"profile":"@work2","headroom_pct":40,"verdict":"ok"}]' >"$FAKE_AK_DIR/pick-claude.json"

# Reported capacity ranks reused panes: low goes after new accounts, critical is never seated.
report_capacity() { # report_capacity LINE — w1:p2 replies to an ask with a capacity line
  local id
  id=$("$HELPER" ask local:w1:p2 "status?")
  last_prompt local w1:p2 >"$WORK/cap-ask.txt"
  as_pane w1:p2 "$HELPER" check "$WORK/cap-ask.txt" >/dev/null
  as_pane w1:p2 "$HELPER" reply local:w1:p1 "$id" "$(printf 'done\n%s' "$1")" >/dev/null
  last_prompt local w1:p1 >"$WORK/cap-reply.txt"
  "$HELPER" check "$WORK/cap-reply.txt" >/dev/null
}
echo '[{"profile":"@c1","headroom_pct":95,"verdict":"ok"}]' >"$FAKE_AK_DIR/pick-codex.json"
report_capacity "capacity=ok 5% @c9"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --json
assert_eq "most quota first: a 95% account is seated before an idle pane at 5%" "|codex@c1" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"]) + "|" + ",".join(s["kind"] + s["profile"] for s in d["new"] if s["provider"] == "openai")')"
report_capacity "capacity=ok 95% @c9"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --json
assert_eq "on a headroom tie the idle pane is reused (no new pane or lease)" "w1:p2|" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"]) + "|" + ",".join(s["kind"] + s["profile"] for s in d["new"] if s["provider"] == "openai")')"
report_capacity "capacity=low 20% @c9"
run env PATH="$ROOT/tests/fakes/agentkit:$PATH" "$HELPER" debate panel --seats 3 --json
assert_eq "a low-capacity idle pane yields to a new account of its provider" "|codex@c1" \
  "$(printf '%s' "$OUT" | jget '",".join(s["pane"] for s in d["reuse"]) + "|" + ",".join(s["kind"] + s["profile"] for s in d["new"] if s["provider"] == "openai")')"
run "$HELPER" debate panel --seats 1 --no-ak --json
assert_eq "without another account, the low pane is still seated, with its capacity" "w1:p2 low 20" \
  "$(printf '%s' "$OUT" | jget '"%s %s %s" % (d["reuse"][0]["pane"], d["reuse"][0]["capacity"]["verdict"], d["reuse"][0]["capacity"]["headroom_pct"])')"
report_capacity "capacity=critical 4% @c9"
run "$HELPER" debate panel --seats 2 --no-ak
assert_contains "a critical pane is never seated" "$OUT" "not seated (reported critical capacity): w1:p2"
# After a handover the new lead (w2:p1) still sees each lane's last capacity
# line, though the reply reached the old lead (w1:p1).
as_pane w2:p1 "$HELPER" lead claim --plan cap-plan --lanes local:w1:p2 >/dev/null 2>&1
run as_pane w2:p1 "$HELPER" lanes --plan cap-plan --json
assert_contains "lanes shows a lane's capacity reported to another pane of this server" "$OUT" '"verdict": "critical"'
unset FAKE_AK_DIR

run "$HELPER" debate panel --seats 0
assert_rc "panel refuses zero seats" 2
run "$HELPER" debate panel --seats 2 --kinds 'claude;rm'
assert_rc "panel refuses a malformed kind" 2
run env -u HERDR_ENV "$HELPER" debate panel --seats 2
assert_rc "panel outside Herdr exits 6" 6
run "$HELPER" debate
assert_rc "debate without a sub-verb is a usage error" 2

# --- claims ---
new_world debate-claims
CL="$WORK/round2"
mkdir -p "$CL"
ledger() { # ledger LANE VENDOR CLAIMS_JSON
  printf '{"schema":"herdr-peers/claims-v1","lane":"%s","angle":"angle-%s","vendor":"%s","claims":%s}\n' \
    "$1" "$1" "$2" "$3" >"$CL/$1.claims.json"
}
F1='{"key":"est","text":"Established claim","evidence":"FACT","confidence":90,"sources":["https://a.example/x (2026-10-20)"]}'
ledger p1 anthropic "[$F1,
 {\"key\":\"agr\",\"text\":\"Agreed, weakly sourced\",\"evidence\":\"INFERENCE\"},
 {\"key\":\"con\",\"text\":\"Contested claim\",\"evidence\":\"FACT\",\"sources\":[\"s1\"]},
 {\"key\":\"one\",\"text\":\"Only p1 says this\",\"evidence\":\"FACT\",\"sources\":[\"s2\"]},
 {\"key\":\"ref\",\"stance\":\"disputes\",\"text\":\"Wrong\",\"evidence\":\"FACT\",\"sources\":[\"s4\"]},
 {\"key\":\"opn\",\"stance\":\"disputes\",\"text\":\"I doubt it\",\"evidence\":\"OPEN\",\"confidence\":80},
 {\"key\":\"uns\",\"stance\":\"disputes\",\"text\":\"Doubtful\"}]"
ledger p2 openai '[{"key":"EST","text":"Same, another source","evidence":"FACT","confidence":70,"sources":["https://B.example/y (2026-10-21)"]},
 {"key":"agr-synonym","text":"Agreed too","evidence":"OPEN"},
 {"key":"con","stance":"disputes","text":"No","evidence":"FACT","sources":["s3"]},
 {"key":"ref","stance":"disputes","text":"Also wrong","evidence":"FACT","sources":["s5"]},
 {"key":"opn","stance":"disputes","text":"p1 at local:w1:p4 on @work1 (anthropic, angle-p1) doubts it too","evidence":"OPEN","confidence":60}]'
ledger p3 xai '[{"key":"est","text":"Same source as p1","evidence":"INFERENCE","sources":["https://a.example/x/ (2026-10-20)"]}]'
echo '{"agr-synonym":"agr"}' >"$WORK/keymap.json"
run "$HELPER" debate claims "$CL" --map "$WORK/keymap.json" --json
assert_rc "claims merges a directory of ledgers" 0
status_of() { printf '%s' "$OUT" | jget "{c['key']: c['status'] for c in d['claims']}.get('$1')"; }
assert_eq "established: 2+ lanes, a sourced FACT, 2 distinct sources" "established" "$(status_of est)"
assert_eq "keys match case-insensitively; sources de-duplicate (case, trailing slash)" "3 2" \
  "$(printf '%s' "$OUT" | jget '[("%d %d" % (len(c["supporters"]), c["distinct_sources"])) for c in d["claims"] if c["key"] == "est"][0]')"
assert_eq "agreed: enough lanes, evidence bar not met (--map merged the synonym)" "agreed" "$(status_of agr)"
assert_eq "contested: supported and disputed" "contested" "$(status_of con)"
assert_eq "single: one lane, no dispute" "single" "$(status_of one)"
assert_eq "refuted: disputed by 2+ lanes, none supports, a sourced FACT, 2 distinct sources" "refuted" "$(status_of ref)"
assert_eq "disputed: 2+ OPEN, sourceless disputes are never refuted" "disputed" "$(status_of opn)"
assert_eq "disputers' sources, FACTs and confidence are reported on their own" "0 0 70" \
  "$(printf '%s' "$OUT" | jget '[("%d %d %s" % (c["dispute_sources"], c["dispute_fact_backed"], c["dispute_median_confidence"])) for c in d["claims"] if c["key"] == "opn"][0]')"
assert_contains "the report says statuses are a quorum, not verification" "$(printf '%s' "$OUT" | jget 'd["basis"]')" "quorum, not verification"
assert_eq "unsupported: disputed by fewer than --min-lanes" "unsupported" "$(status_of uns)"
assert_eq "the synonym key no longer appears" "None" "$(status_of agr-synonym)"
assert_eq "claims --json carries exactly claims-report-v1's required keys" \
  "$(required_keys "$SCHEMAS/claims-report-v1.json")" "$(printf '%s' "$OUT" | json_keys)"
assert_eq "claims are ordered established first" "est,agr,con,one,uns,opn,ref" \
  "$(printf '%s' "$OUT" | jget '",".join(c["key"] for c in d["claims"])')"
assert_eq "coverage lists what only one lane raised" "['one']" \
  "$(printf '%s' "$OUT" | jget '[c["unique"] for c in d["coverage"] if c["lane"] == "p1"][0]')"
assert_eq "vendors of supporters are reported" "['anthropic', 'openai', 'xai']" \
  "$(printf '%s' "$OUT" | jget '[c["vendors"] for c in d["claims"] if c["key"] == "est"][0]')"
run "$HELPER" debate claims "$CL" --map "$WORK/keymap.json" --min-lanes 3 --json
assert_eq "--min-lanes 3: two supporting lanes are partial, not agreed" "partial" "$(status_of agr)"
run "$HELPER" debate claims "$CL" --map "$WORK/keymap.json"
assert_contains "the table names the next round's work" "$OUT" "next round: verify or cross-examine"
run "$HELPER" debate claims "$CL" --anonymous --seed 7 --json
blind1=$OUT
assert_not_contains "--anonymous hides lane ids" "$blind1" '"p1"'
assert_not_contains "--anonymous drops vendors" "$blind1" "anthropic"
assert_contains "--anonymous names lanes Lane_A..." "$blind1" '"Lane_A"'
for leak in angle-p1 local:w1:p4 @work1 anthropic; do
  assert_not_contains "--anonymous redacts $leak from angles, claim text and sources" "$blind1" "$leak"
done
assert_contains "--anonymous replaces each angle with Angle_A..." "$blind1" '"angle": "Angle_'
run "$HELPER" debate claims "$CL" --anonymous --seed 7 --json
assert_eq "--anonymous with a seed repeats" "$blind1" "$OUT"
run "$HELPER" debate claims "$DEBATE_TPL/claims.json"
assert_rc "the shipped claims template merges" 0

badc() { mkdir -p "$WORK/bad" && rm -f "$WORK"/bad/*; printf '%s' "$2" >"$WORK/bad/x.claims.json"
  run "$HELPER" debate claims "$WORK/bad"; assert_rc "$1" "${3:-2}"; }
badc "a ledger without the claims-v1 schema is refused" '{"lane":"x","claims":[]}'
badc "a bad stance is refused" '{"schema":"herdr-peers/claims-v1","lane":"x","claims":[{"key":"k","stance":"maybe"}]}'
badc "a bad evidence level is refused" '{"schema":"herdr-peers/claims-v1","lane":"x","claims":[{"key":"k","evidence":"VIBES"}]}'
badc "a key twice in one ledger is refused" '{"schema":"herdr-peers/claims-v1","lane":"x","claims":[{"key":"k"},{"key":"K"}]}'
badc "a confidence outside 0-100 is refused" '{"schema":"herdr-peers/claims-v1","lane":"x","claims":[{"key":"k","confidence":-1}]}'
badc "a path-like key is refused" '{"schema":"herdr-peers/claims-v1","lane":"x","claims":[{"key":"../k"}]}'
long=$(python3 -c 'print("x" * 501)')
badc "text over 500 characters is refused" "{\"schema\":\"herdr-peers/claims-v1\",\"lane\":\"x\",\"claims\":[{\"key\":\"k\",\"text\":\"$long\"}]}"
badc "more than 20 sources are refused" "{\"schema\":\"herdr-peers/claims-v1\",\"lane\":\"x\",\"claims\":[{\"key\":\"k\",\"sources\":$(python3 -c 'import json; print(json.dumps(["s"] * 21))')}]}"
cp "$CL/p1.claims.json" "$WORK/dup.claims.json"
run "$HELPER" debate claims "$CL" "$WORK/dup.claims.json"
assert_rc "two ledgers for one lane are refused" 2
assert_contains "the refusal points at --rounds" "$ERR" "--rounds"
sed 's/"lane":"p1"/"lane":"local:P1"/' "$CL/p1.claims.json" >"$WORK/dup2.claims.json"
run "$HELPER" debate claims "$CL" "$WORK/dup2.claims.json"
assert_rc "local:P1 and p1 are one lane (case and local: prefix)" 2
# Rounds: a round-2 ledger that judges only some claims keeps the lane's round-1 rest.
mkdir -p "$WORK/r1" "$WORK/r2"
lg() { printf '{"schema":"herdr-peers/claims-v1","lane":"%s","claims":%s}\n' "$2" "$3" >"$WORK/$1/$2.claims.json"; }
lg r1 local:w1:p1 '[{"key":"x"},{"key":"y"}]'
lg r1 w1:p2 '[{"key":"x"},{"key":"z"}]'
lg r2 w1:p1 '[{"key":"z"}]'
lg r2 w1:p2 '[{"key":"y","stance":"disputes"}]'
run "$HELPER" debate claims --rounds "$WORK/r1" "$WORK/r2" --json
assert_rc "claims --rounds merges rounds in order" 0
assert_eq "round-1 consensus survives; a later dispute makes a claim contested" "x=agreed y=contested z=agreed" \
  "$(printf '%s' "$OUT" | jget '" ".join("%s=%s" % (c["key"], c["status"]) for c in sorted(d["claims"], key=lambda c: c["key"]))')"
assert_eq "lanes are named without local:" "w1:p1,w1:p2" \
  "$(printf '%s' "$OUT" | jget '",".join(c["lane"] for c in d["coverage"])')"
lg r2 local:w1:p2 '[]'
run "$HELPER" debate claims --rounds "$WORK/r1" "$WORK/r2"
assert_rc "with --rounds, two ledgers of one lane in one round are refused" 2
ln -s "$CL/p1.claims.json" "$WORK/link.claims.json"
run "$HELPER" debate claims "$WORK/link.claims.json"
assert_rc "a symlinked ledger is refused (policy)" 4
echo '["not", "a", "map"]' >"$WORK/badmap.json"
run "$HELPER" debate claims "$CL" --map "$WORK/badmap.json"
assert_rc "a malformed --map is refused" 2
run "$HELPER" debate claims "$WORK/empty-dir-does-not-exist"
assert_rc "a missing path is refused" 2
